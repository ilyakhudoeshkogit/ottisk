namespace Ottisk.Core;

public enum PaperKind { A4, A5, Letter }

/// <summary>Размеры бумаги и выбор из того, что умеет принтер.</summary>
public static class Papers
{
    public static readonly PaperKind[] All = { PaperKind.A4, PaperKind.A5, PaperKind.Letter };
    const double ToleranceMm = 2.5;

    public static SizeMm Size(PaperKind k) => k switch
    {
        PaperKind.A5 => new SizeMm(148, 210),
        PaperKind.Letter => new SizeMm(215.9, 279.4),
        _ => SizeMm.A4
    };

    public static string Title(PaperKind k) => k switch
    {
        PaperKind.A5 => "A5 — половинка A4",
        PaperKind.Letter => "Letter — американский",
        _ => "A4 — обычный лист"
    };

    /// <summary>Узнаёт формат по имени носителя драйвера («ISOA4», «iso_a5_148x210mm», «NorthAmericaLetter»…).</summary>
    public static PaperKind? FromName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return null;
        var n = name.ToLowerInvariant().Replace("_", "").Replace("-", "").Replace(" ", "");
        if (n.Contains("letter") && !n.Contains("small") && !n.Contains("extra") && !n.Contains("rotated")) return PaperKind.Letter;
        if (n.Contains("rotated") || n.Contains("extra")) return null;
        if (n is "a4" or "isoa4" || n.StartsWith("isoa4")) return PaperKind.A4;
        if (n is "a5" or "isoa5" || n.StartsWith("isoa5")) return PaperKind.A5;
        return null;
    }

    /// <summary>Узнаёт формат по размерам (в любой ориентации).</summary>
    public static PaperKind? FromSize(double wMm, double hMm)
    {
        var s = new SizeMm(wMm, hMm).Portrait;
        foreach (var k in All)
        {
            var p = Size(k);
            if (Math.Abs(p.W - s.W) <= ToleranceMm && Math.Abs(p.H - s.H) <= ToleranceMm) return k;
        }
        return null;
    }

    /// <summary>
    /// Какие из наших форматов показывать. <paramref name="media"/> — что сообщил драйвер (имя и размер в мм);
    /// если он ничего не сообщил — показываем все три, A4 есть всегда.
    /// </summary>
    public static IReadOnlyList<PaperKind> Available(IEnumerable<(string? Name, double W, double H)>? media)
    {
        var list = media?.ToList();
        if (list == null || list.Count == 0) return All;
        var found = new HashSet<PaperKind> { PaperKind.A4 };
        foreach (var m in list)
        {
            var k = FromName(m.Name) ?? (m.W > 0 && m.H > 0 ? FromSize(m.W, m.H) : null);
            if (k != null) found.Add(k.Value);
        }
        return All.Where(found.Contains).ToList();
    }

    /// <summary>Сохранённый выбор, если принтер его умеет, иначе A4.</summary>
    public static PaperKind Choose(PaperKind? preferred, IReadOnlyList<PaperKind> available)
        => preferred is { } p && available.Contains(p) ? p : PaperKind.A4;
}
