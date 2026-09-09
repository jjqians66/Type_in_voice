using NAudio.Wave;
using System.IO;

namespace TypeInVoice.Windows;

internal sealed class AudioRecorderService : IDisposable
{
    private readonly object _gate = new();
    private WaveInEvent? _recorder;
    private MemoryStream? _stream;
    private WaveFileWriter? _writer;
    private TaskCompletionSource<byte[]>? _stopCompletion;

    internal void Start()
    {
        lock (_gate)
        {
            if (_recorder is not null)
            {
                throw new InvalidOperationException("A recording is already in progress.");
            }

            _stream = new MemoryStream();
            _recorder = new WaveInEvent
            {
                WaveFormat = new WaveFormat(24_000, 16, 1),
                BufferMilliseconds = 100
            };
            _writer = new WaveFileWriter(_stream, _recorder.WaveFormat);
            _recorder.DataAvailable += HandleDataAvailable;
            _recorder.RecordingStopped += HandleRecordingStopped;

            try
            {
                _recorder.StartRecording();
            }
            catch
            {
                CleanUpRecording();
                throw;
            }
        }
    }

    internal Task<byte[]> StopAsync()
    {
        lock (_gate)
        {
            if (_recorder is null)
            {
                return Task.FromResult(Array.Empty<byte>());
            }

            if (_stopCompletion is not null)
            {
                return _stopCompletion.Task;
            }

            _stopCompletion = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);
            _recorder.StopRecording();
            return _stopCompletion.Task;
        }
    }

    private void HandleDataAvailable(object? sender, WaveInEventArgs e)
    {
        lock (_gate)
        {
            _writer?.Write(e.Buffer, 0, e.BytesRecorded);
        }
    }

    private void HandleRecordingStopped(object? sender, StoppedEventArgs e)
    {
        lock (_gate)
        {
            var completion = _stopCompletion;
            byte[] audio = Array.Empty<byte>();

            try
            {
                _writer?.Flush();
                _writer?.Dispose();
                _writer = null;
                audio = _stream?.ToArray() ?? Array.Empty<byte>();

                if (e.Exception is not null)
                {
                    completion?.TrySetException(e.Exception);
                }
                else
                {
                    completion?.TrySetResult(audio);
                }
            }
            finally
            {
                CleanUpRecording();
            }
        }
    }

    private void CleanUpRecording()
    {
        if (_recorder is not null)
        {
            _recorder.DataAvailable -= HandleDataAvailable;
            _recorder.RecordingStopped -= HandleRecordingStopped;
            _recorder.Dispose();
        }

        _writer?.Dispose();
        _stream?.Dispose();
        _recorder = null;
        _writer = null;
        _stream = null;
        _stopCompletion = null;
    }

    public void Dispose()
    {
        lock (_gate)
        {
            _stopCompletion?.TrySetCanceled();
            CleanUpRecording();
        }
    }
}
