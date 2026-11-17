namespace Ottisk.Core;

public sealed record BookletSide(PageSlot Left, PageSlot Right);

/// <summary>
/// Раскладка «для сгиба». Для 8 страниц: лист 1 — лицо [8|1], оборот [2|7]; лист 2 — лицо [6|3], оборот [4|5].
/// Число страниц дополняется пустыми до кратного 4 (в конце).
/// </summary>
public static class BookletPlanner
{
    public static int PaddedCount(int pageCount) => pageCount <= 0 ? 0 : (pageCount + 3) / 4 * 4;

    /// <summary>Стороны в порядке «лицо, оборот, лицо, оборот…».</summary>
    public static IReadOnlyList<BookletSide> Sides(IReadOnlyList<int> pages)
    {
        var total = PaddedCount(pages.Count);
        var result = new List<BookletSide>();
        PageSlot Slot(int pos) => pos <= pages.Count ? PageSlot.Of(pages[pos - 1]) : PageSlot.Blank;
        for (var i = 0; i < total / 4; i++)
        {
            result.Add(new BookletSide(Slot(total - 2 * i), Slot(2 * i + 1)));
            result.Add(new BookletSide(Slot(2 * i + 2), Slot(total - 2 * i - 1)));
        }
        return result;
    }
}
