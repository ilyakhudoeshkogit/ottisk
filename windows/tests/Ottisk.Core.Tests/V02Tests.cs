using Ottisk.Core;

namespace Ottisk.Core.Tests;

public class GostPresetTests
{
    static readonly PageSizeProvider A4 = _ => new SizeMm(210, 297);
    static PrintOptions Gost(string range = "") => Presets.Apply(PresetKind.Gost, new PrintOptions { PageRangeText = range });

    [Fact] public void Margins_MatchMacVersion()
    {
        Assert.Equal(new PageMargins(20, 20, 30, 15), PageMargins.Gost7_32);
        Assert.Equal(PageMargins.Gost7_32, Gost().FixedMargins);
    }

    [Fact] public void WholePageInsideGostMargins_ProportionalScale()
    {
        var plan = LayoutPlanner.Plan(3, A4, Gost());
        Assert.Single(plan.Passes);
        Assert.Equal(3, plan.Passes[0].Sides.Count);
        foreach (var side in plan.Passes[0].Sides)
        {
            Assert.Equal(new SizeMm(210, 297), side.Size);
            var t = side.Placements[0].Target;
            Assert.InRange(t.X, 30 - 1e-6, 30 + 1e-6);        // прижато к полю под дырокол
            Assert.InRange(t.Y, 20 - 1e-6, 20 + 1e-6);
            Assert.True(t.Right <= 210 - 15 + 1e-6);
            Assert.True(t.Bottom <= 297 - 20 + 1e-6);
            Assert.Equal(210.0 / 297.0, t.W / t.H, 6);        // пропорции сохранены
            Assert.Equal(165, t.W, 6);                        // упирается в ширину поля
        }
    }

    [Fact] public void Guide_IsMarginArea_ForPreview()
    {
        var side = LayoutPlanner.Plan(1, A4, Gost()).Passes[0].Sides[0];
        Assert.Equal(new Rect(30, 20, 165, 257), side.Guide);
        var normal = LayoutPlanner.Plan(1, A4, new PrintOptions()).Passes[0].Sides[0];
        Assert.Null(normal.Guide);
    }

    [Fact] public void GutterCheckbox_IgnoredByGost()
    {
        var withGutter = Gost() with { GutterMm = 20 };
        var t = LayoutPlanner.Plan(1, A4, withGutter).Passes[0].Sides[0].Placements[0].Target;
        Assert.Equal(30, t.X, 6);
        Assert.True(Presets.HasOwnGutter(PresetKind.Gost));
        Assert.False(Presets.HasOwnGutter(PresetKind.Normal));
    }

    [Fact] public void SwitchingAway_ClearsFixedMargins()
    {
        var back = Presets.Apply(PresetKind.Normal, Gost());
        Assert.Null(back.FixedMargins);
        var t = LayoutPlanner.Plan(1, A4, back).Passes[0].Sides[0].Placements[0].Target;
        Assert.True(t.X < 10);
    }

    [Fact] public void KeepsCopiesAndRange()
    {
        var o = Presets.Apply(PresetKind.Gost, new PrintOptions { Copies = 2, PageRangeText = "2-3" });
        Assert.Equal(2, o.Copies);
        var plan = LayoutPlanner.Plan(5, A4, o);
        Assert.Equal(new[] { 2, 3, 2, 3 }, plan.Passes[0].Sides.Select(s => s.Placements[0].Page));
    }

    [Fact] public void OnA5_StillInsideMargins()
    {
        var o = Gost() with { Paper = PaperKind.A5 };
        var side = LayoutPlanner.Plan(1, A4, o).Passes[0].Sides[0];
        Assert.Equal(new SizeMm(148, 210), side.Size);
        var t = side.Placements[0].Target;
        Assert.Equal(30, t.X, 6);
        Assert.True(t.Right <= 148 - 15 + 1e-6 && t.Bottom <= 210 - 20 + 1e-6);
    }

    [Fact] public void LandscapeImage_LandscapeSheet_InsideMargins()
    {
        var side = LayoutPlanner.Plan(1, _ => new SizeMm(300, 200), Gost()).Passes[0].Sides[0];
        Assert.True(side.Size.IsLandscape);
        var t = side.Placements[0].Target;
        Assert.True(t.X >= 30 - 1e-6 && t.Right <= 297 - 15 + 1e-6 && t.Bottom <= 210 - 20 + 1e-6);
    }

    [Fact] public void ShownInPresetList_WithRussianTitle()
    {
        Assert.Contains(PresetKind.Gost, Presets.Shown);
        Assert.Contains("ГОСТ", Presets.Title(PresetKind.Gost));
        Assert.Contains("30", Presets.Hint(PresetKind.Gost));
    }

    [Fact] public void Area_MirrorsGostOnBacks()
    {
        var o = Gost();
        var front = LayoutPlanner.Area(o, SizeMm.A4, isBack: false, mirror: true);
        var back = LayoutPlanner.Area(o, SizeMm.A4, isBack: true, mirror: true);
        Assert.Equal(30, front.X, 6);
        Assert.Equal(15, back.X, 6);
        Assert.Equal(front.W, back.W, 6);
    }
}

public class PaperTests
{
    static readonly PageSizeProvider A4 = _ => new SizeMm(210, 297);

    [Fact] public void Sizes()
    {
        Assert.Equal(new SizeMm(210, 297), Papers.Size(PaperKind.A4));
        Assert.Equal(new SizeMm(148, 210), Papers.Size(PaperKind.A5));
        Assert.Equal(new SizeMm(215.9, 279.4), Papers.Size(PaperKind.Letter));
    }

    [Fact] public void DefaultIsA4() => Assert.Equal(PaperKind.A4, new PrintOptions().Paper);

    [Theory]
    [InlineData("ISOA4", PaperKind.A4)] [InlineData("iso_a4_210x297mm", PaperKind.A4)] [InlineData("A4", PaperKind.A4)]
    [InlineData("ISOA5", PaperKind.A5)] [InlineData("iso_a5_148x210mm", PaperKind.A5)]
    [InlineData("NorthAmericaLetter", PaperKind.Letter)] [InlineData("na_letter_8.5x11in", PaperKind.Letter)]
    public void FromName_Known(string name, PaperKind expected) => Assert.Equal(expected, Papers.FromName(name));

    [Theory]
    [InlineData(null)] [InlineData("")] [InlineData("ISOA4Rotated")] [InlineData("NorthAmericaLegal")] [InlineData("ISOA3")]
    [InlineData("NorthAmericaLetterRotated")] [InlineData("ISOA4Extra")]
    public void FromName_Unknown(string? name) => Assert.Null(Papers.FromName(name));

    [Fact] public void FromSize_AnyOrientation_WithTolerance()
    {
        Assert.Equal(PaperKind.A4, Papers.FromSize(297, 210));
        Assert.Equal(PaperKind.A5, Papers.FromSize(148.5, 210.2));
        Assert.Equal(PaperKind.Letter, Papers.FromSize(216, 279));
        Assert.Null(Papers.FromSize(216, 356)); // Legal
    }

    [Fact] public void Available_FromDriver()
    {
        var media = new (string?, double, double)[] { ("ISOA4", 210, 297), ("NorthAmericaLegal", 216, 356), (null, 148, 210) };
        Assert.Equal(new[] { PaperKind.A4, PaperKind.A5 }, Papers.Available(media));
    }

    [Fact] public void Available_UnknownDriver_ShowsAll()
    {
        Assert.Equal(Papers.All, Papers.Available(null));
        Assert.Equal(Papers.All, Papers.Available(Array.Empty<(string?, double, double)>()));
    }

    [Fact] public void Available_AlwaysHasA4()
        => Assert.Equal(new[] { PaperKind.A4, PaperKind.Letter }, Papers.Available(new (string?, double, double)[] { ("Letter", 0, 0) }));

    [Fact] public void Choose_FallsBackToA4()
    {
        var onlyA4 = new[] { PaperKind.A4 };
        Assert.Equal(PaperKind.A4, Papers.Choose(PaperKind.A5, onlyA4));
        Assert.Equal(PaperKind.A5, Papers.Choose(PaperKind.A5, Papers.All));
        Assert.Equal(PaperKind.A4, Papers.Choose(null, Papers.All));
    }

    [Fact] public void Plan_UsesPaperFromOptions()
    {
        var side = LayoutPlanner.Plan(1, A4, new PrintOptions { Paper = PaperKind.A5 }).Passes[0].Sides[0];
        Assert.Equal(new SizeMm(148, 210), side.Size);
        Assert.True(side.Placements[0].Target.Right <= 148 - 6 + 1e-6);
    }

    [Fact] public void Letter_Economy_Landscape()
    {
        var o = Presets.Apply(PresetKind.Economy, new PrintOptions { Paper = PaperKind.Letter });
        var side = LayoutPlanner.Plan(2, A4, o).Passes[0].Sides[0];
        Assert.Equal(new SizeMm(279.4, 215.9), side.Size);
    }

    [Fact] public void Booklet_OnA5()
    {
        var o = Presets.Apply(PresetKind.Booklet, new PrintOptions { Paper = PaperKind.A5 });
        var plan = LayoutPlanner.Plan(4, A4, o);
        Assert.Equal(new SizeMm(210, 148), plan.Sheet);
    }

    [Fact] public void Titles_Russian() => Assert.All(Papers.All, k => Assert.False(string.IsNullOrWhiteSpace(Papers.Title(k))));
}

public class CalibrationTests
{
    static readonly DuplexHandling Default = new(FlipBacks: false, FaceUp: false);

    [Fact] public void Correct_KeepsSettings() => Assert.Equal(Default, DuplexCalibration.Apply(Default, CalibrationResult.Correct));

    [Fact] public void UpsideDown_TogglesFlip()
    {
        var h = DuplexCalibration.Apply(Default, CalibrationResult.BackUpsideDown);
        Assert.True(h.FlipBacks); Assert.False(h.FaceUp);
        // повторный ответ «вверх ногами» после исправления — значит, было правильно, возвращаем
        Assert.False(DuplexCalibration.Apply(h, CalibrationResult.BackUpsideDown).FlipBacks);
    }

    [Fact] public void SameSide_TogglesFaceUp_KeepsFlip()
    {
        var h = DuplexCalibration.Apply(new DuplexHandling(true, false), CalibrationResult.BackOnSameSide);
        Assert.True(h.FaceUp); Assert.True(h.FlipBacks); Assert.False(h.ReverseBacks);
    }

    [Fact] public void Retry_OnlyWhenNotCorrect()
    {
        Assert.False(DuplexCalibration.SuggestRetry(CalibrationResult.Correct));
        Assert.True(DuplexCalibration.SuggestRetry(CalibrationResult.BackUpsideDown));
        Assert.True(DuplexCalibration.SuggestRetry(CalibrationResult.BackOnSameSide));
        Assert.All(Enum.GetValues<CalibrationResult>(), r => Assert.False(string.IsNullOrWhiteSpace(DuplexCalibration.Message(r))));
    }

    [Fact] public void Plan_OneSheet_TwoPasses_1Then2()
    {
        var plan = DuplexCalibration.Plan(PaperKind.A4, Default);
        Assert.Equal(2, plan.Passes.Count);
        Assert.Single(plan.Passes[0].Sides);
        Assert.Single(plan.Passes[1].Sides);
        Assert.Equal(1, plan.Passes[0].Sides[0].Placements[0].Page);
        Assert.Equal(2, plan.Passes[1].Sides[0].Placements[0].Page);
        Assert.False(plan.Passes[1].Sides[0].Rotate180);
        Assert.True(plan.Passes[1].Sides[0].IsBack);
        Assert.Equal(SizeMm.A4, plan.Sheet);
    }

    [Fact] public void Plan_RespectsFlip()
    {
        var plan = DuplexCalibration.Plan(PaperKind.A4, new DuplexHandling(true, false));
        Assert.False(plan.Passes[0].Sides[0].Rotate180);
        Assert.True(plan.Passes[1].Sides[0].Rotate180);
    }

    [Fact] public void Plan_UsesChosenPaper()
        => Assert.Equal(new SizeMm(148, 210), DuplexCalibration.Plan(PaperKind.A5, Default).Passes[0].Sides[0].Size);
}

public class UserSettingsTests
{
    [Fact] public void Defaults()
    {
        var s = new UserSettings();
        Assert.False(s.FlipBacks); Assert.True(s.ReverseBacks);
        Assert.Equal(PaperKind.A4, s.Paper); Assert.False(s.Calibrated);
    }

    [Fact] public void RoundTrip_AfterCalibration()
    {
        var s = new UserSettings { Printer = "Canon" };
        s.Duplex = DuplexCalibration.Apply(s.Duplex, CalibrationResult.BackUpsideDown);
        s.Duplex = DuplexCalibration.Apply(s.Duplex, CalibrationResult.BackOnSameSide);
        s.Paper = PaperKind.A5; s.Calibrated = true;
        var back = UserSettings.FromJson(s.ToJson());
        Assert.Equal("Canon", back.Printer);
        Assert.True(back.FlipBacks); Assert.False(back.ReverseBacks);
        Assert.Equal(new DuplexHandling(true, true), back.Duplex);
        Assert.Equal(PaperKind.A5, back.Paper); Assert.True(back.Calibrated);
        Assert.Contains("\"A5\"", s.ToJson());   // читаемо в файле
    }

    [Fact] public void OldFile_From010_StillLoads()
    {
        var s = UserSettings.FromJson("{\n  \"Printer\": \"HP\",\n  \"FlipBacks\": true,\n  \"ReverseBacks\": false\n}");
        Assert.Equal("HP", s.Printer); Assert.True(s.FlipBacks); Assert.False(s.ReverseBacks);
        Assert.Equal(PaperKind.A4, s.Paper);
    }

    [Theory] [InlineData(null)] [InlineData("")] [InlineData("{oops")] [InlineData("[]")] [InlineData("{\"Paper\": 42}")]
    public void Broken_GivesDefaults(string? json)
    {
        var s = UserSettings.FromJson(json);
        Assert.Equal(PaperKind.A4, s.Paper);
    }
}
