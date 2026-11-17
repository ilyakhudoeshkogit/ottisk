using System;
using System.Windows;
using System.Windows.Threading;

namespace Ottisk.App;

public partial class App : Application
{
    public static string? StartupFile { get; private set; }

    protected override void OnStartup(StartupEventArgs e)
    {
        if (e.Args.Length > 0) StartupFile = e.Args[0];
        DispatcherUnhandledException += OnCrash;
        base.OnStartup(e);
    }

    private static void OnCrash(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        e.Handled = true;
        MessageBox.Show("Что-то пошло не так, но ничего не потеряно.\n\nЗакройте программу и откройте её снова.\n\n(" + e.Exception.Message + ")",
            "Оттиск", MessageBoxButton.OK, MessageBoxImage.Warning);
    }
}
