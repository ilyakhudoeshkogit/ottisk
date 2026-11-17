using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ottisk.Core;

/// <summary>Что запоминаем между запусками (%APPDATA%\Ottisk\settings.json). Только то, что не хочется вводить второй раз.</summary>
public sealed class UserSettings
{
    public string? Printer { get; set; }
    public bool FlipBacks { get; set; }
    public bool ReverseBacks { get; set; } = true;
    public PaperKind Paper { get; set; } = PaperKind.A4;
    /// <summary>Пробный лист уже печатали (подсказку можно не показывать).</summary>
    public bool Calibrated { get; set; }

    // 0.3.0. Сами галочки (номера, обрезка, водяной знак) при запуске выключены — чтобы случайно
    // не напечатать «ЧЕРНОВИК» на всём подряд; запоминаем только то, что неудобно вводить заново.
    /// <summary>С какого номера начинать нумерацию.</summary>
    public int NumberStart { get; set; } = 1;
    /// <summary>Без номера на первой странице (титул).</summary>
    public bool NumberSkipTitle { get; set; } = true;
    /// <summary>Последний текст водяного знака.</summary>
    public string WatermarkText { get; set; } = Watermark.Suggestions[0];

    /// <summary>Нумерация из запомненных значений (включена или нет — решает человек).</summary>
    public PageNumbering Numbering(bool enabled) => new(enabled, NumberStart, NumberSkipTitle ? 1 : 0);

    [JsonIgnore]
    public DuplexHandling Duplex
    {
        get => new(FlipBacks, !ReverseBacks);
        set { FlipBacks = value.FlipBacks; ReverseBacks = value.ReverseBacks; }
    }

    static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public string ToJson() => JsonSerializer.Serialize(this, Json);

    /// <summary>Битый или пустой файл — настройки по умолчанию, без ошибок.</summary>
    public static UserSettings FromJson(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new();
        try
        {
            var s = JsonSerializer.Deserialize<UserSettings>(json, Json) ?? new();
            if (!Enum.IsDefined(s.Paper)) s.Paper = PaperKind.A4;
            s.NumberStart = Math.Clamp(s.NumberStart, 0, PageNumbering.MaxStart);
            if (string.IsNullOrWhiteSpace(s.WatermarkText)) s.WatermarkText = Watermark.Suggestions[0];
            else if (s.WatermarkText.Length > 40) s.WatermarkText = s.WatermarkText[..40];
            return s;
        }
        catch (Exception) { return new(); }
    }
}
