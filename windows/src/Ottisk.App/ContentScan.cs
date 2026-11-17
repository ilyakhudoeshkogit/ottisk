using System;
using System.Collections.Generic;
using System.Threading;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Ottisk.Core;

namespace Ottisk.App;

/// <summary>
/// «Обрезать белые поля исходника»: снимок каждой страницы в низком разрешении → поиск непустой области
/// (Ottisk.Core.ContentBounds, порог 235 как на Mac) → общая рамка для страниц одного размера.
/// </summary>
public static class ContentScan
{
    /// <summary>Ширина снимка для поиска полей: ~1 пиксель на 0,5 мм у A4 — хватает и быстро.</summary>
    private const int ScanWidth = 420;
    /// <summary>Больше страниц не сканируем (остальные печатаются целиком) — чтобы не ждать вечно.</summary>
    public const int MaxPages = 400;

    public static Dictionary<int, Ottisk.Core.Rect> Compute(DocumentSource doc, CancellationToken ct)
    {
        var boxes = new Dictionary<int, Ottisk.Core.Rect>();
        var sizes = new Dictionary<int, SizeMm>();
        var n = Math.Min(doc.PageCount, MaxPages);
        for (var p = 1; p <= n; p++)
        {
            ct.ThrowIfCancellationRequested();
            var size = doc.PageSizeMm(p);
            sizes[p] = size;
            try
            {
                var (gray, w, h) = Grayscale(doc.RenderPage(p, ScanWidth));
                if (ContentBounds.Detect(gray, w, h) is { } px)
                    boxes[p] = ContentBounds.ToPage(px, w / size.W, size);
            }
            catch (Exception) when (!ct.IsCancellationRequested) { /* страницу не удалось снять — печатаем её целиком */ }
        }
        return ContentBounds.Unified(boxes, sizes);
    }

    /// <summary>Яркость 0–255 построчно; прозрачные места считаются белой бумагой.</summary>
    private static (byte[] gray, int w, int h) Grayscale(BitmapSource src)
    {
        if (src.PixelWidth > ScanWidth * 3 / 2)
        {
            var k = (double)ScanWidth / src.PixelWidth;
            var t = new TransformedBitmap(src, new ScaleTransform(k, k));
            t.Freeze();
            src = t;
        }
        var bgra = new FormatConvertedBitmap(src, PixelFormats.Bgra32, null, 0);
        bgra.Freeze();
        int w = bgra.PixelWidth, h = bgra.PixelHeight, stride = w * 4;
        var buf = new byte[stride * h];
        bgra.CopyPixels(buf, stride, 0);
        var gray = new byte[w * h];
        for (int i = 0, j = 0; i < gray.Length; i++, j += 4)
        {
            var lum = (buf[j + 2] * 299 + buf[j + 1] * 587 + buf[j] * 114) / 1000;
            var a = buf[j + 3];
            gray[i] = (byte)((lum * a + 255 * (255 - a)) / 255);
        }
        return (gray, w, h);
    }
}
