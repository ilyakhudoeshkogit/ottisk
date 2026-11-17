using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using Ottisk.Core;

namespace Ottisk.App;

public partial class MainWindow : Window
{
    private readonly UserSettings _settings = AppSettings.Load();
    private DocumentSource? _doc;
    private PrintOptions _opt = new();
    private PrinterCaps _caps = new();
    private JobPlan? _plan;
    private List<(SideLayout side, string caption)> _flat = new();
    private int _index;
    private int _renderVersion;
    private bool _ready;
    private bool _busy;
    private readonly DispatcherTimer _debounce = new() { Interval = TimeSpan.FromMilliseconds(200) };
    private readonly Dictionary<PresetKind, RadioButton> _presetButtons = new();
    // Обрезка белых полей: найденные рамки для текущего документа (считаются один раз на документ).
    private DocumentSource? _boxesDoc;
    private Dictionary<int, Ottisk.Core.Rect>? _boxes;
    private CancellationTokenSource? _scanCts;
    private Task<Dictionary<int, Ottisk.Core.Rect>>? _scanTask;
    private DocumentSource? _scanDoc;
    private bool _syncing;
    // Превью (0.4.0): готовые картинки листов текущего плана, отмена устаревшего рендера.
    private const double PreviewDpi = 110;
    private const int PreviewCacheMax = 16;
    private readonly Dictionary<(int plan, int index, bool mono), BitmapSource> _previewCache = new();
    private int _planId;
    private CancellationTokenSource? _previewCts;

    public MainWindow()
    {
        InitializeComponent();
        FlipBox.IsChecked = _settings.FlipBacks;
        FaceUpBox.IsChecked = !_settings.ReverseBacks;
        _opt = _opt with { Paper = _settings.Paper, Numbering = _settings.Numbering(false) };
        WatermarkCombo.ItemsSource = Watermark.Suggestions;
        WatermarkCombo.Text = _settings.WatermarkText;
        WatermarkCombo.AddHandler(TextBoxBase.TextChangedEvent, new TextChangedEventHandler((_, _) => WatermarkText_Changed()));
        WatermarkCombo.SelectionChanged += (_, _) => WatermarkText_Changed();
        SyncNumberingUi();
        BuildPresets();
        FillPapers(Papers.All);
        _debounce.Tick += (_, _) => { _debounce.Stop(); Recompute(); };
        Loaded += async (_, _) =>
        {
            _ready = true;
            await LoadPrintersAsync();
            if (App.StartupFile != null) LoadFile(App.StartupFile);
        };
    }

    // ---------- Принтеры ----------

    private async Task LoadPrintersAsync()
    {
        PrinterStatus.Text = "Ищу принтеры…";
        var listing = Task.Run(PrintService.ListPrinters);
        // Сетевой принтер может отвечать долго — окно при этом живое, просто подскажем.
        if (await Task.WhenAny(listing, Task.Delay(TimeSpan.FromSeconds(10))) != listing)
            PrinterStatus.Text = "Windows долго отвечает про принтеры, подождите…";
        var (list, def) = await listing;
        PrinterStatus.Text = "";
        PrinterBox.ItemsSource = list;
        var want = list.FirstOrDefault(p => p.FullName == _settings.Printer) ?? list.FirstOrDefault(p => p.IsDefault) ?? list.FirstOrDefault();
        if (want != null) PrinterBox.SelectedItem = want;
        else PrinterStatus.Text = "Принтеры не найдены. Подключите принтер и перезапустите программу.";
    }

    private async void Printer_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (!_ready || PrinterBox.SelectedItem is not PrinterInfo p) return;
        _settings.Printer = p.FullName; _settings.Save();
        PrinterStatus.Text = "Проверяю принтер…";
        var caps = await Task.Run(() => PrintService.GetCaps(p.FullName));
        if (PrinterBox.SelectedItem != p) return;
        _caps = caps;
        PrinterStatus.Text = caps.Status;
        FillPapers(caps.Papers);
        MonoBox.IsEnabled = caps.CanChooseColor;
        if (caps.CanChooseColor) MonoNote.Text = "";
        else { MonoBox.IsChecked = false; MonoNote.Text = caps.MonochromeOnly ? "Этот принтер печатает только чёрно-белое" : "Для этого принтера выбор цвета недоступен"; }
        Recompute();
    }

    // ---------- Пресеты ----------

    private void BuildPresets()
    {
        foreach (var k in Presets.Shown)
        {
            var rb = new RadioButton { GroupName = "preset", Tag = k, Margin = new Thickness(0, 0, 0, 6), IsChecked = k == PresetKind.Normal };
            var panel = new StackPanel { Margin = new Thickness(6, 4, 0, 4) };
            panel.Children.Add(new TextBlock { Text = Presets.Title(k), FontSize = 18, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
            panel.Children.Add(new TextBlock { Text = Presets.Hint(k), FontSize = 13, Foreground = new SolidColorBrush(Color.FromRgb(0x60, 0x7D, 0x8B)), TextWrapping = TextWrapping.Wrap });
            rb.Content = panel;
            rb.VerticalContentAlignment = VerticalAlignment.Center;
            rb.Checked += (_, _) => { if (_ready) { _opt = Presets.Apply(k, _opt); UpdateGutterBox(); SyncNumberingUi(); Schedule(); } };
            _presetButtons[k] = rb;
            PresetPanel.Children.Add(rb);
        }
    }

    private void UpdateGutterBox()
    {
        var own = Presets.HasOwnGutter(_opt.Preset);
        GutterBox.IsEnabled = !own;
        GutterNote.Visibility = own ? Visibility.Visible : Visibility.Collapsed;
    }

    // ---------- Номера страниц, обрезка, водяной знак (0.3.0) ----------

    private void SyncNumberingUi()
    {
        _syncing = true;
        var n = _opt.Numbering;
        NumbersBox.IsChecked = n.Enabled;
        NumbersPanel.IsEnabled = n.Enabled;
        NumberStartText.Text = n.StartAt.ToString();
        SkipTitleBox.IsChecked = n.SkipFirst > 0;
        _syncing = false;
    }

    private void SetNumbering(PageNumbering n)
    {
        _opt = _opt with { Numbering = n };
        _settings.NumberStart = n.StartAt;
        _settings.NumberSkipTitle = n.SkipFirst > 0;
        _settings.Save();
        SyncNumberingUi();
        if (_ready) Schedule();
    }

    private void Numbering_Changed(object sender, RoutedEventArgs e)
    {
        if (_syncing) return;
        SetNumbering(_opt.Numbering with { Enabled = NumbersBox.IsChecked == true, SkipFirst = SkipTitleBox.IsChecked == true ? 1 : 0 });
    }

    private void NumberMinus_Click(object sender, RoutedEventArgs e) =>
        SetNumbering(_opt.Numbering with { StartAt = Math.Max(1, _opt.Numbering.StartAt - 1) });
    private void NumberPlus_Click(object sender, RoutedEventArgs e) =>
        SetNumbering(_opt.Numbering with { StartAt = Math.Min(PageNumbering.MaxStart, _opt.Numbering.StartAt + 1) });

    private void Trim_Changed(object sender, RoutedEventArgs e) { if (_ready) Schedule(); }

    private void Watermark_Changed(object sender, RoutedEventArgs e)
    {
        WatermarkCombo.IsEnabled = WatermarkBox.IsChecked == true;
        if (_ready) Schedule();
    }

    private void WatermarkText_Changed()
    {
        var text = WatermarkCombo.Text?.Trim() ?? "";
        if (text.Length > 0 && text.Length <= 40 && text != _settings.WatermarkText) { _settings.WatermarkText = text; _settings.Save(); }
        if (_ready && WatermarkBox.IsChecked == true) Schedule();
    }

    private Ottisk.Core.Rect? ContentBox(int page) =>
        _boxes != null && _boxes.TryGetValue(page, out var r) ? r : null;

    // ---------- Бумага ----------

    private bool _fillingPapers;

    private void FillPapers(IReadOnlyList<PaperKind> available)
    {
        _fillingPapers = true;
        PaperBox.ItemsSource = available.Select(k => new PaperItem(k)).ToList();
        var chosen = Papers.Choose(_settings.Paper, available);
        PaperBox.SelectedItem = ((List<PaperItem>)PaperBox.ItemsSource).First(i => i.Kind == chosen);
        PaperBox.IsEnabled = available.Count > 1;
        _opt = _opt with { Paper = chosen };
        _fillingPapers = false;
    }

    private void Paper_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_fillingPapers || PaperBox.SelectedItem is not PaperItem item) return;
        _opt = _opt with { Paper = item.Kind };
        _settings.Paper = item.Kind; _settings.Save();
        if (_ready) Schedule();
    }

    private sealed record PaperItem(PaperKind Kind) { public override string ToString() => Papers.Title(Kind); }

    // ---------- Пробный лист ----------

    private async void TestSheet_Click(object sender, RoutedEventArgs e)
    {
        if (_busy) return;
        if (PrinterBox.SelectedItem is not PrinterInfo printer)
        {
            MessageBox.Show(this, "Не выбран принтер. Подключите принтер к компьютеру и перезапустите программу.", "Оттиск", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (MessageBox.Show(this, $"Положите в принтер один чистый лист ({Papers.Title(_opt.Paper)}).\n\nСначала напечатается сторона с цифрой «1», потом Оттиск подскажет, как положить лист обратно.",
                "Пробный лист", MessageBoxButton.OKCancel, MessageBoxImage.Information) != MessageBoxResult.OK) return;
        var handling = new DuplexHandling(FlipBox.IsChecked == true, FaceUpBox.IsChecked == true);
        var paper = _opt.Paper;
        var plan = DuplexCalibration.Plan(paper, handling);
        using var doc = new TestSheetDocument(Papers.Size(paper));
        const string title = "Оттиск — пробный лист";
        try
        {
            SetBusy(true, "Печатаю лицевую сторону…");
            await Task.Run(() => RunSta(() => PrintService.PrintPass(printer.FullName, plan, plan.Passes[0], doc, false, title, paper)));
            SetBusy(false, "");
            var dlg = new DuplexWindow(printer.FullName, 1, 1, handling.FaceUp, testSheet: true) { Owner = this };
            if (dlg.ShowDialog() != true) return;
            SetBusy(true, "Печатаю обратную сторону…");
            await Task.Run(() => RunSta(() => PrintService.PrintPass(printer.FullName, plan, plan.Passes[1], doc, false, title + " (оборот)", paper)));
            SetBusy(false, "");
            var ask = new CalibrationWindow { Owner = this };
            if (ask.ShowDialog() != true || ask.Result is not { } result) return;
            var fixedH = DuplexCalibration.Apply(handling, result);
            FlipBox.IsChecked = fixedH.FlipBacks;
            FaceUpBox.IsChecked = fixedH.FaceUp;
            _settings.Duplex = fixedH;
            _settings.Calibrated = result == CalibrationResult.Correct || _settings.Calibrated;
            _settings.Save();
            Schedule();
            MessageBox.Show(this, DuplexCalibration.Message(result), "Оттиск", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (FriendlyException ex)
        {
            SetBusy(false, "");
            MessageBox.Show(this, ex.Message, "Оттиск", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        catch (Exception ex)
        {
            SetBusy(false, "");
            MessageBox.Show(this, "Не получилось отправить на печать.\nПроверьте, что принтер включён и в нём есть бумага.\n\n(" + ex.Message + ")",
                "Оттиск", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    // ---------- Файл ----------

    private void Open_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Title = "Что напечатать?",
            Filter = "PDF и фото|*.pdf;*.jpg;*.jpeg;*.png;*.bmp;*.gif;*.tif;*.tiff|Все файлы|*.*"
        };
        if (dlg.ShowDialog(this) == true) LoadFile(dlg.FileName);
    }

    private void Window_DragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) && !_busy ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private void Window_Drop(object sender, DragEventArgs e)
    {
        if (_busy || e.Data.GetData(DataFormats.FileDrop) is not string[] files || files.Length == 0) return;
        LoadFile(files[0]);
    }

    private async void LoadFile(string path)
    {
        try
        {
            SetBusyPreview(true);
            var doc = await Task.Run(() => DocumentSource.Open(path));
            _doc?.Dispose();
            _doc = doc;
            FileText.Text = $"{doc.FileName}\n{Pluralize(doc.PageCount, "страница", "страницы", "страниц")}";
            _index = 0;
            EmptyHint.Visibility = Visibility.Collapsed;
            Recompute();
        }
        catch (FriendlyException ex)
        {
            SetBusyPreview(false);
            MessageBox.Show(this, ex.Message, "Оттиск", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception)
        {
            SetBusyPreview(false);
            MessageBox.Show(this, "Не удалось открыть этот файл.", "Оттиск", MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    // ---------- Настройки ----------

    private void Pages_Changed(object sender, RoutedEventArgs e)
    {
        if (!_ready) return;
        RangeBox.IsEnabled = SomePages.IsChecked == true;
        if (SomePages.IsChecked == true) RangeBox.Focus();
        Schedule();
    }
    private void Range_Changed(object sender, TextChangedEventArgs e) { if (_ready) Schedule(); }
    private void Options_Changed(object sender, RoutedEventArgs e)
    {
        if (!_ready) return;
        _settings.FlipBacks = FlipBox.IsChecked == true;
        _settings.ReverseBacks = FaceUpBox.IsChecked != true;
        _settings.Save();
        Schedule();
    }
    private void CopiesMinus_Click(object sender, RoutedEventArgs e) { _opt = _opt with { Copies = Math.Max(1, _opt.Copies - 1) }; CopiesText.Text = _opt.Copies.ToString(); Schedule(); }
    private void CopiesPlus_Click(object sender, RoutedEventArgs e) { _opt = _opt with { Copies = Math.Min(99, _opt.Copies + 1) }; CopiesText.Text = _opt.Copies.ToString(); Schedule(); }

    private PrintOptions CurrentOptions() => _opt with
    {
        PageRangeText = SomePages.IsChecked == true ? RangeBox.Text : "",
        GutterMm = GutterBox.IsChecked == true ? 20 : 0,
        TrimWhite = TrimBox.IsChecked == true,
        Watermark = new Watermark(WatermarkBox.IsChecked == true ? WatermarkCombo.Text ?? "" : ""),
        FlipBacks = FlipBox.IsChecked == true,
        ReverseBacks = FaceUpBox.IsChecked != true,
    };

    private bool Mono => MonoBox.IsChecked == true && MonoBox.IsEnabled;

    private void Schedule() { _debounce.Stop(); _debounce.Start(); }

    // ---------- План и превью ----------

    private async void Recompute()
    {
        var version = ++_renderVersion;
        RangeError.Text = "";
        _plan = null;
        if (_doc == null) { SummaryText.Text = " "; PrintButton.IsEnabled = false; UpdateNav(); return; }
        var doc = _doc;
        var opt = CurrentOptions();
        if (opt.TrimWhite && _boxesDoc != doc)
        {
            // Белые поля ищем один раз на документ, в фоне; повторные пересчёты ждут тот же поиск.
            if (_scanDoc != doc || _scanTask == null)
            {
                _scanCts?.Cancel();
                var cts = _scanCts = new CancellationTokenSource();
                _scanDoc = doc;
                _scanTask = Task.Run(() => ContentScan.Compute(doc, cts.Token));
            }
            SetBusyPreview(true);
            BusyText.Text = "Ищу белые поля…";
            try
            {
                var boxes = await _scanTask;
                if (_doc == doc) { _boxes = boxes; _boxesDoc = doc; }
            }
            catch (OperationCanceledException) { return; }
            catch (Exception) { if (_doc == doc) { _boxes = new(); _boxesDoc = doc; } }
            finally { BusyText.Text = "Готовлю картинку…"; }
            if (version != _renderVersion) return;
        }
        try
        {
            _plan = LayoutPlanner.Plan(doc.PageCount, doc.PageSizeMm, opt, opt.TrimWhite && _boxesDoc == doc ? ContentBox : null);
            _planId++;
            _previewCache.Clear();
        }
        catch (PageRangeException ex)
        {
            RangeError.Text = ex.Message;
            SummaryText.Text = "Исправьте страницы — и печать станет доступна";
            PrintButton.IsEnabled = false;
            SetBusyPreview(false);
            return;
        }

        _flat = new();
        foreach (var pass in _plan.Passes)
        {
            var i = 0;
            foreach (var s in pass.Sides)
            {
                i++;
                string cap = _plan.Passes.Count > 1
                    ? $"{pass.Title}\nлист {i} из {pass.Sides.Count}"
                    : $"Лист {i} из {pass.Sides.Count}";
                if (s.IsBlankSide) cap += "\n(пустая сторона — так нужно для порядка)";
                _flat.Add((s, cap));
            }
        }
        _index = Math.Clamp(_index, 0, Math.Max(0, _flat.Count - 1));
        var sheets = _plan.Passes.Count > 1 ? _plan.Passes[0].Sides.Count : _plan.Passes[0].Sides.Count;
        SummaryText.Text = _plan.Passes.Count > 1
            ? $"Будет напечатано: {Pluralize(sheets, "лист", "листа", "листов")} бумаги, в два захода"
            : $"Будет напечатано: {Pluralize(sheets, "лист", "листа", "листов")} бумаги";
        PrintButton.IsEnabled = !_busy;
        UpdateNav();
        await ShowCurrentAsync(version);
    }

    private async Task ShowCurrentAsync(int version)
    {
        if (_flat.Count == 0 || _doc == null) return;
        var index = _index;
        var (side, _) = _flat[index];
        var doc = _doc;
        var mono = Mono;
        var planId = _planId;
        if (_previewCache.TryGetValue((planId, index, mono), out var cached))
        {
            ShowPreview(cached);
            Prefetch(planId, index, doc, mono);
            return;
        }
        _previewCts?.Cancel();
        var cts = _previewCts = new CancellationTokenSource();
        SetBusyPreview(true);
        try
        {
            var bmp = await RenderSideAsync(side, doc, mono, cts.Token);
            if (planId == _planId) Remember(planId, index, mono, bmp);
            if (version != _renderVersion) return;
            ShowPreview(bmp);
            Prefetch(planId, index, doc, mono);
        }
        catch (OperationCanceledException) { /* настройки поменялись — рисуется уже новое превью */ }
        catch (Exception)
        {
            if (version == _renderVersion) { SetBusyPreview(false); PageLabel.Text = "Не удалось нарисовать превью"; }
        }
    }

    private void ShowPreview(BitmapSource bmp)
    {
        PreviewImage.Source = bmp;
        PreviewFrame.Visibility = Visibility.Visible;
        SetBusyPreview(false);
    }

    private void Remember(int planId, int index, bool mono, BitmapSource bmp)
    {
        if (_previewCache.Count >= PreviewCacheMax) _previewCache.Clear();
        _previewCache[(planId, index, mono)] = bmp;
    }

    /// <summary>Растр страниц — в пуле потоков, рисование листа — в отдельном STA-потоке. Главный поток свободен.</summary>
    private static async Task<BitmapSource> RenderSideAsync(SideLayout side, DocumentSource doc, bool mono, CancellationToken ct)
    {
        await Task.Run(() => SideRenderer.Prewarm(side, doc, PreviewDpi, ct), ct);
        return await StaWorker.Preview.Run(() => SideRenderer.Preview(side, doc, PreviewDpi, mono), ct);
    }

    /// <summary>Соседние листы рисуются заранее — «Назад/Вперёд» показывают их сразу.</summary>
    private async void Prefetch(int planId, int index, DocumentSource doc, bool mono)
    {
        var ct = _previewCts?.Token ?? CancellationToken.None;
        foreach (var i in new[] { index + 1, index - 1 })
        {
            if (planId != _planId || _doc != doc || ct.IsCancellationRequested) return;
            if (i < 0 || i >= _flat.Count || _previewCache.ContainsKey((planId, i, mono))) continue;
            try
            {
                var bmp = await RenderSideAsync(_flat[i].side, doc, mono, ct);
                if (planId == _planId) Remember(planId, i, mono, bmp);
            }
            catch (Exception) { return; }
        }
    }

    private void SetBusyPreview(bool on) => BusyText.Visibility = on ? Visibility.Visible : Visibility.Collapsed;

    private void UpdateNav()
    {
        PrevButton.IsEnabled = _flat.Count > 1 && _index > 0;
        NextButton.IsEnabled = _flat.Count > 1 && _index < _flat.Count - 1;
        PageLabel.Text = _flat.Count > 0 ? _flat[_index].caption : "";
        if (_flat.Count == 0 && _doc == null) PreviewFrame.Visibility = Visibility.Collapsed;
    }

    private async void Prev_Click(object sender, RoutedEventArgs e) { if (_index > 0) { _index--; UpdateNav(); await ShowCurrentAsync(++_renderVersion); } }
    private async void Next_Click(object sender, RoutedEventArgs e) { if (_index < _flat.Count - 1) { _index++; UpdateNav(); await ShowCurrentAsync(++_renderVersion); } }

    // ---------- Печать ----------

    private async void Print_Click(object sender, RoutedEventArgs e)
    {
        if (_doc == null || _plan == null || _plan.Passes.Count == 0) return;
        if (PrinterBox.SelectedItem is not PrinterInfo printer)
        {
            MessageBox.Show(this, "Не выбран принтер. Подключите принтер к компьютеру и перезапустите программу.", "Оттиск", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var plan = _plan; var doc = _doc; var mono = Mono; var paper = _opt.Paper;
        var title = "Оттиск — " + doc.FileName;
        SetBusy(true, "Отправляю на принтер…");
        try
        {
            await Task.Run(() => RunSta(() => PrintService.PrintPass(printer.FullName, plan, plan.Passes[0], doc, mono, title, paper)));
            if (plan.Passes.Count > 1)
            {
                SetBusy(false, "");
                var dlg = new DuplexWindow(printer.FullName, plan.Passes[0].Sides.Count, plan.Passes[1].Sides.Count, FaceUpBox.IsChecked == true) { Owner = this };
                if (dlg.ShowDialog() == true)
                {
                    SetBusy(true, "Печатаю вторую сторону…");
                    await Task.Run(() => RunSta(() => PrintService.PrintPass(printer.FullName, plan, plan.Passes[1], doc, mono, title + " (оборот)", paper)));
                    SetBusy(false, "");
                    MessageBox.Show(this, "Готово! Вторая сторона отправлена на печать.", "Оттиск", MessageBoxButton.OK, MessageBoxImage.Information);
                }
            }
            else
            {
                SetBusy(false, "");
                MessageBox.Show(this, "Готово! Документ отправлен на принтер.", "Оттиск", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }
        catch (FriendlyException ex)
        {
            SetBusy(false, "");
            MessageBox.Show(this, ex.Message, "Оттиск", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        catch (Exception ex)
        {
            SetBusy(false, "");
            MessageBox.Show(this, "Не получилось отправить на печать.\nПроверьте, что принтер включён и в нём есть бумага.\n\n(" + ex.Message + ")",
                "Оттиск", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void SetBusy(bool on, string text)
    {
        _busy = on;
        BusyOverlayText.Text = text;
        BusyOverlay.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        PrintButton.IsEnabled = !on && _plan != null;
    }

    /// <summary>Печать WPF требует STA-потока.</summary>
    private static void RunSta(Action action)
    {
        Exception? error = null;
        var t = new Thread(() => { try { action(); } catch (Exception ex) { error = ex; } });
        t.SetApartmentState(ApartmentState.STA);
        t.Start();
        t.Join();
        if (error != null) throw error is FriendlyException ? error : new InvalidOperationException(error.Message, error);
    }

    private static string Pluralize(int n, string one, string few, string many)
    {
        var m100 = n % 100; var m10 = n % 10;
        var w = m100 is >= 11 and <= 14 ? many : m10 == 1 ? one : m10 is >= 2 and <= 4 ? few : many;
        return $"{n} {w}";
    }
}
