namespace Ottisk.Core;

/// <summary>Ответ на вопрос «Как вышло?» после пробного листа.</summary>
public enum CalibrationResult { Correct, BackUpsideDown, BackOnSameSide }

/// <summary>Как обращаться с оборотами: повернуть их на 180° и выходят ли листы лицом вверх.</summary>
public sealed record DuplexHandling(bool FlipBacks, bool FaceUp)
{
    public bool ReverseBacks => !FaceUp;
}

/// <summary>
/// Пробный лист для ручной двусторонней печати: лицо — стрелка «верх» и «1», оборот — стрелка и «2».
/// По ответу человека меняет галочки «оборот вверх ногами» / «лицом вверх».
/// </summary>
public static class DuplexCalibration
{
    public const int FrontPage = 1;
    public const int BackPage = 2;

    public static DuplexHandling Apply(DuplexHandling current, CalibrationResult result) => result switch
    {
        CalibrationResult.BackUpsideDown => current with { FlipBacks = !current.FlipBacks },
        // «2» на той же стороне, что и «1»: стопку надо класть другой стороной — значит, листы выходят иначе,
        // чем мы думали (лицом вверх/вниз). Поворот оборота при этом не трогаем.
        CalibrationResult.BackOnSameSide => current with { FaceUp = !current.FaceUp },
        _ => current
    };

    /// <summary>После исправления стоит напечатать пробный лист ещё раз.</summary>
    public static bool SuggestRetry(CalibrationResult r) => r != CalibrationResult.Correct;

    public static string Message(CalibrationResult r) => r switch
    {
        CalibrationResult.BackUpsideDown => "Запомнил: оборот нужно поворачивать. Напечатайте пробный лист ещё раз, чтобы проверить.",
        CalibrationResult.BackOnSameSide => "Запомнил: бумагу нужно класть другой стороной — подсказка в окне оборота изменится. Напечатайте пробный лист ещё раз, чтобы проверить.",
        _ => "Отлично! Настройки сохранены — двусторонняя печать будет выходить так же ровно."
    };

    /// <summary>План пробного листа: 1 лист, два прохода (лицо «1», оборот «2»), с текущими галочками.</summary>
    public static JobPlan Plan(PaperKind paper, DuplexHandling h)
    {
        var sheet = Papers.Size(paper);
        var o = new PrintOptions
        {
            ManualDuplex = true,
            Paper = paper,
            FlipBacks = h.FlipBacks,
            ReverseBacks = h.ReverseBacks,
            Preset = PresetKind.DuplexManual,
        };
        return LayoutPlanner.Plan(2, _ => sheet, o, sheet);
    }
}
