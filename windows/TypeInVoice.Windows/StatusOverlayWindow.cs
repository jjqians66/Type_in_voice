using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace TypeInVoice.Windows;

public sealed class StatusOverlayWindow : Window
{
    private readonly TextBlock _label;
    private bool _allowClose;

    public StatusOverlayWindow()
    {
        Width = 360;
        Height = 64;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true;
        Background = System.Windows.Media.Brushes.Transparent;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;

        _label = new TextBlock
        {
            FontFamily = new System.Windows.Media.FontFamily("Segoe UI"),
            FontSize = 14,
            FontWeight = FontWeights.SemiBold,
            Foreground = System.Windows.Media.Brushes.White,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Center
        };

        Content = new Border
        {
            Background = new SolidColorBrush(System.Windows.Media.Color.FromArgb(236, 25, 31, 45)),
            BorderBrush = new SolidColorBrush(System.Windows.Media.Color.FromArgb(80, 255, 255, 255)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(18),
            Padding = new Thickness(20, 12, 20, 12),
            Child = _label
        };

        Closing += (_, e) =>
        {
            if (!_allowClose)
            {
                e.Cancel = true;
                Hide();
            }
        };
    }

    internal void ShowStatus(DictationStatus status)
    {
        _label.Text = status.State switch
        {
            DictationState.Recording => "●  Recording — Ctrl + Alt + D to stop",
            DictationState.Processing => "Transcribing… Ctrl + Alt + D to cancel",
            _ => status.Message
        };

        var workArea = SystemParameters.WorkArea;
        Left = workArea.Left + (workArea.Width - Width) / 2;
        Top = workArea.Bottom - Height - 28;
        if (!IsVisible)
        {
            Show();
        }
    }

    public void CloseForExit()
    {
        _allowClose = true;
        Close();
    }
}
