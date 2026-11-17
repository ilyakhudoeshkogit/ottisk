using System;
using System.Globalization;
using System.Threading;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Ottisk.Core;
using Rect = System.Windows.Rect;

namespace Ottisk.App;

/// <summary>Рисует одну сторону листа. Один и тот же код — для превью и для печати.</summary>
public static class SideRenderer
{
    public const double DipPerMm = 96.0 / 25.4;

    public static Rect ToRect(Ottisk.Core.Rect r) => new(r.X * DipPerMm, r.Y * DipPerMm, r.W * DipPerMm, r.H * DipPerMm);

    /// <summary>Страница целиком, когда рисуем только её непустую часть (обрезка белых полей).</summary>
    private static Ottisk.Core.Rect FullRect(Placement p, Ottisk.Core.Rect src, DocumentSource doc)
    {
        var page = doc.PageSizeMm(p.Page);
        var k = p.Target.W / src.W;
        return new Ottisk.Core.Rect(p.Target.X - src.X * k, p.Target.Y - src.Y * k, page.W * k, page.H * k);
    }

    /// <summary>Какой ширины растр страницы нужен для этой ячейки.</summary>
    public static int PixelWidth(Placement p, DocumentSource doc, double pixelsPerMm) =>
        (int)Math.Ceiling((p.Source is { } src ? FullRect(p, src, doc).W : p.Target.W) * pixelsPerMm);

    /// <summary>
    /// Заранее растрирует страницы стороны (в любом потоке) — тогда рисование на STA-потоке берёт их из кеша
    /// документа и не ждёт рендера PDF.
    /// </summary>
    public static void Prewarm(SideLayout side, DocumentSource doc, double dpi, CancellationToken ct)
    {
        foreach (var p in side.Placements)
        {
            ct.ThrowIfCancellationRequested();
            if (!p.IsBlank) doc.RenderPage(p.Page, PixelWidth(p, doc, dpi / 25.4));
        }
    }

    /// <param name="pixelsPerMm">Разрешение, с которым запрашиваем растр страницы (300 dpi ≈ 11.8).</param>
    /// <param name="guides">Только для превью: пунктир полей ГОСТ и отметки дырокола.</param>
    public static DrawingVisual Draw(SideLayout side, DocumentSource doc, double pixelsPerMm, bool mono, bool whiteBackground, bool guides = false)
    {
        var visual = new DrawingVisual();
        RenderOptions.SetBitmapScalingMode(visual, BitmapScalingMode.HighQuality);
        var w = side.Size.W * DipPerMm;
        var h = side.Size.H * DipPerMm;
        using (var dc = visual.RenderOpen())
        {
            if (whiteBackground) dc.DrawRectangle(Brushes.White, null, new Rect(0, 0, w, h));
            if (side.Rotate180) dc.PushTransform(new RotateTransform(180, w / 2, h / 2));
            foreach (var p in side.Placements)
            {
                if (p.IsBlank) continue;
                var target = ToRect(p.Target);
                if (p.Source is { } src)
                {
                    // Обрезка белых полей: рисуем страницу целиком в таком масштабе, чтобы её непустая часть
                    // легла ровно в Target, а всё лишнее отсекаем.
                    var full = FullRect(p, src, doc);
                    BitmapSource bmp = doc.RenderPage(p.Page, PixelWidth(p, doc, pixelsPerMm));
                    if (mono) bmp = Gray(bmp);
                    dc.PushClip(new RectangleGeometry(target));
                    dc.DrawImage(bmp, ToRect(full));
                    dc.Pop();
                }
                else
                {
                    BitmapSource bmp = doc.RenderPage(p.Page, PixelWidth(p, doc, pixelsPerMm));
                    if (mono) bmp = Gray(bmp);
                    dc.DrawImage(bmp, target);
                }
            }
            foreach (var m in side.Watermarks) DrawWatermark(dc, m);
            foreach (var l in side.Labels) DrawLabel(dc, l);
            if (side.Rotate180) dc.Pop();
            if (guides && side.Guide is { } g) DrawGuides(dc, side, g);
        }
        return visual;
    }

    private static readonly Typeface NumberFace = new(new FontFamily("Times New Roman"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
    private static readonly Typeface WatermarkFace = new(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);
    private const double DipPerPt = 96.0 / 72;

    private static FormattedText Text(string s, Typeface face, double pt, Brush brush) =>
        new(s, CultureInfo.GetCultureInfo("ru-RU"), FlowDirection.LeftToRight, face, pt * DipPerPt, brush, 1.0);

    /// <summary>Номер страницы: арабские цифры, точка привязки по выравниванию, по линии шрифта.</summary>
    private static void DrawLabel(DrawingContext dc, PageLabel l)
    {
        var ft = Text(l.Text, NumberFace, l.FontPt, Brushes.Black);
        var x = l.X * DipPerMm;
        x -= l.Align switch { LabelAlign.Center => ft.Width / 2, LabelAlign.Right => ft.Width, _ => 0 };
        dc.DrawText(ft, new Point(x, l.BaselineY * DipPerMm - ft.Baseline));
    }

    /// <summary>Водяной знак: светло-серый, полупрозрачный, по диагонали снизу-слева вверх-вправо, не вылезает за страницу.</summary>
    private static void DrawWatermark(DrawingContext dc, WatermarkMark m)
    {
        var brush = new SolidColorBrush(Color.FromRgb(0x80, 0x80, 0x80)) { Opacity = m.Opacity }; brush.Freeze();
        var ft = Text(m.Text, WatermarkFace, m.FontPt, brush);
        var cx = m.CenterX * DipPerMm; var cy = m.CenterY * DipPerMm;
        dc.PushClip(new RectangleGeometry(ToRect(m.Clip)));
        dc.PushTransform(new RotateTransform(-m.AngleDeg, cx, cy));   // против часовой стрелки
        dc.DrawText(ft, new Point(cx - ft.Width / 2, cy - ft.Height / 2));
        dc.Pop();
        dc.Pop();
    }

    private static void DrawGuides(DrawingContext dc, SideLayout side, Ottisk.Core.Rect g)
    {
        var blue = new SolidColorBrush(Color.FromArgb(200, 0x15, 0x65, 0xC0)); blue.Freeze();
        var pen = new Pen(blue, 1) { DashStyle = DashStyles.Dash }; pen.Freeze();
        dc.DrawRectangle(null, pen, ToRect(g));
        // Два отверстия дырокола (шаг 80 мм) посередине поля со стороны переплёта.
        var leftField = g.X >= side.Size.W - g.Right;
        var cx = (leftField ? g.X / 2 : (g.Right + side.Size.W) / 2) * DipPerMm;
        var cy = side.Size.H / 2 * DipPerMm;
        var hole = new SolidColorBrush(Color.FromArgb(90, 0x60, 0x7D, 0x8B)); hole.Freeze();
        foreach (var dy in new[] { -40.0, 40.0 })
            dc.DrawEllipse(hole, null, new Point(cx, cy + dy * DipPerMm), 3 * DipPerMm, 3 * DipPerMm);
    }

    private static BitmapSource Gray(BitmapSource s)
    {
        var g = new FormatConvertedBitmap(s, PixelFormats.Gray8, null, 0);
        g.Freeze();
        return g;
    }

    /// <summary>Растр стороны для превью.</summary>
    public static BitmapSource Preview(SideLayout side, DocumentSource doc, double dpi, bool mono)
    {
        var visual = Draw(side, doc, dpi / 25.4, mono, true, guides: true);
        var pw = (int)Math.Ceiling(side.Size.W / 25.4 * dpi);
        var ph = (int)Math.Ceiling(side.Size.H / 25.4 * dpi);
        var rtb = new RenderTargetBitmap(pw, ph, dpi, dpi, PixelFormats.Pbgra32);
        rtb.Render(visual);
        rtb.Freeze();
        return rtb;
    }
}
