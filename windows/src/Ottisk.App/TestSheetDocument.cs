using System;
using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Ottisk.Core;

namespace Ottisk.App;

/// <summary>«Документ» пробного листа: стр. 1 — лицо, стр. 2 — оборот. Крупная стрелка «ВЕРХ» и цифра.</summary>
public sealed class TestSheetDocument : DocumentSource
{
    private readonly SizeMm _size;

    public TestSheetDocument(SizeMm paper)
    {
        _size = paper.Portrait;
        Path = "Пробный лист.pdf";
    }

    public override int PageCount => 2;
    public override SizeMm PageSizeMm(int page) => _size;

    public override BitmapSource RenderPage(int page, int pixelWidth)
    {
        pixelWidth = Math.Clamp(pixelWidth, 50, 3000);
        var w = (double)pixelWidth;
        var h = Math.Round(w * _size.H / _size.W);
        var u = w / 100; // 1% ширины
        var ink = new SolidColorBrush(Color.FromRgb(0x26, 0x32, 0x38)); ink.Freeze();
        var pen = new Pen(ink, Math.Max(1, u * 0.6)); pen.Freeze();
        var face = new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);
        FormattedText Text(string s, double size) =>
            new(s, CultureInfo.GetCultureInfo("ru-RU"), FlowDirection.LeftToRight, face, size, ink, 1.0);

        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            dc.DrawRectangle(Brushes.White, null, new System.Windows.Rect(0, 0, w, h));
            dc.DrawRectangle(null, pen, new System.Windows.Rect(u * 2, u * 2, w - u * 4, h - u * 4));

            // Стрелка вверх
            var cx = w / 2;
            var arrow = new StreamGeometry();
            using (var g = arrow.Open())
            {
                g.BeginFigure(new Point(cx, u * 8), true, true);
                g.LineTo(new Point(cx + u * 18, u * 30), true, false);
                g.LineTo(new Point(cx + u * 7, u * 30), true, false);
                g.LineTo(new Point(cx + u * 7, u * 52), true, false);
                g.LineTo(new Point(cx - u * 7, u * 52), true, false);
                g.LineTo(new Point(cx - u * 7, u * 30), true, false);
                g.LineTo(new Point(cx - u * 18, u * 30), true, false);
            }
            arrow.Freeze();
            dc.DrawGeometry(ink, null, arrow);
            var top = Text("ВЕРХ", u * 9);
            dc.DrawText(top, new Point(cx - top.Width / 2, u * 54));

            var digit = Text(page.ToString(CultureInfo.InvariantCulture), u * 60);
            dc.DrawText(digit, new Point(cx - digit.Width / 2, h * 0.42));

            var caption = Text(page == 1 ? "Лицевая сторона" : "Обратная сторона", u * 5.5);
            dc.DrawText(caption, new Point(cx - caption.Width / 2, h - u * 22));
            var note = Text("Пробный лист Оттиска", u * 3.5);
            dc.DrawText(note, new Point(cx - note.Width / 2, h - u * 12));
        }
        var rtb = new RenderTargetBitmap(pixelWidth, (int)h, 96, 96, PixelFormats.Pbgra32);
        rtb.Render(visual);
        rtb.Freeze();
        return rtb;
    }
}
