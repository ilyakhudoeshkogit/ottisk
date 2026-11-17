using System;
using System.IO;
using Ottisk.Core;

namespace Ottisk.App;

/// <summary>Файл настроек пользователя: %APPDATA%\Ottisk\settings.json. Формат и значения по умолчанию — в Ottisk.Core.UserSettings.</summary>
public static class AppSettings
{
    private static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Ottisk", "settings.json");

    public static UserSettings Load()
    {
        try { return File.Exists(FilePath) ? UserSettings.FromJson(File.ReadAllText(FilePath)) : new(); }
        catch { return new(); }
    }

    public static void Save(this UserSettings s)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            var tmp = FilePath + ".tmp";
            File.WriteAllText(tmp, s.ToJson());
            File.Move(tmp, FilePath, overwrite: true);
        }
        catch { }
    }
}
