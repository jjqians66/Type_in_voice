using System.Drawing;
using System.Windows;
using Forms = System.Windows.Forms;

namespace TypeInVoice.Windows;

public partial class App : System.Windows.Application
{
    private Mutex? _singleInstance;
    private bool _ownsSingleInstance;
    private DictationController? _controller;
    private MainWindow? _settingsWindow;
    private StatusOverlayWindow? _overlay;
    private Forms.NotifyIcon? _trayIcon;
    private Forms.ToolStripMenuItem? _toggleMenuItem;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _singleInstance = new Mutex(true, @"Local\TypeInVoice.SingleInstance", out var isFirstInstance);
        _ownsSingleInstance = isFirstInstance;
        if (!isFirstInstance)
        {
            System.Windows.MessageBox.Show(
                "Type in Voice is already running in the system tray.",
                "Type in Voice",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            Shutdown();
            return;
        }

        _controller = new DictationController();
        _settingsWindow = new MainWindow(_controller);
        _overlay = new StatusOverlayWindow();
        _controller.StatusChanged += HandleStatusChanged;
        _controller.SettingsRequested += ShowSettings;

        _trayIcon = new Forms.NotifyIcon
        {
            Icon = SystemIcons.Information,
            Text = "Type in Voice — Ready",
            Visible = true,
            ContextMenuStrip = BuildTrayMenu()
        };
        _trayIcon.DoubleClick += (_, _) => ShowSettings();

        if (string.IsNullOrWhiteSpace(SecretStore.LoadApiKey()))
        {
            ShowSettings();
        }
    }

    private Forms.ContextMenuStrip BuildTrayMenu()
    {
        var menu = new Forms.ContextMenuStrip();
        _toggleMenuItem = new Forms.ToolStripMenuItem("Start dictation", null, async (_, _) =>
        {
            if (_controller is not null)
            {
                await _controller.ToggleAsync();
            }
        });
        menu.Items.Add(_toggleMenuItem);
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Settings…", null, (_, _) => ShowSettings());
        menu.Items.Add("Exit Type in Voice", null, (_, _) => Shutdown());
        return menu;
    }

    private void HandleStatusChanged(object? sender, DictationStatus status)
    {
        Dispatcher.Invoke(() =>
        {
            if (_trayIcon is not null)
            {
                _trayIcon.Text = Shorten($"Type in Voice — {status.Message}", 63);
                if (status.State == DictationState.Idle &&
                    status.Message is not "Done — transcription inserted." and not "Cancelled.")
                {
                    _trayIcon.BalloonTipTitle = "Type in Voice";
                    _trayIcon.BalloonTipText = status.Message;
                    _trayIcon.ShowBalloonTip(4_000);
                }
            }

            if (_toggleMenuItem is not null)
            {
                _toggleMenuItem.Text = status.State switch
                {
                    DictationState.Idle => "Start dictation",
                    DictationState.Recording => "Stop and transcribe",
                    _ => "Cancel"
                };
            }

            if (_overlay is not null)
            {
                if (status.State == DictationState.Idle)
                {
                    _overlay.Hide();
                }
                else
                {
                    _overlay.ShowStatus(status);
                }
            }

            _settingsWindow?.UpdateStatus(status);
        });
    }

    private void ShowSettings()
    {
        Dispatcher.Invoke(() => _settingsWindow?.ShowAndActivate());
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _controller?.Dispose();
        _trayIcon?.Dispose();
        _overlay?.CloseForExit();
        _settingsWindow?.CloseForExit();
        if (_ownsSingleInstance)
        {
            _singleInstance?.ReleaseMutex();
        }
        _singleInstance?.Dispose();
        base.OnExit(e);
    }

    private static string Shorten(string value, int maxLength) =>
        value.Length <= maxLength ? value : value[..(maxLength - 1)] + "…";
}
