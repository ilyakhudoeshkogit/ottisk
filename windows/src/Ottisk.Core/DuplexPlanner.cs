namespace Ottisk.Core;

/// <summary>План ручной двусторонней печати по спискам «слотов» (номера сторон или страниц).</summary>
public sealed record DuplexPlan(IReadOnlyList<PageSlot> Fronts, IReadOnlyList<PageSlot> Backs, int SheetCount)
{
    public bool NeedsSecondPass => Backs.Any(s => !s.IsBlank);
}

/// <summary>
/// Для принтера без дуплекса: 1) печатаем лица (1, 3, 5…), 2) человек перекладывает стопку,
/// 3) печатаем обороты (по умолчанию с последнего листа к первому — принтеры выкладывают лицом вниз).
/// Если сторон нечётное число, добавляется пустой оборот, чтобы последний лист не сместился.
/// </summary>
public static class DuplexPlanner
{
    public static DuplexPlan Plan(IReadOnlyList<int> pages, bool reverseBacks = true, int copies = 1)
    {
        // Копии идут одной стопкой: обороты разворачиваем целиком, а не по копиям,
        // иначе последняя копия (она сверху стопки) попала бы в печать не первой.
        var single = PlanSingle(pages, reverseBacks: false);
        var count = Math.Max(copies, 1);
        var fronts = Repeat(single.Fronts, count);
        var backs = single.NeedsSecondPass ? Repeat(single.Backs, count) : new List<PageSlot>();
        if (reverseBacks) backs.Reverse();
        return new DuplexPlan(fronts, backs, single.SheetCount * count);
    }

    private static DuplexPlan PlanSingle(IReadOnlyList<int> pages, bool reverseBacks)
    {
        if (pages.Count == 0) return new DuplexPlan(Array.Empty<PageSlot>(), Array.Empty<PageSlot>(), 0);
        if (pages.Count == 1) return new DuplexPlan(new[] { PageSlot.Of(pages[0]) }, Array.Empty<PageSlot>(), 1);
        var list = pages.Select(PageSlot.Of).ToList();
        if (list.Count % 2 == 1) list.Add(PageSlot.Blank);
        var fronts = new List<PageSlot>();
        var backs = new List<PageSlot>();
        for (var i = 0; i < list.Count; i++) (i % 2 == 0 ? fronts : backs).Add(list[i]);
        if (reverseBacks) backs.Reverse();
        return new DuplexPlan(fronts, backs, fronts.Count);
    }

    /// <summary>Брошюра: стороны идут «лицо, оборот, лицо, оборот…» (1…2K).</summary>
    public static DuplexPlan BookletPasses(int sideCount, bool reverseBacks = true, int copies = 1)
    {
        var sheets = sideCount / 2;
        if (sheets <= 0) return new DuplexPlan(Array.Empty<PageSlot>(), Array.Empty<PageSlot>(), 0);
        var fronts = Enumerable.Range(0, sheets).Select(i => PageSlot.Of(2 * i + 1)).ToList();
        var backs = Enumerable.Range(0, sheets).Select(i => PageSlot.Of(2 * i + 2)).ToList();
        var n = Math.Max(copies, 1);
        var allBacks = Repeat(backs, n);
        if (reverseBacks) allBacks.Reverse();
        return new DuplexPlan(Repeat(fronts, n), allBacks, sheets * n);
    }

    private static List<PageSlot> Repeat(IReadOnlyList<PageSlot> l, int n)
    {
        var r = new List<PageSlot>(l.Count * n);
        for (var i = 0; i < n; i++) r.AddRange(l);
        return r;
    }
}

/// <summary>
/// Когда можно печатать вторую сторону: только после того, как очередь принтера опустела
/// (первое задание ушло). Печать оборотов раньше смешает бумагу.
/// </summary>
public sealed class DuplexGate
{
    public bool QueueChecked { get; private set; }
    public bool FrontFinished { get; private set; }

    /// <summary>Вызывается после каждого опроса очереди; <paramref name="jobsInQueue"/> — число заданий.</summary>
    public void Update(int jobsInQueue)
    {
        QueueChecked = true;
        if (jobsInQueue == 0) FrontFinished = true;
    }

    public void MarkFinished() { QueueChecked = true; FrontFinished = true; }
    public bool CanPrintBacks => QueueChecked && FrontFinished;
}
