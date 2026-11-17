using System;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;

namespace Ottisk.App;

/// <summary>
/// Отдельный STA-поток со своим диспетчером. WPF-рисование (DrawingVisual, RenderTargetBitmap) требует STA,
/// а в главном потоке оно подвешивает окно — поэтому превью рисуется здесь.
/// Задачи выполняются по очереди; отменённая до старта задача не выполняется вовсе.
/// </summary>
public sealed class StaWorker : IDisposable
{
    private static readonly Lazy<StaWorker> _preview = new(() => new StaWorker("Ottisk preview"));
    public static StaWorker Preview => _preview.Value;

    private readonly Dispatcher _dispatcher;

    public StaWorker(string name)
    {
        Dispatcher? dispatcher = null;
        using var ready = new ManualResetEventSlim();
        var thread = new Thread(() =>
        {
            dispatcher = Dispatcher.CurrentDispatcher;
            ready.Set();
            Dispatcher.Run();
        })
        { IsBackground = true, Name = name };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        ready.Wait();
        _dispatcher = dispatcher!;
    }

    public Task<T> Run<T>(Func<T> work, CancellationToken ct = default) =>
        _dispatcher.InvokeAsync(work, DispatcherPriority.Normal, ct).Task;

    public void Dispose() => _dispatcher.BeginInvokeShutdown(DispatcherPriority.Normal);
}
