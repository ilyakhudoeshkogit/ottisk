using Ottisk.Core;

namespace Ottisk.Core.Tests;

public class PageNumberingTests
{
    static readonly PageSizeProvider A4 = _ => new SizeMm(210, 297);

    [Fact] public void Off_NoLabels()
    {
        Assert.Null(PageNumbering.Off.Label(1));
        var side = LayoutPlanner.Plan(3, A4, new PrintOptions()).Passes[0].Sides[1];
        Assert.Empty(side.Labels);
    }

    [Fact] public void Label_IsDocumentPage_FromStart()
    {
        var n = new PageNumbering(true, 1, 0);
        Assert.Equal("1", n.Label(1));
        Assert.Equal("7", n.Label(7));
        var from5 = new PageNumbering(true, 5, 0);
        Assert.Equal("5", from5.Label(1));
        Assert.Equal("9", from5.Label(5));
    }

    [Fact] public void Title_CountedButNotNumbered_Gost632()
    {
        var g = PageNumbering.Gost;
        Assert.True(g.Enabled);
        Assert.Null(g.Label(1));          // титул считается, но номер не ставится
        Assert.Equal("2", g.Label(2));    // следующая страница — «2», а не «1»
        Assert.Equal("10", g.Label(10));
    }

    [Fact] public void SkipFirst_WithCustomStart()
    {
        var n = new PageNumbering(true, 3, 1);
        Assert.Null(n.Label(1));
        Assert.Equal("4", n.Label(2));
    }

    [Fact] public void Label_BadInput_Safe()
    {
        var n = new PageNumbering(true, -10, -3);
        Assert.Null(n.Label(0));
        Assert.Equal("0", n.Label(1));   // старт зажимается в 0…999
        Assert.Equal("1000", new PageNumbering(true, 5000).Label(2));
    }

    [Fact] public void GostPreset_TurnsNumberingOn_TitleWithoutNumber()
    {
        var o = Presets.Apply(PresetKind.Gost, new PrintOptions());
        Assert.Equal(PageNumbering.Gost, o.Numbering);
    }

    [Fact] public void LeavingGost_TurnsNumberingOff_OtherPresetsKeepIt()
    {
        var gost = Presets.Apply(PresetKind.Gost, new PrintOptions());
        Assert.False(Presets.Apply(PresetKind.Normal, gost).Numbering.Enabled);
        var mine = new PrintOptions { Numbering = new PageNumbering(true, 3, 0) };
        Assert.Equal(mine.Numbering, Presets.Apply(PresetKind.Economy, mine).Numbering);
        Assert.Equal(mine.Numbering, Presets.Apply(PresetKind.DuplexManual, mine).Numbering);
    }

    [Fact] public void Gost_NumberBottomCenterOfMargins_NotOnTitle()
    {
        var o = Presets.Apply(PresetKind.Gost, new PrintOptions());
        var sides = LayoutPlanner.Plan(3, A4, o).Passes[0].Sides;
        Assert.Empty(sides[0].Labels);
        var l = Assert.Single(sides[1].Labels);
        Assert.Equal("2", l.Text);
        Assert.Equal(30 + 165 / 2.0, l.X, 6);       // середина между полями 30 и 15 мм
        Assert.Equal(297 - 10, l.BaselineY, 6);     // посередине нижнего поля 20 мм
        Assert.Equal(LabelAlign.Center, l.Align);
        Assert.Equal(12, l.FontPt);
        Assert.Equal("3", sides[2].Labels[0].Text);
    }

    [Fact] public void NumberStaysWithPage_WhenReprintingRange()
    {
        var o = Presets.Apply(PresetKind.Gost, new PrintOptions { PageRangeText = "5" });
        var side = Assert.Single(LayoutPlanner.Plan(9, A4, o).Passes[0].Sides);
        Assert.Equal("5", side.Labels[0].Text);
    }

    [Fact] public void NormalMargins_NumberAtLeast5mmFromEdge()
    {
        var o = new PrintOptions { Numbering = new PageNumbering(true) };
        var l = LayoutPlanner.Plan(1, A4, o).Passes[0].Sides[0].Labels[0];
        Assert.Equal(297 - 5, l.BaselineY, 6);
        Assert.Equal(105, l.X, 6);
    }

    [Fact] public void TwoPerSheet_SmallNumberUnderEachPage_CellShrinks()
    {
        var o = Presets.Apply(PresetKind.Economy, new PrintOptions { Numbering = new PageNumbering(true) });
        var plain = LayoutPlanner.Plan(2, A4, Presets.Apply(PresetKind.Economy, new PrintOptions())).Passes[0].Sides[0];
        var side = LayoutPlanner.Plan(2, A4, o).Passes[0].Sides[0];
        Assert.Equal(2, side.Labels.Count);
        for (var k = 0; k < 2; k++)
        {
            var p = side.Placements[k];
            Assert.Equal(plain.Placements[k].Cell.H - LayoutPlanner.SmallNumberGapMm, p.Cell.H, 6);
            Assert.Equal(p.Cell.X + p.Cell.W / 2, side.Labels[k].X, 6);
            Assert.True(side.Labels[k].BaselineY > p.Target.Bottom);
            Assert.True(side.Labels[k].BaselineY < p.Cell.Bottom + LayoutPlanner.SmallNumberGapMm);
            Assert.Equal(LayoutPlanner.SmallNumberFontPt, side.Labels[k].FontPt);
        }
        Assert.Equal(new[] { "1", "2" }, side.Labels.Select(l => l.Text));
    }

    [Fact] public void ManualDuplex_BackNumberFollowsMirroredMargins()
    {
        var o = Presets.Apply(PresetKind.Gost, new PrintOptions()) with { ManualDuplex = true };
        var plan = LayoutPlanner.Plan(2, A4, o);
        var back = plan.Passes[1].Sides[0];
        Assert.Equal("2", back.Labels[0].Text);
        Assert.Equal(15 + 165 / 2.0, back.Labels[0].X, 6);    // на обороте поле 30 мм справа
    }

    [Fact] public void Booklet_NumbersOnBothHalves_BlankHasNone()
    {
        var o = Presets.Apply(PresetKind.Booklet, new PrintOptions { Numbering = new PageNumbering(true) });
        var plan = LayoutPlanner.Plan(3, A4, o);
        var all = plan.Passes.SelectMany(p => p.Sides).SelectMany(s => s.Labels).Select(l => l.Text).OrderBy(t => t).ToList();
        Assert.Equal(new[] { "1", "2", "3" }, all);   // 4-я страница брошюры пустая — без номера
    }

    [Fact] public void FlippedBack_KeepsLabels()
    {
        var o = new PrintOptions { Numbering = new PageNumbering(true), ManualDuplex = true, FlipBacks = true };
        var back = LayoutPlanner.Plan(2, A4, o).Passes[1].Sides[0];
        Assert.True(back.Rotate180);
        Assert.Equal("2", back.Labels[0].Text);
    }
}

public class WatermarkTests
{
    static readonly PageSizeProvider A4 = _ => new SizeMm(210, 297);

    [Fact] public void Empty_NotActive_NoMarks()
    {
        Assert.False(new Watermark("   ").IsActive);
        Assert.Null(new Watermark("").Place(new Rect(0, 0, 100, 100)));
        Assert.Empty(LayoutPlanner.Plan(1, A4, new PrintOptions()).Passes[0].Sides[0].Watermarks);
    }

    [Fact] public void Place_CenterOfTarget_TrimmedText_Diagonal()
    {
        var m = new Watermark("  ЧЕРНОВИК ").Place(new Rect(10, 20, 100, 200))!;
        Assert.Equal("ЧЕРНОВИК", m.Text);
        Assert.Equal(60, m.CenterX, 6);
        Assert.Equal(120, m.CenterY, 6);
        Assert.Equal(45, m.AngleDeg);
        Assert.Equal(new Rect(10, 20, 100, 200), m.Clip);
    }

    [Fact] public void Font_FitsAlongDiagonal_LikeMac()
    {
        var w = new Watermark("КОПИЯ");
        var pt = w.FontPt(210, 297);
        // По 45° до края: min(210/cos, 297/sin) = 296,98 мм; 80 % / (5 × 0,62) = 76,6 мм ≈ 217 пт → потолок 160.
        Assert.Equal(160, pt, 6);
        var longText = new Watermark("НЕ ДЛЯ ПЕЧАТИ НЕ ДЛЯ ПЕЧАТИ");
        var lpt = longText.FontPt(210, 297);
        var widthMm = longText.Trimmed.Length * 0.62 * lpt * 25.4 / 72;
        Assert.True(widthMm <= 210 / Math.Cos(Math.PI / 4) + 1e-6);   // не вылезает за край
        Assert.True(lpt < 160 && lpt > 12);
    }

    [Fact] public void Font_ClampedForTinyArea()
    {
        Assert.Equal(Watermark.MinFontPt, new Watermark("ЧЕРНОВИК").FontPt(5, 5), 6);
    }

    [Fact] public void Opacity_Clamped_LightByDefault()
    {
        Assert.InRange(new Watermark("A").ClampedOpacity, 0.05, 0.6);
        Assert.Equal(Watermark.MaxOpacity, new Watermark("A", 5).ClampedOpacity);
        Assert.Equal(Watermark.MinOpacity, new Watermark("A", -1).ClampedOpacity);
    }

    [Fact] public void Plan_OneMarkPerPage_InsideTarget()
    {
        var o = Presets.Apply(PresetKind.Economy, new PrintOptions { Watermark = new Watermark("КОПИЯ") });
        var side = LayoutPlanner.Plan(3, A4, o).Passes[0].Sides[1];   // страница 3 + пустое место
        var m = Assert.Single(side.Watermarks);
        var t = side.Placements[0].Target;
        Assert.Equal(t, m.Clip);
        Assert.Equal(t.X + t.W / 2, m.CenterX, 6);
    }

    [Fact] public void Plan_ManualDuplex_BacksHaveWatermarkToo()
    {
        var o = new PrintOptions { ManualDuplex = true, Watermark = new Watermark("ЧЕРНОВИК") };
        var plan = LayoutPlanner.Plan(4, A4, o);
        Assert.All(plan.Passes.SelectMany(p => p.Sides), s => Assert.Single(s.Watermarks));
    }
}

public class TrimWhiteTests
{
    static readonly PageSizeProvider A4 = _ => new SizeMm(210, 297);

    static byte[] White(int w, int h) => Enumerable.Repeat((byte)255, w * h).ToArray();
    static void Fill(byte[] g, int w, int x0, int y0, int x1, int y1, byte v = 0)
    {
        for (var y = y0; y <= y1; y++) for (var x = x0; x <= x1; x++) g[y * w + x] = v;
    }

    [Fact] public void Detect_EmptyPage_Null()
    {
        Assert.Null(ContentBounds.Detect(White(20, 30), 20, 30));
        Assert.Null(ContentBounds.Detect(new byte[3], 20, 30));   // мало данных
    }

    [Fact] public void Detect_Block_TopLeftOrigin()
    {
        var g = White(40, 50);
        Fill(g, 40, 5, 10, 24, 39);
        Assert.Equal(new Rect(5, 10, 20, 30), ContentBounds.Detect(g, 40, 50));
    }

    [Fact] public void Detect_IgnoresSingleDustSpeck()
    {
        var g = White(40, 50);
        Fill(g, 40, 10, 10, 19, 19);
        g[45 * 40 + 35] = 0;   // одна пылинка внизу справа
        Assert.Equal(new Rect(10, 10, 10, 10), ContentBounds.Detect(g, 40, 50));
    }

    [Fact] public void Detect_LightGrayBelowThreshold_IsPaper()
    {
        var g = White(30, 30);
        Fill(g, 30, 0, 0, 29, 29, 240);    // сероватая бумага скана
        Fill(g, 30, 8, 8, 12, 12, 100);
        Assert.Equal(new Rect(8, 8, 5, 5), ContentBounds.Detect(g, 30, 30));
        Assert.Equal(new Rect(0, 0, 30, 30), ContentBounds.Detect(g, 30, 30, threshold: 250));
    }

    [Fact] public void ToPage_PixelsToMm_WithPaddingAndClamp()
    {
        // 2 пикселя на мм, страница 100×100 мм.
        var r = ContentBounds.ToPage(new Rect(20, 40, 100, 60), 2, new SizeMm(100, 100));
        Assert.Equal(new Rect(9, 19, 52, 32), r);
        var edge = ContentBounds.ToPage(new Rect(0, 0, 200, 200), 2, new SizeMm(100, 100));
        Assert.Equal(new Rect(0, 0, 100, 100), edge);
    }

    [Fact] public void Unified_SameSizePagesShareBox_OtherSizesSeparate()
    {
        var sizes = new Dictionary<int, SizeMm> { [1] = new(210, 297), [2] = new(210, 297), [3] = new(297, 210), [4] = new(210, 297) };
        var boxes = new Dictionary<int, Rect> { [1] = new(20, 20, 100, 100), [2] = new(30, 10, 150, 50), [3] = new(5, 5, 10, 10) };
        var u = ContentBounds.Unified(boxes, sizes);
        Assert.Equal(new Rect(20, 10, 160, 110), u[1]);
        Assert.Equal(u[1], u[2]);
        Assert.Equal(u[1], u[4]);              // пустая страница того же размера — та же рамка
        Assert.Equal(new Rect(5, 5, 10, 10), u[3]);
    }

    [Fact] public void Crop_TinyOrMissingBox_WholePage()
    {
        var a4 = new SizeMm(210, 297);
        Assert.Equal(new Rect(0, 0, 210, 297), ContentBounds.Crop(a4, null));
        Assert.Equal(new Rect(0, 0, 210, 297), ContentBounds.Crop(a4, new Rect(10, 10, 0.2, 50)));
        Assert.Equal(new Rect(0, 10, 210, 287), ContentBounds.Crop(a4, new Rect(-5, 10, 300, 400)));
    }

    [Fact] public void Plan_TrimOff_IgnoresBoxes()
    {
        var plan = LayoutPlanner.Plan(1, A4, new PrintOptions(), _ => new Rect(30, 30, 150, 200));
        Assert.Null(plan.Passes[0].Sides[0].Placements[0].Source);
    }

    [Fact] public void Plan_TrimOn_ContentFillsCell()
    {
        var o = new PrintOptions { TrimWhite = true };
        var p = LayoutPlanner.Plan(1, A4, o, _ => new Rect(30, 30, 150, 200)).Passes[0].Sides[0].Placements[0];
        Assert.Equal(new Rect(30, 30, 150, 200), p.Source);
        Assert.Equal(150.0 / 200.0, p.Target.W / p.Target.H, 6);
        Assert.Equal(210 - 12, p.Target.W, 6);      // упирается в ширину области (поля 6 мм)
    }

    [Fact] public void Plan_GostTrim_TopLeft_NoEnlarge()
    {
        var o = Presets.Apply(PresetKind.Gost, new PrintOptions()) with { TrimWhite = true };
        // Мелкий текст с огромными полями: не растягиваем — кегль как в файле.
        var small = LayoutPlanner.Plan(1, A4, o, _ => new Rect(50, 50, 100, 120)).Passes[0].Sides[0].Placements[0];
        Assert.Equal(new Rect(30, 20, 100, 120), small.Target);
        // Текст шире поля ГОСТ — уменьшаем ровно до 165 мм.
        var wide = LayoutPlanner.Plan(1, A4, o, _ => new Rect(10, 10, 190, 250)).Passes[0].Sides[0].Placements[0];
        Assert.Equal(165, wide.Target.W, 6);
        Assert.Equal(30, wide.Target.X, 6);
        Assert.Equal(20, wide.Target.Y, 6);
    }

    [Fact] public void Plan_GostTrim_BetterFitThanWholePage()
    {
        var gost = Presets.Apply(PresetKind.Gost, new PrintOptions());
        PageSizeProvider sz = A4; ContentBoxProvider box = _ => new Rect(20, 15, 175, 260);   // поля Word ~2 см
        var whole = LayoutPlanner.Plan(1, sz, gost, box).Passes[0].Sides[0].Placements[0];
        var trimmed = LayoutPlanner.Plan(1, sz, gost with { TrimWhite = true }, box).Passes[0].Sides[0].Placements[0];
        var wholeScale = whole.Target.W / 210;
        var trimScale = trimmed.Target.W / 175;
        Assert.True(trimScale > wholeScale);   // текст крупнее, а белые поля исходника не съедают место
    }

    [Fact] public void Plan_TrimOn_NullBox_WholePage()
    {
        var o = new PrintOptions { TrimWhite = true };
        var p = LayoutPlanner.Plan(1, A4, o, _ => null).Passes[0].Sides[0].Placements[0];
        Assert.Null(p.Source);
    }
}

public class SettingsV03Tests
{
    [Fact] public void OldV02File_Reads_WithNewDefaults()
    {
        const string v02 = """
        {
          "Printer": "Canon MF3010",
          "FlipBacks": true,
          "ReverseBacks": false,
          "Paper": "A5",
          "Calibrated": true
        }
        """;
        var s = UserSettings.FromJson(v02);
        Assert.Equal("Canon MF3010", s.Printer);
        Assert.Equal(PaperKind.A5, s.Paper);
        Assert.True(s.Calibrated);
        Assert.Equal(1, s.NumberStart);
        Assert.True(s.NumberSkipTitle);
        Assert.Equal("ЧЕРНОВИК", s.WatermarkText);
    }

    [Fact] public void NewFields_RoundTrip()
    {
        var s = new UserSettings { NumberStart = 3, NumberSkipTitle = false, WatermarkText = "КОПИЯ" };
        var back = UserSettings.FromJson(s.ToJson());
        Assert.Equal(3, back.NumberStart);
        Assert.False(back.NumberSkipTitle);
        Assert.Equal("КОПИЯ", back.WatermarkText);
        Assert.Equal(new PageNumbering(true, 3, 0), back.Numbering(true));
        Assert.False(back.Numbering(false).Enabled);
    }

    [Fact] public void BadValues_Sanitized()
    {
        var s = UserSettings.FromJson("""{ "NumberStart": -7, "WatermarkText": "   " }""");
        Assert.Equal(0, s.NumberStart);
        Assert.Equal("ЧЕРНОВИК", s.WatermarkText);
        var big = UserSettings.FromJson("{ \"NumberStart\": 100000, \"WatermarkText\": \"" + new string('Я', 100) + "\" }");
        Assert.Equal(PageNumbering.MaxStart, big.NumberStart);
        Assert.Equal(40, big.WatermarkText.Length);
    }
}
