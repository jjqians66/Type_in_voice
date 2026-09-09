using System.Runtime.InteropServices;
using System.Windows;

namespace TypeInVoice.Windows;

internal enum DictationState
{
    Idle,
    Recording,
    Processing
}

internal sealed record DictationStatus(DictationState State, string Message);

internal sealed class DictationController : IDisposable
{
    private static readonly TimeSpan RecordingLimit = TimeSpan.FromMinutes(5);

    private readonly AudioRecorderService _recorder = new();
    private readonly TranscriptionService _transcription = new();
    private CancellationTokenSource? _recordingLimitCancellation;
    private CancellationTokenSource? _requestCancellation;
    private IntPtr _targetWindow;
    private int _operationVersion;
    private bool _disposed;

    internal event EventHandler<DictationStatus>? StatusChanged;
    internal event Action? SettingsRequested;

    internal DictationState State { get; private set; } = DictationState.Idle;
    internal string LanguageCode { get; set; } = PreferenceStore.LoadLanguage();

    internal Task ToggleAsync()
    {
        if (_disposed)
        {
            return Task.CompletedTask;
        }

        return State switch
        {
            DictationState.Idle => StartAsync(),
            DictationState.Recording => StopAndTranscribeAsync(),
            _ => CancelAsync()
        };
    }

    private Task StartAsync()
    {
        if (string.IsNullOrWhiteSpace(SecretStore.LoadApiKey()))
        {
            Notify(DictationState.Idle, "Add your OpenAI API key before dictating.");
            SettingsRequested?.Invoke();
            return Task.CompletedTask;
        }

        _targetWindow = NativeMethods.GetForegroundWindow();
        if (!NativeMethods.IsSafeTarget(_targetWindow))
        {
            _targetWindow = IntPtr.Zero;
        }

        try
        {
            _recorder.Start();
            _operationVersion++;
            Notify(DictationState.Recording, "Recording — press Ctrl + Alt + D to stop");
            _recordingLimitCancellation = new CancellationTokenSource();
            _ = EnforceRecordingLimitAsync(_operationVersion, _recordingLimitCancellation.Token);
        }
        catch (Exception error)
        {
            Notify(DictationState.Idle, $"Microphone unavailable: {error.Message}");
        }

        return Task.CompletedTask;
    }

    private async Task StopAndTranscribeAsync()
    {
        if (State != DictationState.Recording)
        {
            return;
        }

        _recordingLimitCancellation?.Cancel();
        _recordingLimitCancellation?.Dispose();
        _recordingLimitCancellation = null;
        var operation = ++_operationVersion;
        Notify(DictationState.Processing, "Transcribing… press Ctrl + Alt + D to cancel");
        CancellationTokenSource? requestCancellation = null;

        try
        {
            var wavAudio = await _recorder.StopAsync();
            if (operation != _operationVersion)
            {
                return;
            }

            if (wavAudio.Length < 48)
            {
                throw new InvalidOperationException("The recording was empty.");
            }

            var apiKey = SecretStore.LoadApiKey();
            if (string.IsNullOrWhiteSpace(apiKey))
            {
                throw new InvalidOperationException("Add your OpenAI API key in Settings.");
            }

            requestCancellation = new CancellationTokenSource();
            _requestCancellation = requestCancellation;
            var text = await _transcription.TranscribeAsync(
                wavAudio,
                apiKey,
                LanguageCode,
                requestCancellation.Token);

            if (operation != _operationVersion)
            {
                return;
            }

            if (!TrySetClipboard(text))
            {
                throw new InvalidOperationException("Windows could not update the clipboard. Please try again.");
            }

            await Task.Delay(120);
            var pasted = NativeMethods.PasteInto(_targetWindow);
            Notify(DictationState.Idle, pasted
                ? "Done — transcription inserted."
                : "Transcription copied. Press Ctrl + V to paste.");
        }
        catch (OperationCanceledException)
        {
            if (operation == _operationVersion)
            {
                Notify(DictationState.Idle, "Cancelled.");
            }
        }
        catch (Exception error)
        {
            if (operation == _operationVersion)
            {
                Notify(DictationState.Idle, error.Message);
            }
        }
        finally
        {
            requestCancellation?.Dispose();
            if (ReferenceEquals(_requestCancellation, requestCancellation))
            {
                _requestCancellation = null;
            }
        }
    }

    private async Task CancelAsync()
    {
        var previousState = State;
        _operationVersion++;
        _recordingLimitCancellation?.Cancel();
        _recordingLimitCancellation?.Dispose();
        _recordingLimitCancellation = null;
        _requestCancellation?.Cancel();

        if (previousState == DictationState.Recording)
        {
            try
            {
                await _recorder.StopAsync();
            }
            catch
            {
                // Cancellation intentionally discards the recording.
            }
        }

        Notify(DictationState.Idle, "Cancelled.");
    }

    private async Task EnforceRecordingLimitAsync(int operation, CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(RecordingLimit, cancellationToken);
            if (operation != _operationVersion || State != DictationState.Recording)
            {
                return;
            }

            var stopTask = await System.Windows.Application.Current.Dispatcher.InvokeAsync(StopAndTranscribeAsync);
            await stopTask;
        }
        catch (OperationCanceledException)
        {
            // The user stopped before the safety limit.
        }
    }

    private void Notify(DictationState state, string message)
    {
        State = state;
        StatusChanged?.Invoke(this, new DictationStatus(state, message));
    }

    private static bool TrySetClipboard(string text)
    {
        for (var attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                System.Windows.Clipboard.SetText(text);
                return true;
            }
            catch (COMException)
            {
                Thread.Sleep(50);
            }
        }
        return false;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _operationVersion++;
        _recordingLimitCancellation?.Cancel();
        _recordingLimitCancellation?.Dispose();
        _requestCancellation?.Cancel();
        _requestCancellation?.Dispose();
        _recorder.Dispose();
    }
}
