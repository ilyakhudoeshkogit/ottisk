using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Ottisk.Core;
using Windows.Data.Pdf;
using Windows.Storage;
using Windows.Storage.Streams;

namespace Ottisk.App;

/// <summary>Сообщение для человека: показываем как есть, без технических деталей.</summary>
public sealed class FriendlyException : Exception
{
    public FriendlyException(string message) : base(message) { }
}

/// <summary>Документ для печати: PDF или картинка. Страницы отдаёт как растр нужного размера.</summary>
public abstract class DocumentSource : IDisposable
{
    public string Path { get; protected set; } = "";
    public string FileName => System.IO.Path.GetFileName(Path);
    public abstract int PageCount { get; }
    /// <summary>Размер страницы в мм (только пропорции важны для раскладки).</summary>
    public abstract SizeMm PageSizeMm(int page);
    /// <summary>Рисует страницу (с 1) шириной <paramref name="pixelWidth"/>. Вызывается из любого потока.</summary>
    public abstract BitmapSource RenderPage(int page, int pixelWidth);
    public virtual void Dispose() { }

    public static readonly string[] ImageExt = { ".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tif", ".tiff" };
    public static readonly string[] OfficeExt = { ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".odt", ".rtf", ".txt" };

    public static DocumentSource Open(string path)
    {
        var ext = System.IO.Path.GetExtension(path).ToLowerInvariant();
        if (!File.Exists(path)) throw new FriendlyException("Файл не найден.");
        if (ext == ".pdf") return PdfSource.Load(path);
        if (Array.IndexOf(ImageExt, ext) >= 0) return new ImageDocument(path);
        if (Array.IndexOf(OfficeExt, ext) >= 0)
            throw new FriendlyException("Документы Word и Excel этот файл напрямую не откроются.\n\n" +
                "Откройте его в Word (или Excel), выберите «Файл → Сохранить как → PDF», " +
                "а потом откройте получившийся PDF здесь.");
        throw new FriendlyException("Такой тип файла не поддерживается. Можно открыть PDF и фото (JPG, PNG).");
    }
}

public sealed class PdfSource : DocumentSource
{
    private PdfDocument _doc = null!;
    private SizeMm[] _sizes = Array.Empty<SizeMm>();
    private readonly object _lock = new();

    public override int PageCount => _sizes.Length;
    public override SizeMm PageSizeMm(int page) => _sizes[Math.Clamp(page, 1, _sizes.Length) - 1];

    public static PdfSource Load(string path)
    {
        var s = new PdfSource { Path = path };
        try
        {
            var file = StorageFile.GetFileFromPathAsync(path).AsTask().GetAwaiter().GetResult();
            s._doc = PdfDocument.LoadFromFileAsync(file).AsTask().GetAwaiter().GetResult();
        }
        catch (Exception ex) when (ex is not FriendlyException)
        {
            throw new FriendlyException("Не удалось открыть PDF. Возможно, файл повреждён или защищён паролем.");
        }
        if (s._doc.IsPasswordProtected)
            throw new FriendlyException("Этот PDF защищён паролем. Снимите защиту и откройте его снова.");
        var n = (int)s._doc.PageCount;
        if (n == 0) throw new FriendlyException("В этом PDF нет страниц.");
        s._sizes = new SizeMm[n];
        for (var i = 0; i < n; i++)
        {
            using var p = s._doc.GetPage((uint)i);
            // Size — в 1/96 дюйма.
            s._sizes[i] = new SizeMm(p.Size.Width * 25.4 / 96, p.Size.Height * 25.4 / 96);
        }
        return s;
    }

    /// <summary>Недавние растры для превью (страница, ширина): переключение галочек и листание не рендерят PDF заново.</summary>
    private readonly BitmapCache _cache = new(maxItems: 32, maxPixelWidth: 1800);

    public override BitmapSource RenderPage(int page, int pixelWidth)
    {
        pixelWidth = Math.Clamp(pixelWidth, 50, 6000);
        if (_cache.TryGet(page, pixelWidth, out var hit)) return hit;
        var bmp = RenderUncached(page, pixelWidth);
        _cache.Add(page, pixelWidth, bmp);
        return bmp;
    }

    private BitmapSource RenderUncached(int page, int pixelWidth)
    {
        var sz = PageSizeMm(page);
        var h = (uint)Math.Max(1, Math.Round(pixelWidth * sz.H / sz.W));
        lock (_lock)
        {
            using var p = _doc.GetPage((uint)(page - 1));
            using var ms = new InMemoryRandomAccessStream();
            var opt = new PdfPageRenderOptions
            {
                DestinationWidth = (uint)pixelWidth,
                DestinationHeight = h,
                BackgroundColor = global::Windows.UI.Color.FromArgb(255, 255, 255, 255)
            };
            p.RenderToStreamAsync(ms, opt).AsTask().GetAwaiter().GetResult();
            ms.Seek(0);
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.StreamSource = ms.AsStreamForRead();
            bmp.EndInit();
            bmp.Freeze();
            return bmp;
        }
    }
}

public sealed class ImageDocument : DocumentSource
{
    private readonly BitmapSource _bmp;
    public override int PageCount => 1;

    public ImageDocument(string path)
    {
        Path = path;
        try
        {
            var bytes = File.ReadAllBytes(path);
            var frame = BitmapFrame.Create(new MemoryStream(bytes), BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            BitmapSource src = frame;
            try
            {
                if (frame.Metadata is BitmapMetadata md && md.GetQuery("/app1/ifd/{ushort=274}") is ushort o)
                {
                    var angle = o switch { 3 => 180, 6 => 90, 8 => 270, _ => 0 };
                    if (angle != 0) src = new TransformedBitmap(frame, new RotateTransform(angle));
                }
            }
            catch { /* нет EXIF — не страшно */ }
            src.Freeze();
            _bmp = src;
        }
        catch
        {
            throw new FriendlyException("Не удалось открыть картинку. Возможно, файл повреждён.");
        }
    }

    public override SizeMm PageSizeMm(int page) =>
        new(_bmp.PixelWidth * 25.4 / 96, _bmp.PixelHeight * 25.4 / 96);

    private readonly BitmapCache _scaled = new(maxItems: 4, maxPixelWidth: 4000);

    /// <summary>
    /// Для превью большое фото заранее уменьшаем (и запоминаем) — рисовать 12-мегапиксельный снимок
    /// в маленькую картинку на каждый пересчёт слишком медленно. Для печати отдаём оригинал.
    /// </summary>
    public override BitmapSource RenderPage(int page, int pixelWidth)
    {
        if (pixelWidth <= 0 || pixelWidth * 3 / 2 >= _bmp.PixelWidth) return _bmp;
        var bucket = Math.Max(64, (pixelWidth + 63) / 64 * 64);
        if (_scaled.TryGet(1, bucket, out var hit)) return hit;
        var k = (double)bucket / _bmp.PixelWidth;
        var t = new TransformedBitmap(_bmp, new ScaleTransform(k, k));
        var small = new WriteableBitmap(t);
        small.Freeze();
        _scaled.Add(1, bucket, small);
        return small;
    }
}

/// <summary>Маленький потокобезопасный LRU-кеш растров страниц.</summary>
public sealed class BitmapCache
{
    private readonly int _maxItems;
    private readonly int _maxPixelWidth;
    private readonly object _lock = new();
    private readonly Dictionary<(int page, int width), LinkedListNode<((int, int) key, BitmapSource bmp)>> _map = new();
    private readonly LinkedList<((int, int) key, BitmapSource bmp)> _order = new();

    public BitmapCache(int maxItems, int maxPixelWidth) { _maxItems = maxItems; _maxPixelWidth = maxPixelWidth; }

    public bool TryGet(int page, int width, out BitmapSource bmp)
    {
        lock (_lock)
        {
            if (_map.TryGetValue((page, width), out var node))
            {
                _order.Remove(node);
                _order.AddFirst(node);
                bmp = node.Value.bmp;
                return true;
            }
        }
        bmp = null!;
        return false;
    }

    public void Add(int page, int width, BitmapSource bmp)
    {
        if (width > _maxPixelWidth || !bmp.IsFrozen) return;
        lock (_lock)
        {
            if (_map.ContainsKey((page, width))) return;
            _map[(page, width)] = _order.AddFirst(((page, width), bmp));
            while (_order.Count > _maxItems)
            {
                var last = _order.Last!;
                _order.RemoveLast();
                _map.Remove(last.Value.key);
            }
        }
    }

    public int Count { get { lock (_lock) return _order.Count; } }
}
