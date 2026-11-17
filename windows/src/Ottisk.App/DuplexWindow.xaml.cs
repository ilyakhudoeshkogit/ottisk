using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using Ottisk.Core;

namespace Ottisk.App;

public partial class DuplexWindow : Window
{
    private readonly string _printer;
    private readonly DuplexGate _gate = new();
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1.5) };
    private readonly DateTime _started = DateTime.Now;
    private bool _polling;

    /// <param name="faceUp">Принтер выкладывает листы лицом вверх — стопку нужно перевернуть.</param>
    /// <param name="testSheet">Пробный лист: другие слова, без лишних подсказок.</param>
    public DuplexWindow(string printerFullName, int sheets, int backs, bool faceUp = false, bool testSheet = false)
    {
        InitializeComponent();
        _printer = printerFullName;
        if (faceUp)
        {
            Step2Text.Text = "Переверните стопку, как страницу книги: напечатанная сторона должна оказаться снизу.";
            TurnIcon.Text = "⇅";
            TurnLabel.Text = "перевернуть";
        }
        if (testSheet)
        {
            HeaderText.Text = "Лицевая сторона пробного листа готова";
            CountText.Text = "Положите этот один лист обратно так, как написано выше. Сейчас на обороте напечатается «2».";
        }
        else
            CountText.Text = $"Положите обратно всю стопку: {sheets} лист(ов). Если оборот вышел вверх ногами — напечатайте пробный лист (раздел «Дополнительно»).";
        _timer.Tick += async (_, _) => await PollAsync();
        _timer.Start();
        Closed += (_, _) => _timer.Stop();
    }

    private async Task PollAsync()
    {
        if (_polling) return;
        _polling = true;
        try
        {
            var jobs = await Task.Run(() => PrintService.JobsInQueue(_printer));
            // Не раньше 4 секунд: задание могло ещё не появиться в очереди.
            if (DateTime.Now - _started > TimeSpan.FromSeconds(4)) _gate.Update(jobs);
            if (_gate.CanPrintBacks)
            {
                GoButton.IsEnabled = true;
                WaitText.Text = "Принтер закончил. Можно перекладывать бумагу.";
                WaitText.Foreground = System.Windows.Media.Brushes.DarkGreen;
                _timer.Stop();
            }
            else if (DateTime.Now - _started > TimeSpan.FromSeconds(25))
            {
                SkipButton.Visibility = Visibility.Visible;
            }
        }
        finally { _polling = false; }
    }

    private void Go_Click(object sender, RoutedEventArgs e) { DialogResult = true; }
    private void Skip_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show(this, "Убедитесь, что все листы уже вышли из принтера. Продолжить?", "Оттиск", MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes)
            DialogResult = true;
    }
    private void Cancel_Click(object sender, RoutedEventArgs e) { DialogResult = false; }
}
