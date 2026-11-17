using System;
using System.Collections.Generic;
using System.Linq;
using System.Printing;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using Ottisk.Core;
using Rect = System.Windows.Rect;

namespace Ottisk.App;

public sealed class PrinterInfo
{
    public required string Name { get; init; }
    public required string FullName { get; init; }
    public bool IsDefault { get; init; }
    public override string ToString() => Name;
}

public sealed class PrinterCaps
{
    public bool CanChooseColor { get; init; }
    public bool MonochromeOnly { get; init; }
    /// <summary>Какие из форматов A4 / A5 / Letter умеет принтер (если драйвер не сказал — все).</summary>
    public IReadOnlyList<PaperKind> Papers { get; init; } = Ottisk.Core.Papers.All;
    public string Status { get; init; } = "";
}

/// <summary>Работа с очередями печати Windows. Принтеры берутся из системы, модель не важна.</summary>
public static class PrintService
{
    public static (List<PrinterInfo> list, string? defaultName) ListPrinters()
    {
        var result = new List<PrinterInfo>();
        string? def = null;
        try
        {
            using var server = new LocalPrintServer();
            try { using var d = server.DefaultPrintQueue; def = d.FullName; } catch { }
            foreach (var q in server.GetPrintQueues(new[] { EnumeratedPrintQueueTypes.Local, EnumeratedPrintQueueTypes.Connections }))
            {
                result.Add(new PrinterInfo { Name = q.Name, FullName = q.FullName, IsDefault = q.FullName == def });
                q.Dispose();
            }
        }
        catch { }
        return (result.OrderByDescending(p => p.IsDefault).ThenBy(p => p.Name).ToList(), def);
    }

    public static PrintQueue? Open(string fullName)
    {
        try { return new LocalPrintServer().GetPrintQueue(fullName); }
        catch
        {
            try
            {
                // Сетевые принтеры вида \\server\name
                if (fullName.StartsWith(@"\\"))
                {
                    var idx = fullName.IndexOf('\\', 2);
                    if (idx > 0) return new PrintServer(fullName[..idx]).GetPrintQueue(fullName[(idx + 1)..]);
                }
            }
            catch { }
            return null;
        }
    }

    public static PrinterCaps GetCaps(string fullName)
    {
        try
        {
            using var q = Open(fullName);
            if (q == null) return new PrinterCaps { Status = "Принтер недоступен" };
            var status = DescribeStatus(q);
            bool color = false, mono = false;
            IReadOnlyList<PaperKind> papers = Ottisk.Core.Papers.All;
            try
            {
                var caps = q.GetPrintCapabilities();
                color = caps.OutputColorCapability.Contains(OutputColor.Color);
                mono = caps.OutputColorCapability.Contains(OutputColor.Monochrome);
                papers = Ottisk.Core.Papers.Available(caps.PageMediaSizeCapability?.Select(m =>
                    (m.PageMediaSizeName?.ToString(), (m.Width ?? 0) * 25.4 / 96, (m.Height ?? 0) * 25.4 / 96)));
            }
            catch { }
            return new PrinterCaps { CanChooseColor = color && mono, MonochromeOnly = mono && !color, Papers = papers, Status = status };
        }
        catch { return new PrinterCaps { Status = "" }; }
    }

    public static string DescribeStatus(PrintQueue q)
    {
        try
        {
            q.Refresh();
            var s = q.QueueStatus;
            if (s.HasFlag(PrintQueueStatus.Offline)) return "Принтер выключен или не подключён";
            if (s.HasFlag(PrintQueueStatus.PaperOut)) return "В принтере закончилась бумага";
            if (s.HasFlag(PrintQueueStatus.PaperJam)) return "Замялась бумага";
            if (s.HasFlag(PrintQueueStatus.DoorOpen)) return "Открыта крышка принтера";
            if (s.HasFlag(PrintQueueStatus.TonerLow)) return "Заканчивается тонер";
            if (s.HasFlag(PrintQueueStatus.Paused)) return "Печать приостановлена";
            if (s.HasFlag(PrintQueueStatus.Error)) return "Ошибка принтера";
            return "Готов к печати";
        }
        catch { return ""; }
    }

    public static int JobsInQueue(string fullName)
    {
        try
        {
            using var q = Open(fullName);
            if (q == null) return 0;
            q.Refresh();
            return q.NumberOfJobs;
        }
        catch { return 0; }
    }

    /// <summary>Носитель для билета печати: тот, что предлагает драйвер, иначе стандартный по имени.</summary>
    private static PageMediaSize? MediaFor(PaperKind paper, PrintCapabilities caps)
    {
        var offered = caps.PageMediaSizeCapability;
        if (offered != null && offered.Count > 0)
            return offered.FirstOrDefault(m => Ottisk.Core.Papers.FromName(m.PageMediaSizeName?.ToString()) == paper)
                ?? offered.FirstOrDefault(m => m.Width is double w && m.Height is double h
                       && Ottisk.Core.Papers.FromSize(w * 25.4 / 96, h * 25.4 / 96) == paper);
        var size = Ottisk.Core.Papers.Size(paper);
        var name = paper switch { PaperKind.A5 => PageMediaSizeName.ISOA5, PaperKind.Letter => PageMediaSizeName.NorthAmericaLetter, _ => PageMediaSizeName.ISOA4 };
        return new PageMediaSize(name, size.W * SideRenderer.DipPerMm, size.H * SideRenderer.DipPerMm);
    }

    /// <summary>Отправляет один проход в очередь. Блокирует поток — вызывать не из UI.</summary>
    public static void PrintPass(string printerFullName, JobPlan plan, PrintPass pass, DocumentSource doc, bool mono, string title, PaperKind paper = PaperKind.A4)
    {
        using var q = Open(printerFullName) ?? throw new FriendlyException("Не удалось связаться с принтером. Проверьте, что он включён.");
        var ticket = (q.UserPrintTicket ?? q.DefaultPrintTicket).Clone();
        ticket.PageOrientation = plan.Sheet.IsLandscape ? PageOrientation.Landscape : PageOrientation.Portrait;
        ticket.CopyCount = 1;
        try
        {
            var caps = q.GetPrintCapabilities(ticket);
            if (caps.DuplexingCapability.Contains(Duplexing.OneSided)) ticket.Duplexing = Duplexing.OneSided;
            if (caps.OutputColorCapability.Contains(OutputColor.Monochrome) && caps.OutputColorCapability.Contains(OutputColor.Color))
                ticket.OutputColor = mono ? OutputColor.Monochrome : OutputColor.Color;
            if (caps.PageScalingFactorRange != null) ticket.PageScalingFactor = 100;
            var media = MediaFor(paper, caps);
            if (media != null) ticket.PageMediaSize = media;
        }
        catch { /* драйвер не рассказал о возможностях — печатаем с настройками по умолчанию */ }

        var dlg = new PrintDialog { PrintQueue = q, PrintTicket = ticket };
        var paginator = new SidePaginator(pass.Sides, doc, mono, new Size(plan.Sheet.W * SideRenderer.DipPerMm, plan.Sheet.H * SideRenderer.DipPerMm));
        dlg.PrintDocument(paginator, title);
    }
}

/// <summary>Страницы задания: каждая сторона рисуется в момент печати (экономим память).</summary>
public sealed class SidePaginator : DocumentPaginator
{
    private readonly IReadOnlyList<SideLayout> _sides;
    private readonly DocumentSource _doc;
    private readonly bool _mono;
    private Size _size;

    public SidePaginator(IReadOnlyList<SideLayout> sides, DocumentSource doc, bool mono, Size size)
    { _sides = sides; _doc = doc; _mono = mono; _size = size; }

    public override bool IsPageCountValid => true;
    public override int PageCount => _sides.Count;
    public override Size PageSize { get => _size; set => _size = value; }
    public override IDocumentPaginatorSource? Source => null;

    public override DocumentPage GetPage(int pageNumber)
    {
        var side = _sides[pageNumber];
        var visual = SideRenderer.Draw(side, _doc, 300 / 25.4, _mono, true);
        return new DocumentPage(visual, _size, new Rect(_size), new Rect(_size));
    }
}
