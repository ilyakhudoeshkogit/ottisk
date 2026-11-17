using System.Windows;
using Ottisk.Core;

namespace Ottisk.App;

public partial class CalibrationWindow : Window
{
    public CalibrationResult? Result { get; private set; }

    public CalibrationWindow() { InitializeComponent(); }

    private void Done(CalibrationResult r) { Result = r; DialogResult = true; }
    private void Correct_Click(object sender, RoutedEventArgs e) => Done(CalibrationResult.Correct);
    private void UpsideDown_Click(object sender, RoutedEventArgs e) => Done(CalibrationResult.BackUpsideDown);
    private void SameSide_Click(object sender, RoutedEventArgs e) => Done(CalibrationResult.BackOnSameSide);
    private void Cancel_Click(object sender, RoutedEventArgs e) { DialogResult = false; }
}
