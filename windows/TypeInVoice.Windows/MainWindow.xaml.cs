using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;

namespace TypeInVoice.Windows;

public partial class MainWindow : Window
{
    private const int RecordHotKeyId = 1;
    private const int SettingsHotKeyId = 2;
    private const int WmHotKey = 0x0312;
    private const uint ModAlt = 0x0001;
    private const uint ModControl = 0x0002;
    private const uint ModNoRepeat = 0x4000;
    private const uint VirtualKeyD = 0x44;
    private const uint VirtualKeyS = 0x53;

    private readonly DictationController _controller;
    private readonly IntPtr _windowHandle;
    private bool _allowClose;

    internal MainWindow(DictationController controller)
    {
        InitializeComponent();
        _controller = controller;
        ApiKeyBox.Password = SecretStore.LoadApiKey() ?? string.Empty;
        SelectLanguage(PreferenceStore.LoadLanguage());

        _windowHandle = new WindowInteropHelper(this).EnsureHandle();
        HwndSource.FromHwnd(_windowHandle)?.AddHook(WindowMessageHook);

        var modifiers = ModControl | ModAlt | ModNoRepeat;
        var recordRegistered = NativeMethods.RegisterHotKey(_windowHandle, RecordHotKeyId, modifiers, VirtualKeyD);
        var settingsRegistered = NativeMethods.RegisterHotKey(_windowHandle, SettingsHotKeyId, modifiers, VirtualKeyS);
        if (!recordRegistered || !settingsRegistered)
        {
            UpdateStatus("A keyboard shortcut is already used by another app. You can still use the tray menu.");
        }

        Closing += HandleClosing;
    }

    public void ShowAndActivate()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
        Topmost = true;
        Topmost = false;
        Focus();
    }

    public void UpdateStatus(string message)
    {
        StatusText.Text = message;
    }

    internal void UpdateStatus(DictationStatus status)
    {
        StatusText.Text = status.Message;
        ToggleButton.Content = status.State switch
        {
            DictationState.Idle => "Start dictation",
            DictationState.Recording => "Stop and transcribe",
            _ => "Cancel"
        };
    }

    public void CloseForExit()
    {
        _allowClose = true;
        NativeMethods.UnregisterHotKey(_windowHandle, RecordHotKeyId);
        NativeMethods.UnregisterHotKey(_windowHandle, SettingsHotKeyId);
        Close();
    }

    private IntPtr WindowMessageHook(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message != WmHotKey)
        {
            return IntPtr.Zero;
        }

        handled = true;
        switch (wParam.ToInt32())
        {
            case RecordHotKeyId:
                _ = _controller.ToggleAsync();
                break;
            case SettingsHotKeyId:
                ShowAndActivate();
                break;
        }

        return IntPtr.Zero;
    }

    private void SaveButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SecretStore.SaveApiKey(ApiKeyBox.Password);
            var language = (LanguageBox.SelectedItem as ComboBoxItem)?.Tag?.ToString() ?? "auto";
            PreferenceStore.SaveLanguage(language);
            _controller.LanguageCode = language;
            UpdateStatus(string.IsNullOrWhiteSpace(ApiKeyBox.Password)
                ? "API key removed."
                : "Settings saved securely.");
        }
        catch (Exception error)
        {
            UpdateStatus($"Could not save settings: {error.Message}");
        }
    }

    private async void ToggleButton_Click(object sender, RoutedEventArgs e)
    {
        await _controller.ToggleAsync();
    }

    private void SelectLanguage(string language)
    {
        foreach (var item in LanguageBox.Items.OfType<ComboBoxItem>())
        {
            if (string.Equals(item.Tag?.ToString(), language, StringComparison.OrdinalIgnoreCase))
            {
                LanguageBox.SelectedItem = item;
                _controller.LanguageCode = language;
                return;
            }
        }

        LanguageBox.SelectedIndex = 0;
        _controller.LanguageCode = "auto";
    }

    private void HandleClosing(object? sender, CancelEventArgs e)
    {
        if (_allowClose)
        {
            return;
        }

        e.Cancel = true;
        Hide();
    }
}
