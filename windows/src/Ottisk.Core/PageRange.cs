namespace Ottisk.Core;

/// <summary>Ошибка в диапазоне страниц, сообщение — по-русски и понятное.</summary>
public sealed class PageRangeException : Exception
{
    public PageRangeException(string message) : base(message) { }
}

/// <summary>Разбор диапазона страниц, который вводит человек: «1-3, 5, 8-».</summary>
public static class PageRange
{
    public static IReadOnlyList<int> Parse(string? text, int pageCount)
    {
        if (pageCount <= 0) throw new PageRangeException("В документе нет страниц");
        var cleaned = (text ?? "").Replace('–', '-').Replace('—', '-').Replace(';', ',').Trim();
        if (cleaned.Length == 0) return Enumerable.Range(1, pageCount).ToList();

        var pages = new SortedSet<int>();
        foreach (var raw in cleaned.Split(',', StringSplitOptions.RemoveEmptyEntries))
        {
            var token = raw.Replace(" ", "");
            if (token.Length == 0) continue;
            var dash = token.IndexOf('-');
            if (dash >= 0)
            {
                var left = token[..dash];
                var right = token[(dash + 1)..];
                if (right.Contains('-')) throw Invalid(token);
                int s = 1, e = pageCount;
                if (left.Length > 0 && !int.TryParse(left, out s)) throw Invalid(token);
                if (right.Length > 0 && !int.TryParse(right, out e)) throw Invalid(token);
                if (s <= 0 || e <= 0) throw Invalid(token);
                if (s > e) throw new PageRangeException($"«{token}»: начало больше конца");
                if (s > pageCount) throw OutOfBounds(s, pageCount);
                if (e > pageCount) throw OutOfBounds(e, pageCount);
                for (var p = s; p <= e; p++) pages.Add(p);
            }
            else
            {
                if (!int.TryParse(token, out var p) || p <= 0) throw Invalid(token);
                if (p > pageCount) throw OutOfBounds(p, pageCount);
                pages.Add(p);
            }
        }
        if (pages.Count == 0) throw new PageRangeException("В диапазон не попала ни одна страница");
        return pages.ToList();
    }

    private static PageRangeException Invalid(string t) => new($"Не понял «{t}». Пример: 1-3, 5, 8-");
    private static PageRangeException OutOfBounds(int p, int max) => new($"Страницы {p} нет — в документе {max}");
}
