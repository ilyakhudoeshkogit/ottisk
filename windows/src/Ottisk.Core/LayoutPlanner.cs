namespace Ottisk.Core;

/// <summary>Источник размеров страниц документа (в мм).</summary>
public delegate SizeMm PageSizeProvider(int page);

/// <summary>
/// Вся геометрия печати: что, где и в каком масштабе окажется на каждой стороне листа.
/// Чистая логика без Windows — её проверяют тесты, а рисует приложение.
/// </summary>
public static class LayoutPlanner
{
    public const double CellGapMm = 4;
    /// <summary>Номер страницы на листе с одной страницей: 12 пт, как на Mac.</summary>
    public const double NumberFontPt = 12;
    /// <summary>Номер под каждой страницей при нескольких на листе / в брошюре: 7 пт, под него ячейка ужимается на 4,5 мм.</summary>
    public const double SmallNumberFontPt = 7;
    public const double SmallNumberGapMm = 4.5;
    public static readonly int[] AllowedPerSheet = { 1, 2, 4, 6, 9 };

    public static IReadOnlyList<PageSlot> Sequence(IReadOnlyList<int> selected, Parity parity)
    {
        IEnumerable<int> f = parity switch
        {
            Parity.Odd => selected.Where(p => p % 2 == 1),
            Parity.Even => selected.Where(p => p % 2 == 0),
            _ => selected
        };
        return f.Select(PageSlot.Of).ToList();
    }

    /// <summary>Лист берётся из <see cref="PrintOptions.Paper"/>.</summary>
    public static JobPlan Plan(int pageCount, PageSizeProvider sizeOf, PrintOptions o, ContentBoxProvider? contentOf = null)
        => Plan(pageCount, sizeOf, o, Papers.Size(o.Paper), contentOf);

    public static JobPlan Plan(int pageCount, PageSizeProvider sizeOf, PrintOptions o, SizeMm sheetBase, ContentBoxProvider? contentOf = null)
    {
        var selected = PageRange.Parse(o.PageRangeText, pageCount);
        var slots = Sequence(selected, o.Parity);
        if (slots.Count == 0) throw new PageRangeException(
            o.Parity == Parity.Odd ? "В выбранных страницах нет нечётных"
            : o.Parity == Parity.Even ? "В выбранных страницах нет чётных" : "Нет страниц для печати");
        return Plan(slots, sizeOf, o, sheetBase, contentOf);
    }

    /// <param name="contentOf">Непустая часть страницы (для «Обрезать белые поля»); учитывается, только если <see cref="PrintOptions.TrimWhite"/>.</param>
    public static JobPlan Plan(IReadOnlyList<PageSlot> slots, PageSizeProvider sizeOf, PrintOptions o, SizeMm sheetBase, ContentBoxProvider? contentOf = null)
    {
        if (slots.Count == 0) return JobPlan.Empty(sheetBase);
        var copies = Math.Clamp(o.Copies, 1, 99);
        var firstPage = slots.First(s => !s.IsBlank).Page;
        var rep = sizeOf(firstPage);

        if (o.Booklet) return PlanBooklet(slots, sizeOf, o, sheetBase, copies, contentOf);

        var n = AllowedPerSheet.Contains(o.PagesPerSheet) ? o.PagesPerSheet : 1;
        var duplex = o.ManualDuplex;
        // Лист и сетка постоянны на всё задание — иначе принтер получит смесь ориентаций.
        var (sheet, cols, rows) = o.FixedMargins is { } fm
            ? ChooseGrid(n, rep, sheetBase, fm)
            : ChooseGrid(n, rep, sheetBase, o.MarginMm, o.GutterMm);

        var groups = new List<PageSlot[]>();
        for (var i = 0; i < slots.Count; i += n)
        {
            var g = new PageSlot[n];
            for (var j = 0; j < n; j++) g[j] = i + j < slots.Count ? slots[i + j] : PageSlot.Blank;
            groups.Add(g);
        }

        SideLayout Build(int sideIndex)
        {
            var isBack = duplex && sideIndex % 2 == 1;
            var area = Area(o, sheet, isBack, duplex);
            var small = n > 1 && o.Numbering.Enabled;
            var cells = GridCells(area, cols, rows).Select(c => small ? ShrinkForNumber(c) : c).ToList();
            var pl = new List<Placement>();
            // ГОСТ: страница прижата к левому верхнему углу полей — поле под дырокол не «расползается».
            var topLeft = o.FixedMargins != null;
            // ГОСТ + обрезка: текст не увеличиваем — кегль остаётся как в файле (как «заменить поля» на Mac).
            var maxScale = topLeft && o.TrimWhite && n == 1 ? 1.0 : double.PositiveInfinity;
            for (var k = 0; k < n; k++)
            {
                var s = groups[sideIndex][k];
                pl.Add(s.IsBlank ? new Placement(0, cells[k], cells[k])
                    : Fit(s.Page, sizeOf(s.Page), cells[k], topLeft, CropOf(s.Page, sizeOf, o, contentOf), maxScale));
            }
            return Decorate(new SideLayout(sheet, pl, isBack, false, false) { Guide = o.FixedMargins != null ? area : null }, o, area, single: n == 1);
        }

        var sides = Enumerable.Range(0, groups.Count).Select(Build).ToList();
        if (!duplex)
            return OnePass(sheet, sides, copies);
        // Сторона листа i (с 1): нечётные — лица, чётные — обороты. Номера идут по порядку сторон.
        var plan = DuplexPlanner.Plan(Enumerable.Range(1, sides.Count).ToList(), o.ReverseBacks, copies);
        return TwoPasses(sheet, sides, plan, o.FlipBacks);
    }

    private static JobPlan OnePass(SizeMm sheet, List<SideLayout> sides, int copies)
    {
        var all = new List<SideLayout>();
        for (var c = 0; c < copies; c++) all.AddRange(sides);
        return new JobPlan(sheet, new[] { new PrintPass("Печать", all) });
    }

    private static JobPlan TwoPasses(SizeMm sheet, List<SideLayout> sides, DuplexPlan plan, bool flipBacks)
    {
        SideLayout Blank(bool back) => new(sheet, Array.Empty<Placement>(), back, false, true);
        SideLayout Get(PageSlot s, bool back)
        {
            if (s.IsBlank) return Blank(back);
            var side = sides[s.Page - 1];
            return back && (flipBacks) ? side.Rotated : side;
        }
        var fronts = plan.Fronts.Select(s => Get(s, false)).ToList();
        if (!plan.NeedsSecondPass)
            return new JobPlan(sheet, new[] { new PrintPass("Печать", fronts) });
        var backs = plan.Backs.Select(s => Get(s, true)).ToList();
        return new JobPlan(sheet, new[]
        {
            new PrintPass("Первая сторона (лицевая)", fronts),
            new PrintPass("Вторая сторона (оборот)", backs)
        });
    }

    private static JobPlan PlanBooklet(IReadOnlyList<PageSlot> slots, PageSizeProvider sizeOf, PrintOptions o, SizeMm sheetBase, int copies, ContentBoxProvider? contentOf)
    {
        var sheet = sheetBase.Landscape;
        var pages = slots.Where(s => !s.IsBlank).Select(s => s.Page).ToList();
        var bs = BookletPlanner.Sides(pages);
        var m = Math.Max(o.MarginMm, 4);
        var area = new Rect(m, m, sheet.W - 2 * m, sheet.H - 2 * m);
        var cells = new[] { new Rect(area.X, area.Y, area.W / 2, area.H), new Rect(area.X + area.W / 2, area.Y, area.W / 2, area.H) };
        if (o.Numbering.Enabled) cells = cells.Select(ShrinkForNumber).ToArray();
        var sides = new List<SideLayout>();
        for (var i = 0; i < bs.Count; i++)
        {
            var pair = new[] { bs[i].Left, bs[i].Right };
            var pl = new List<Placement>();
            for (var k = 0; k < 2; k++)
                pl.Add(pair[k].IsBlank ? new Placement(0, cells[k], cells[k])
                    : Fit(pair[k].Page, sizeOf(pair[k].Page), cells[k], false, CropOf(pair[k].Page, sizeOf, o, contentOf)));
            sides.Add(Decorate(new SideLayout(sheet, pl, i % 2 == 1, false, false), o, area, single: false));
        }
        var dp = DuplexPlanner.BookletPasses(sides.Count, o.ReverseBacks, copies);
        return TwoPasses(sheet, sides, dp, o.FlipBacks);
    }

    /// <summary>Область печати стороны. На обороте при ручной двусторонней поле под дырокол зеркалится вправо.</summary>
    public static Rect Area(PrintOptions o, SizeMm sheet, bool isBack, bool mirror)
    {
        double t, b, l, r;
        if (o.FixedMargins is { } m)
        {
            (t, b, l, r) = (m.Top, m.Bottom, m.Left, m.Right);
            if (mirror && isBack) (l, r) = (r, l);
        }
        else
        {
            t = b = l = r = o.MarginMm;
            var g = Math.Clamp(o.GutterMm, 0, 60);
            if (mirror && isBack) r += g; else l += g;
        }
        return new Rect(l, t, Math.Max(1, sheet.W - l - r), Math.Max(1, sheet.H - t - b));
    }

    /// <summary>
    /// Вписывает страницу (или её кусок <paramref name="source"/>) в ячейку с сохранением пропорций:
    /// по центру или в левый верхний угол. <paramref name="maxScale"/> — не увеличивать сильнее.
    /// </summary>
    public static Placement Fit(int page, SizeMm pageSize, Rect cell, bool topLeft = false, Rect? source = null, double maxScale = double.PositiveInfinity)
    {
        if (pageSize.W <= 0 || pageSize.H <= 0) return new Placement(page, cell, cell);
        var src = source is { W: > 0, H: > 0 } r ? r : new Rect(0, 0, pageSize.W, pageSize.H);
        var scale = Math.Min(Math.Min(cell.W / src.W, cell.H / src.H), maxScale);
        var w = src.W * scale;
        var h = src.H * scale;
        var target = topLeft
            ? new Rect(cell.X, cell.Y, w, h)
            : new Rect(cell.X + (cell.W - w) / 2, cell.Y + (cell.H - h) / 2, w, h);
        return new Placement(page, cell, target) { Source = source is { W: > 0, H: > 0 } ? src : null };
    }

    /// <summary>Какой кусок страницы печатать: с «Обрезать белые поля» — непустую часть, иначе null (всю).</summary>
    public static Rect? CropOf(int page, PageSizeProvider sizeOf, PrintOptions o, ContentBoxProvider? contentOf)
    {
        if (!o.TrimWhite || contentOf == null) return null;
        var size = sizeOf(page);
        var box = contentOf(page);
        if (box == null) return null;
        var c = ContentBounds.Crop(size, box);
        return c == new Rect(0, 0, size.W, size.H) ? null : c;
    }

    /// <summary>Ячейка без полоски снизу под мелкий номер страницы.</summary>
    public static Rect ShrinkForNumber(Rect cell) => cell with { H = Math.Max(1, cell.H - SmallNumberGapMm) };

    /// <summary>
    /// Номера страниц и водяные знаки для стороны.
    /// Одна страница на листе — номер 12 пт внизу по центру области печати, посередине нижнего поля (не ниже 5 мм от края), как на Mac.
    /// Несколько страниц / брошюра — 7 пт под каждой страницей.
    /// </summary>
    public static SideLayout Decorate(SideLayout side, PrintOptions o, Rect area, bool single)
    {
        var labels = new List<PageLabel>();
        var marks = new List<WatermarkMark>();
        foreach (var p in side.Placements)
        {
            if (p.IsBlank) continue;
            if (o.Numbering.Label(p.Page) is { } text)
            {
                if (single)
                {
                    var bottomMargin = side.Size.H - area.Bottom;
                    labels.Add(new PageLabel(text, area.X + area.W / 2, side.Size.H - Math.Max(bottomMargin / 2, 5), NumberFontPt));
                }
                else
                    labels.Add(new PageLabel(text, p.Cell.X + p.Cell.W / 2, p.Cell.Bottom + 3.2, SmallNumberFontPt));
            }
            if (o.Watermark.Place(p.Target) is { } m) marks.Add(m);
        }
        return labels.Count == 0 && marks.Count == 0 ? side : side with { Labels = labels, Watermarks = marks };
    }

    /// <summary>Сетка при точных полях (ГОСТ): лист и раскладка, где страница крупнее.</summary>
    public static (SizeMm sheet, int cols, int rows) ChooseGrid(int n, SizeMm page, SizeMm sheetBase, PageMargins m)
    {
        if (n == 1) return (page.IsLandscape ? sheetBase.Landscape : sheetBase.Portrait, 1, 1);
        // Для нескольких страниц на листе считаем «самое широкое» поле со всех сторон — проще и безопасно.
        var margin = Math.Max(Math.Max(m.Top, m.Bottom), m.Right);
        return ChooseGrid(n, page, sheetBase, margin, Math.Max(0, m.Left - margin));
    }

    /// <summary>Выбирает ориентацию листа и сетку, при которых страница получается крупнее всего.</summary>
    public static (SizeMm sheet, int cols, int rows) ChooseGrid(int n, SizeMm page, SizeMm sheetBase, double margin, double gutter)
    {
        if (n == 1)
            return (page.IsLandscape ? sheetBase.Landscape : sheetBase.Portrait, 1, 1);
        (SizeMm, int, int)? best = null;
        var bestScale = -1.0;
        foreach (var s in new[] { sheetBase.Portrait, sheetBase.Landscape })
        {
            var aw = s.W - 2 * margin - Math.Clamp(gutter, 0, 60);
            var ah = s.H - 2 * margin;
            for (var c = 1; c <= n; c++)
            {
                if (n % c != 0) continue;
                var r = n / c;
                var cw = (aw - CellGapMm * (c - 1)) / c;
                var ch = (ah - CellGapMm * (r - 1)) / r;
                if (cw <= 0 || ch <= 0 || page.W <= 0 || page.H <= 0) continue;
                var scale = Math.Min(cw / page.W, ch / page.H);
                if (scale > bestScale + 1e-9) { bestScale = scale; best = (s, c, r); }
            }
        }
        return best ?? (sheetBase.Portrait, 1, n);
    }

    public static IReadOnlyList<Rect> GridCells(Rect a, int cols, int rows)
    {
        var cw = (a.W - CellGapMm * (cols - 1)) / cols;
        var ch = (a.H - CellGapMm * (rows - 1)) / rows;
        var list = new List<Rect>();
        for (var r = 0; r < rows; r++)
            for (var c = 0; c < cols; c++)
                list.Add(new Rect(a.X + c * (cw + CellGapMm), a.Y + r * (ch + CellGapMm), cw, ch));
        return list;
    }
}
