namespace Ottisk.Core;

/// <summary>Прямоугольник в миллиметрах, начало координат — левый верхний угол листа.</summary>
public readonly record struct Rect(double X, double Y, double W, double H)
{
    public double Right => X + W;
    public double Bottom => Y + H;
}

public readonly record struct SizeMm(double W, double H)
{
    public bool IsLandscape => W > H;
    public SizeMm Portrait => W <= H ? this : new SizeMm(H, W);
    public SizeMm Landscape => W >= H ? this : new SizeMm(H, W);
    public static readonly SizeMm A4 = new(210, 297);
}

/// <summary>Ячейка: номер страницы документа (с 1) или пустое место (Page = 0).</summary>
public readonly record struct PageSlot(int Page)
{
    public static readonly PageSlot Blank = new(0);
    public bool IsBlank => Page == 0;
    public static PageSlot Of(int page) => new(page);
}

public enum Parity { All, Odd, Even }

public enum PresetKind { Normal, Economy, DuplexManual, Booklet, OddOnly, EvenOnly, Gost }

/// <summary>Поля страницы в мм (от краёв листа).</summary>
public readonly record struct PageMargins(double Top, double Bottom, double Left, double Right)
{
    /// <summary>ГОСТ 7.32-2017, п. 6.1.1: левое 30, правое 15, верхнее и нижнее 20 мм (как в Mac-версии).</summary>
    public static readonly PageMargins Gost7_32 = new(20, 20, 30, 15);
}

/// <summary>Настройки одного задания — всё, что пользователь видит на экране.</summary>
public sealed record PrintOptions
{
    public int Copies { get; init; } = 1;
    /// <summary>Как ввёл человек: «1-3, 5». Пусто — все страницы.</summary>
    public string PageRangeText { get; init; } = "";
    public int PagesPerSheet { get; init; } = 1;
    public bool ManualDuplex { get; init; }
    public bool Booklet { get; init; }
    public Parity Parity { get; init; } = Parity.All;
    /// <summary>Поле под дырокол/подшивку слева, мм (0 — нет).</summary>
    public double GutterMm { get; init; }
    /// <summary>Лист выходит из принтера лицом вниз — обороты печатаются в обратном порядке.</summary>
    public bool ReverseBacks { get; init; } = true;
    /// <summary>Оборот выходит вверх ногами — повернуть его на 180°.</summary>
    public bool FlipBacks { get; init; }
    public double MarginMm { get; init; } = 6;
    public PresetKind Preset { get; init; } = PresetKind.Normal;
    /// <summary>Размер бумаги (A4 по умолчанию).</summary>
    public PaperKind Paper { get; init; } = PaperKind.A4;
    /// <summary>Точные поля (пресет ГОСТ). Если заданы — вместо <see cref="MarginMm"/> и <see cref="GutterMm"/>.</summary>
    public PageMargins? FixedMargins { get; init; }
    /// <summary>Номера страниц внизу по центру (0.3.0).</summary>
    public PageNumbering Numbering { get; init; } = PageNumbering.Off;
    /// <summary>Обрезать белые поля исходника: печатается только непустая часть страницы (0.3.0).</summary>
    public bool TrimWhite { get; init; }
    /// <summary>Водяной знак по диагонали; пустой текст — нет знака (0.3.0).</summary>
    public Watermark Watermark { get; init; } = new();
}

public static class Presets
{
    public static string Title(PresetKind k) => k switch
    {
        PresetKind.Normal => "Обычная",
        PresetKind.Economy => "Экономия бумаги — 2 на листе",
        PresetKind.DuplexManual => "С двух сторон (вручную)",
        PresetKind.Booklet => "Брошюра",
        PresetKind.OddOnly => "Только нечётные страницы",
        PresetKind.EvenOnly => "Только чётные страницы",
        PresetKind.Gost => "Курсовая / ГОСТ (поле под дырокол)",
        _ => k.ToString()
    };

    public static string Hint(PresetKind k) => k switch
    {
        PresetKind.Normal => "Одна страница на одной стороне листа",
        PresetKind.Economy => "Две страницы на одну сторону листа",
        PresetKind.DuplexManual => "Сначала одна сторона, потом переложите бумагу",
        PresetKind.Booklet => "Сложите листы пополам — получится книжка",
        PresetKind.OddOnly => "Страницы 1, 3, 5 …",
        PresetKind.EvenOnly => "Страницы 2, 4, 6 …",
        PresetKind.Gost => "Поля 30 / 15 / 20 / 20 мм по ГОСТ 7.32, слева место под дырокол",
        _ => ""
    };

    /// <summary>
    /// Применяет пресет, сохраняя копии, диапазон, поле и «аппаратные» галочки.
    /// «Курсовая / ГОСТ» включает номера страниц (титул без номера); при уходе с ГОСТ номера выключаются,
    /// в остальных случаях галочка «Номера страниц» остаётся как была.
    /// </summary>
    public static PrintOptions Apply(PresetKind k, PrintOptions current) => current with
    {
        Numbering = k == PresetKind.Gost ? PageNumbering.Gost
            : current.Preset == PresetKind.Gost ? current.Numbering with { Enabled = false }
            : current.Numbering,
        Preset = k,
        PagesPerSheet = k == PresetKind.Economy ? 2 : 1,
        ManualDuplex = k == PresetKind.DuplexManual,
        Booklet = k == PresetKind.Booklet,
        Parity = k == PresetKind.OddOnly ? Parity.Odd : k == PresetKind.EvenOnly ? Parity.Even : Parity.All,
        FixedMargins = k == PresetKind.Gost ? PageMargins.Gost7_32 : null,
    };

    /// <summary>Порядок пресетов на экране.</summary>
    public static readonly PresetKind[] Shown =
    {
        PresetKind.Normal, PresetKind.Economy, PresetKind.DuplexManual, PresetKind.Gost,
        PresetKind.Booklet, PresetKind.OddOnly, PresetKind.EvenOnly
    };

    /// <summary>Пресет сам задаёт поле слева — галочка «поле для дырокола» не нужна.</summary>
    public static bool HasOwnGutter(PresetKind k) => k == PresetKind.Gost;
}

/// <summary>Страница документа на стороне листа.</summary>
public sealed record Placement(int Page, Rect Cell, Rect Target)
{
    public bool IsBlank => Page == 0;
    /// <summary>Какая часть страницы (мм от её левого верхнего угла) попадает в <see cref="Target"/>. null — вся страница.</summary>
    public Rect? Source { get; init; }
}

/// <summary>Одна сторона листа бумаги.</summary>
public sealed record SideLayout(SizeMm Size, IReadOnlyList<Placement> Placements, bool IsBack, bool Rotate180, bool IsBlankSide)
{
    /// <summary>Граница полей для подсказки в превью (пресет ГОСТ); на печать не идёт.</summary>
    public Rect? Guide { get; init; }
    /// <summary>Номера страниц (рисуются и в превью, и в печати).</summary>
    public IReadOnlyList<PageLabel> Labels { get; init; } = Array.Empty<PageLabel>();
    /// <summary>Водяные знаки — по одному на страницу документа.</summary>
    public IReadOnlyList<WatermarkMark> Watermarks { get; init; } = Array.Empty<WatermarkMark>();
    public SideLayout Rotated => this with { Rotate180 = !Rotate180 };
}

/// <summary>Один проход через принтер (при ручной двусторонней их два).</summary>
public sealed record PrintPass(string Title, IReadOnlyList<SideLayout> Sides);

public sealed record JobPlan(SizeMm Sheet, IReadOnlyList<PrintPass> Passes)
{
    public int TotalSides => Passes.Sum(p => p.Sides.Count);
    public bool NeedsSecondPass => Passes.Count > 1;
    public static JobPlan Empty(SizeMm sheet) => new(sheet, Array.Empty<PrintPass>());
}
