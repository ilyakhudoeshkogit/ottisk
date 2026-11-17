namespace Ottisk.Core;

/// <summary>
/// Нумерация страниц (как в Mac-версии, OttiskCore/LayoutTypes.swift → PageNumbering).
/// Номер привязан к странице документа: страница p получает <c>StartAt + p - 1</c> — если перепечатать
/// одну страницу, номер на ней останется тем же. Первые <see cref="SkipFirst"/> страниц считаются,
/// но номер на них не ставится (титульный лист по ГОСТ 7.32-2017, п. 6.3.2).
/// </summary>
public sealed record PageNumbering(bool Enabled = false, int StartAt = 1, int SkipFirst = 0)
{
    public const int MaxStart = 999;
    public static readonly PageNumbering Off = new();
    /// <summary>ГОСТ 7.32-2017, п. 6.3.1–6.3.2: арабские цифры, внизу по центру, титул считается, но без номера.</summary>
    public static readonly PageNumbering Gost = new(true, 1, 1);

    /// <summary>Подпись для страницы документа (с 1) или null, если номер не ставится.</summary>
    public string? Label(int page)
    {
        if (!Enabled || page < 1 || page <= Math.Max(SkipFirst, 0)) return null;
        var n = Math.Clamp(StartAt, 0, MaxStart) + page - 1;
        return n.ToString(System.Globalization.CultureInfo.InvariantCulture);
    }
}

public enum LabelAlign { Left, Center, Right }

/// <summary>Надпись на стороне листа (номер страницы). X — точка привязки по <see cref="Align"/>, BaselineY — линия шрифта, мм от верха листа.</summary>
public sealed record PageLabel(string Text, double X, double BaselineY, double FontPt, LabelAlign Align = LabelAlign.Center)
{
    public static double PtToMm(double pt) => pt * 25.4 / 72;
}

/// <summary>Водяной знак (как Watermark.swift в Mac-версии): текст по диагонали, светло-серый, полупрозрачный.</summary>
public sealed record Watermark(string Text = "", double Opacity = 0.3, double AngleDeg = 45)
{
    public static readonly string[] Suggestions = { "ЧЕРНОВИК", "КОПИЯ", "ОБРАЗЕЦ" };
    public const double MinOpacity = 0.05, MaxOpacity = 0.6;
    /// <summary>Кегль ограничен 12–160 пт, как на Mac.</summary>
    public const double MinFontPt = 12, MaxFontPt = 160;

    public string Trimmed => (Text ?? "").Trim();
    public bool IsActive => Trimmed.Length > 0;
    public double ClampedOpacity => Math.Clamp(Opacity, MinOpacity, MaxOpacity);

    /// <summary>
    /// Кегль (пт), чтобы текст лёг по диагонали прямоугольника и не вылез за край.
    /// Ширина символа ≈0,62 кегля (жирный гротеск) — с запасом; текст занимает ~80 % длины диагонали.
    /// </summary>
    public double FontPt(double widthMm, double heightMm)
    {
        var len = Math.Max(Trimmed.Length, 1);
        var a = AngleDeg * Math.PI / 180;
        var cos = Math.Abs(Math.Cos(a)); var sin = Math.Abs(Math.Sin(a));
        var along = Math.Min(cos > 1e-4 ? widthMm / cos : double.PositiveInfinity,
                             sin > 1e-4 ? heightMm / sin : double.PositiveInfinity);
        var sizeMm = along * 0.8 / (len * 0.62);
        return Math.Clamp(sizeMm * 72 / 25.4, MinFontPt, MaxFontPt);
    }

    /// <summary>Где и как рисовать знак на странице: центр области, поворот против часовой стрелки.</summary>
    public WatermarkMark? Place(Rect area)
    {
        if (!IsActive || area.W <= 0 || area.H <= 0) return null;
        return new WatermarkMark(Trimmed, area.X + area.W / 2, area.Y + area.H / 2, AngleDeg,
            FontPt(area.W, area.H), ClampedOpacity, area);
    }
}

/// <summary>Готовый водяной знак на стороне листа. Центр в мм, угол против часовой стрелки, Clip — за его край не рисуем.</summary>
public sealed record WatermarkMark(string Text, double CenterX, double CenterY, double AngleDeg, double FontPt, double Opacity, Rect Clip);

/// <summary>Размер страницы и непустая часть страницы (для обрезки белых полей). null — брать страницу целиком.</summary>
public delegate Rect? ContentBoxProvider(int page);

/// <summary>Поиск непустой области на растровом снимке страницы (как ContentBounds в Mac-версии).</summary>
public static class ContentBounds
{
    public const byte DefaultThreshold = 235;
    public const int DefaultMinDark = 2;

    /// <param name="gray">Яркость пикселей построчно, первая строка — верх (0 — чёрный, 255 — белый).</param>
    /// <param name="threshold">Всё, что темнее, считается содержимым.</param>
    /// <param name="minDark">Сколько тёмных пикселей нужно в строке/столбце, чтобы не считать это пылинкой.</param>
    /// <returns>Прямоугольник в пикселях (начало слева сверху) или null для пустой страницы.</returns>
    public static Rect? Detect(byte[] gray, int width, int height, byte threshold = DefaultThreshold, int minDark = DefaultMinDark)
    {
        if (width <= 0 || height <= 0 || gray.Length < width * height) return null;
        var rows = new int[height];
        var cols = new int[width];
        for (var y = 0; y < height; y++)
        {
            var b = y * width;
            for (var x = 0; x < width; x++)
                if (gray[b + x] < threshold) { rows[y]++; cols[x]++; }
        }
        var top = Array.FindIndex(rows, c => c >= minDark);
        if (top < 0) return null;
        var bottom = Array.FindLastIndex(rows, c => c >= minDark);
        var left = Array.FindIndex(cols, c => c >= minDark);
        var right = Array.FindLastIndex(cols, c => c >= minDark);
        if (left < 0 || right < 0) return null;
        return new Rect(left, top, right - left + 1, bottom - top + 1);
    }

    /// <summary>Из пикселей снимка в мм страницы, с запасом <paramref name="paddingMm"/> со всех сторон, не выходя за страницу.</summary>
    public static Rect ToPage(Rect px, double pixelsPerMm, SizeMm page, double paddingMm = 1)
    {
        var x = px.X / pixelsPerMm - paddingMm;
        var y = px.Y / pixelsPerMm - paddingMm;
        var r = x + px.W / pixelsPerMm + 2 * paddingMm;
        var b = y + px.H / pixelsPerMm + 2 * paddingMm;
        x = Math.Max(0, x); y = Math.Max(0, y);
        r = Math.Min(page.W, r); b = Math.Min(page.H, b);
        return new Rect(x, y, Math.Max(0, r - x), Math.Max(0, b - y));
    }

    /// <summary>Общая рамка для страниц одного размера: тогда текст на всех листах стоит одинаково (как на Mac).</summary>
    public static Dictionary<int, Rect> Unified(IReadOnlyDictionary<int, Rect> boxes, IReadOnlyDictionary<int, SizeMm> sizes)
    {
        static string Key(SizeMm s) => $"{Math.Round(s.W)}x{Math.Round(s.H)}";
        var unions = new Dictionary<string, Rect>();
        foreach (var (page, box) in boxes)
        {
            if (!sizes.TryGetValue(page, out var size)) continue;
            var k = Key(size);
            unions[k] = unions.TryGetValue(k, out var u) ? Union(u, box) : box;
        }
        var result = new Dictionary<int, Rect>();
        foreach (var (page, size) in sizes)
            if (unions.TryGetValue(Key(size), out var u)) result[page] = u;
        return result;
    }

    public static Rect Union(Rect a, Rect b)
    {
        var x = Math.Min(a.X, b.X); var y = Math.Min(a.Y, b.Y);
        return new Rect(x, y, Math.Max(a.Right, b.Right) - x, Math.Max(a.Bottom, b.Bottom) - y);
    }

    /// <summary>Кусок страницы, который печатаем: непустая часть (если она разумная) или вся страница.</summary>
    public static Rect Crop(SizeMm page, Rect? box)
    {
        var full = new Rect(0, 0, page.W, page.H);
        if (box is not { } b || b.W < 1 || b.H < 1) return full;
        var x = Math.Max(0, b.X); var y = Math.Max(0, b.Y);
        var r = Math.Min(page.W, b.Right); var bt = Math.Min(page.H, b.Bottom);
        return r - x < 1 || bt - y < 1 ? full : new Rect(x, y, r - x, bt - y);
    }
}
