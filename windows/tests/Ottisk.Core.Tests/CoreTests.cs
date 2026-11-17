using Ottisk.Core;

namespace Ottisk.Core.Tests;

public class PageRangeTests
{
    [Fact] public void EmptyMeansAll() => Assert.Equal(new[] { 1, 2, 3, 4 }, PageRange.Parse("", 4));
    [Fact] public void Mixed() => Assert.Equal(new[] { 1, 2, 3, 5, 8, 9, 10 }, PageRange.Parse("1-3, 5, 8-", 10));
    [Fact] public void OpenStart() => Assert.Equal(new[] { 1, 2, 3 }, PageRange.Parse("-3", 10));
    [Fact] public void EmDashAndSemicolon() => Assert.Equal(new[] { 2, 3, 4, 7 }, PageRange.Parse("2—4; 7", 10));
    [Fact] public void Dedupe() => Assert.Equal(new[] { 1, 2, 3 }, PageRange.Parse("3,1-2,2", 5));
    [Theory]
    [InlineData("abc")] [InlineData("1-2-3")] [InlineData("0")] [InlineData("5-2")] [InlineData("11")] [InlineData("2-11")]
    public void Bad(string t) => Assert.Throws<PageRangeException>(() => PageRange.Parse(t, 10));
    [Fact] public void NoPages() => Assert.Throws<PageRangeException>(() => PageRange.Parse("", 0));
    [Fact] public void MessageIsRussian()
    {
        var e = Assert.Throws<PageRangeException>(() => PageRange.Parse("20", 10));
        Assert.Contains("в документе 10", e.Message);
    }
}

public class DuplexTests
{
    static int[] P(params PageSlot[] s) => s.Select(x => x.Page).ToArray();

    [Fact] public void Four_Reversed()
    {
        var p = DuplexPlanner.Plan(new[] { 1, 2, 3, 4 });
        Assert.Equal(new[] { 1, 3 }, P(p.Fronts.ToArray()));
        Assert.Equal(new[] { 4, 2 }, P(p.Backs.ToArray()));
        Assert.Equal(2, p.SheetCount);
    }
    [Fact] public void Odd_PadsBlankFirstInReversedBacks()
    {
        var p = DuplexPlanner.Plan(new[] { 1, 2, 3, 4, 5 });
        Assert.Equal(new[] { 1, 3, 5 }, P(p.Fronts.ToArray()));
        Assert.Equal(new[] { 0, 4, 2 }, P(p.Backs.ToArray()));
    }
    [Fact] public void NotReversed()
    {
        var p = DuplexPlanner.Plan(new[] { 1, 2, 3, 4 }, reverseBacks: false);
        Assert.Equal(new[] { 2, 4 }, P(p.Backs.ToArray()));
    }
    [Fact] public void SinglePage_NoSecondPass()
    {
        var p = DuplexPlanner.Plan(new[] { 7 });
        Assert.False(p.NeedsSecondPass);
        Assert.Single(p.Fronts);
    }
    [Fact] public void Empty() => Assert.Equal(0, DuplexPlanner.Plan(Array.Empty<int>()).SheetCount);
    [Fact] public void TwoCopies_BacksReversedAsOneStack()
    {
        var p = DuplexPlanner.Plan(new[] { 1, 2, 3, 4 }, copies: 2);
        Assert.Equal(new[] { 1, 3, 1, 3 }, P(p.Fronts.ToArray()));
        // стопка: сверху лист копии 2 (оборот 4), потом оборот 2, потом копия 1
        Assert.Equal(new[] { 4, 2, 4, 2 }, P(p.Backs.ToArray()));
        Assert.Equal(4, p.SheetCount);
    }
    [Fact] public void SelectedNonContiguousPages()
    {
        var p = DuplexPlanner.Plan(new[] { 2, 5, 9 });
        Assert.Equal(new[] { 2, 9 }, P(p.Fronts.ToArray()));
        Assert.Equal(new[] { 0, 5 }, P(p.Backs.ToArray()));
    }
    [Fact] public void BookletPasses_8sides()
    {
        var p = DuplexPlanner.BookletPasses(8);
        Assert.Equal(new[] { 1, 3, 5, 7 }, P(p.Fronts.ToArray()));
        Assert.Equal(new[] { 8, 6, 4, 2 }, P(p.Backs.ToArray()));
    }
    [Fact] public void Gate()
    {
        var g = new DuplexGate();
        Assert.False(g.CanPrintBacks);
        g.Update(1); Assert.False(g.CanPrintBacks);
        g.Update(0); Assert.True(g.CanPrintBacks);
    }
}

public class BookletTests
{
    [Fact] public void Eight()
    {
        var s = BookletPlanner.Sides(Enumerable.Range(1, 8).ToList());
        Assert.Equal(4, s.Count);
        Assert.Equal((8, 1), (s[0].Left.Page, s[0].Right.Page));
        Assert.Equal((2, 7), (s[1].Left.Page, s[1].Right.Page));
        Assert.Equal((6, 3), (s[2].Left.Page, s[2].Right.Page));
        Assert.Equal((4, 5), (s[3].Left.Page, s[3].Right.Page));
    }
    [Fact] public void PadsToMultipleOfFour()
    {
        Assert.Equal(8, BookletPlanner.PaddedCount(5));
        var s = BookletPlanner.Sides(new[] { 1, 2, 3, 4, 5 });
        // страниц 5 → 8: пустые в конце (6,7,8)
        Assert.True(s[0].Left.IsBlank);          // позиция 8
        Assert.Equal(1, s[0].Right.Page);
        Assert.Equal(2, s[1].Left.Page);
        Assert.True(s[1].Right.IsBlank);         // позиция 7
        Assert.True(s[2].Left.IsBlank);          // 6
        Assert.Equal(3, s[2].Right.Page);
        Assert.Equal(4, s[3].Left.Page);
        Assert.Equal(5, s[3].Right.Page);
    }
    [Fact] public void Zero() => Assert.Empty(BookletPlanner.Sides(Array.Empty<int>()));
}

public class LayoutTests
{
    static readonly PageSizeProvider A4 = _ => new SizeMm(210, 297);
    static PrintOptions Opt(PresetKind k, string range = "", int copies = 1)
        => Presets.Apply(k, new PrintOptions { PageRangeText = range, Copies = copies });

    [Fact] public void Normal_OnePagePerSide()
    {
        var plan = LayoutPlanner.Plan(3, A4, Opt(PresetKind.Normal), SizeMm.A4);
        Assert.Single(plan.Passes);
        Assert.Equal(3, plan.Passes[0].Sides.Count);
        var side = plan.Passes[0].Sides[0];
        Assert.Equal(210, side.Size.W);
        var t = side.Placements[0].Target;
        Assert.InRange(t.X, 5.9, 6.1);   // вписано в поля 6 мм
        Assert.True(t.Right <= 210 - 5.9);
    }
    [Fact] public void Normal_Copies_Repeats()
    {
        var plan = LayoutPlanner.Plan(2, A4, Opt(PresetKind.Normal, copies: 3), SizeMm.A4);
        Assert.Equal(6, plan.Passes[0].Sides.Count);
    }
    [Fact] public void Economy_TwoUp_Landscape()
    {
        var plan = LayoutPlanner.Plan(5, A4, Opt(PresetKind.Economy), SizeMm.A4);
        var sides = plan.Passes[0].Sides;
        Assert.Equal(3, sides.Count);                 // 2+2+1
        Assert.True(sides[0].Size.IsLandscape);       // портретные A4 лучше «лежат» на альбомном листе
        Assert.Equal(2, sides[0].Placements.Count);
        Assert.Equal(5, sides[2].Placements[0].Page);
        Assert.True(sides[2].Placements[1].IsBlank);
        var a = sides[0].Placements[0].Target; var b = sides[0].Placements[1].Target;
        Assert.True(a.Right <= b.X);                  // страницы не перекрываются
    }
    [Fact] public void ManualDuplex_TwoPasses_ReverseBacks()
    {
        var plan = LayoutPlanner.Plan(4, A4, Opt(PresetKind.DuplexManual), SizeMm.A4);
        Assert.Equal(2, plan.Passes.Count);
        Assert.Equal(new[] { 1, 3 }, plan.Passes[0].Sides.Select(s => s.Placements[0].Page));
        Assert.Equal(new[] { 4, 2 }, plan.Passes[1].Sides.Select(s => s.Placements[0].Page));
        Assert.All(plan.Passes[1].Sides, s => Assert.True(s.IsBack));
    }
    [Fact] public void ManualDuplex_OddPages_BlankBackKeepsSheetCount()
    {
        var plan = LayoutPlanner.Plan(3, A4, Opt(PresetKind.DuplexManual), SizeMm.A4);
        Assert.Equal(2, plan.Passes[0].Sides.Count);
        Assert.Equal(2, plan.Passes[1].Sides.Count);
        Assert.True(plan.Passes[1].Sides[0].IsBlankSide);
        Assert.Equal(2, plan.Passes[1].Sides[1].Placements[0].Page);
    }
    [Fact] public void ManualDuplex_FlipBacks_RotatesOnlyBacks()
    {
        var o = Opt(PresetKind.DuplexManual) with { FlipBacks = true };
        var plan = LayoutPlanner.Plan(4, A4, o, SizeMm.A4);
        Assert.All(plan.Passes[0].Sides, s => Assert.False(s.Rotate180));
        Assert.All(plan.Passes[1].Sides, s => Assert.True(s.Rotate180));
    }
    [Fact] public void ManualDuplex_SingleSheet_OnePass()
    {
        var plan = LayoutPlanner.Plan(1, A4, Opt(PresetKind.DuplexManual), SizeMm.A4);
        Assert.False(plan.NeedsSecondPass);
    }
    [Fact] public void Gutter_MirroredOnBacks()
    {
        var o = Opt(PresetKind.DuplexManual) with { GutterMm = 20 };
        var plan = LayoutPlanner.Plan(2, A4, o, SizeMm.A4);
        var front = plan.Passes[0].Sides[0].Placements[0].Cell;
        var back = plan.Passes[1].Sides[0].Placements[0].Cell;
        Assert.Equal(26, front.X, 3);        // 6 + 20 слева
        Assert.Equal(6, back.X, 3);          // оборот: подшивка справа
        Assert.Equal(210 - 26, back.Right, 3);
    }
    [Fact] public void Gutter_LeftOnNormal()
    {
        var o = Opt(PresetKind.Normal) with { GutterMm = 20 };
        var plan = LayoutPlanner.Plan(2, A4, o, SizeMm.A4);
        Assert.All(plan.Passes[0].Sides, s => Assert.Equal(26, s.Placements[0].Cell.X, 3));
    }
    [Fact] public void OddEven_Only()
    {
        var odd = LayoutPlanner.Plan(6, A4, Opt(PresetKind.OddOnly), SizeMm.A4);
        Assert.Equal(new[] { 1, 3, 5 }, odd.Passes[0].Sides.Select(s => s.Placements[0].Page));
        var even = LayoutPlanner.Plan(6, A4, Opt(PresetKind.EvenOnly), SizeMm.A4);
        Assert.Equal(new[] { 2, 4, 6 }, even.Passes[0].Sides.Select(s => s.Placements[0].Page));
    }
    [Fact] public void OddOnly_WithRange()
    {
        var plan = LayoutPlanner.Plan(10, A4, Opt(PresetKind.OddOnly, "4-8"), SizeMm.A4);
        Assert.Equal(new[] { 5, 7 }, plan.Passes[0].Sides.Select(s => s.Placements[0].Page));
    }
    [Fact] public void EvenOnly_NothingToPrint_Throws()
        => Assert.Throws<PageRangeException>(() => LayoutPlanner.Plan(10, A4, Opt(PresetKind.EvenOnly, "3"), SizeMm.A4));
    [Fact] public void Range_AppliesBeforeLayout()
    {
        var plan = LayoutPlanner.Plan(10, A4, Opt(PresetKind.Normal, "2-3,9"), SizeMm.A4);
        Assert.Equal(new[] { 2, 3, 9 }, plan.Passes[0].Sides.Select(s => s.Placements[0].Page));
    }
    [Fact] public void Booklet_8Pages()
    {
        var plan = LayoutPlanner.Plan(8, A4, Opt(PresetKind.Booklet), SizeMm.A4);
        Assert.Equal(2, plan.Passes.Count);
        Assert.True(plan.Sheet.IsLandscape);
        var f = plan.Passes[0].Sides; var b = plan.Passes[1].Sides;
        Assert.Equal(new[] { 8, 1 }, f[0].Placements.Select(p => p.Page));
        Assert.Equal(new[] { 6, 3 }, f[1].Placements.Select(p => p.Page));
        // обороты в обратном порядке: сначала лист 2 [4|5], потом лист 1 [2|7]
        Assert.Equal(new[] { 4, 5 }, b[0].Placements.Select(p => p.Page));
        Assert.Equal(new[] { 2, 7 }, b[1].Placements.Select(p => p.Page));
        // левая страница левее правой
        Assert.True(f[0].Placements[0].Target.Right <= f[0].Placements[1].Target.X);
    }
    [Fact] public void Booklet_5Pages_ThreeBlankSlots()
    {
        var plan = LayoutPlanner.Plan(5, A4, Opt(PresetKind.Booklet), SizeMm.A4);
        var all = plan.Passes.SelectMany(p => p.Sides).SelectMany(s => s.Placements).ToList();
        Assert.Equal(3, all.Count(p => p.IsBlank));
        Assert.Equal(5, all.Where(p => !p.IsBlank).Select(p => p.Page).Distinct().Count());
    }
    [Fact] public void Landscape_Page_ChoosesLandscapeSheet()
    {
        PageSizeProvider land = _ => new SizeMm(297, 210);
        var plan = LayoutPlanner.Plan(2, land, Opt(PresetKind.Normal), SizeMm.A4);
        Assert.True(plan.Sheet.IsLandscape);
    }
    [Fact] public void Placement_KeepsAspect_InsideCell()
    {
        PageSizeProvider img = _ => new SizeMm(100, 50);
        var plan = LayoutPlanner.Plan(1, img, Opt(PresetKind.Normal), SizeMm.A4);
        var p = plan.Passes[0].Sides[0].Placements[0];
        Assert.Equal(2.0, p.Target.W / p.Target.H, 3);
        Assert.True(p.Target.X >= p.Cell.X - 1e-9 && p.Target.Right <= p.Cell.Right + 1e-9);
    }
    [Fact] public void BlankPlaceholder_NoSlots_Empty()
        => Assert.Empty(LayoutPlanner.Plan(Array.Empty<PageSlot>(), A4, new PrintOptions(), SizeMm.A4).Passes);
    [Fact] public void PresetsKeepCopiesAndRange()
    {
        var o = Presets.Apply(PresetKind.Booklet, new PrintOptions { Copies = 3, PageRangeText = "1-4" });
        Assert.Equal(3, o.Copies); Assert.Equal("1-4", o.PageRangeText); Assert.True(o.Booklet);
        var back = Presets.Apply(PresetKind.Normal, o);
        Assert.False(back.Booklet); Assert.Equal(1, back.PagesPerSheet);
    }
    [Fact] public void FourUp_Grid2x2()
    {
        var o = Opt(PresetKind.Normal) with { PagesPerSheet = 4 };
        var plan = LayoutPlanner.Plan(4, A4, o, SizeMm.A4);
        Assert.Equal(4, plan.Passes[0].Sides[0].Placements.Count);
    }
}
