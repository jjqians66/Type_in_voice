import Foundation
import AVFoundation
import Accelerate
import Combine

/// Records audio from the microphone using AVAudioEngine,
/// producing 24kHz mono PCM16 data suitable for Whisper transcription.
class AudioRecorder: ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var recordedData = Data()

    /// Guards `_isRecording` and `recordedData`. Both are touched from the
    /// audio tap thread and from the main thread.
    private let stateLock = NSLock()
    private var _isRecording = false

    private var isRecording: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _isRecording }
        set { stateLock.lock(); defer { stateLock.unlock() }; _isRecording = newValue }
    }

    @Published var currentLevel: Float = 0.0
    @Published var frequencyBands: [Float] = Array(repeating: 0, count: 7)

    /// Called for each audio chunk during recording (PCM16 Data).
    var onAudioChunk: ((Data) -> Void)?

    // MARK: - FFT State
    //
    // Allocated once and reused for every buffer. Creating the FFT setup or any
    // of these arrays inside the tap would allocate on the audio thread, which
    // is the usual cause of dropouts.

    private static let fftSize = 512
    private static let bandCount = 7

    private let fftSetup: FFTSetup?
    private let log2n: vDSP_Length
    private var hannWindow: [Float]
    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]

    init() {
        let size = AudioRecorder.fftSize
        log2n = vDSP_Length(log2(Float(size)))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
        hannWindow = [Float](repeating: 0, count: size)
        windowed = [Float](repeating: 0, count: size)
        realp = [Float](repeating: 0, count: size / 2)
        imagp = [Float](repeating: 0, count: size / 2)
        magnitudes = [Float](repeating: 0, count: size / 2)
        vDSP_hann_window(&hannWindow, vDSP_Length(size), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    // MARK: - Recording

    /// Start recording from the default microphone.
    /// Audio is accumulated as PCM16 24kHz mono and can also be streamed via `onAudioChunk`.
    func startRecording() throws {
        print("Type in Voice AudioRecorder: startRecording()")
        
        // Clean up any previous engine
        if let oldEngine = audioEngine {
            oldEngine.inputNode.removeTap(onBus: 0)
            oldEngine.stop()
            audioEngine = nil
        }
        
        stateLock.lock()
        recordedData.removeAll()
        stateLock.unlock()
        
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        print("Type in Voice AudioRecorder: input format: \(inputFormat)")
        
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            print("Type in Voice AudioRecorder: invalid input format - no microphone available?")
            throw RecorderError.formatError
        }

        // Target: 24kHz, mono, Int16 (what Whisper API expects)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24000,
            channels: 1,
            interleaved: true
        ) else {
            throw RecorderError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            print("Type in Voice AudioRecorder: failed to create converter from \(inputFormat) to \(targetFormat)")
            throw RecorderError.converterError
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, self.isRecording else { return }

            // Update audio level for UI
            self.updateLevel(buffer: buffer)
            self.updateFrequencyBands(buffer: buffer)

            // Convert to 24kHz PCM16. Leave headroom: the resampler can emit
            // slightly more than the nominal ratio when it flushes filter state.
            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024

            guard let converted = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: capacity
            ) else { return }

            // The converter may ask for input more than once to fill one output
            // buffer. Hand it this buffer exactly once; returning it again would
            // feed the same samples in twice and duplicate audio.
            var inputConsumed = false
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else {
                print("Type in Voice AudioRecorder: conversion error: \(error?.localizedDescription ?? "unknown")")
                return
            }

            // Extract Int16 bytes
            if let int16Data = converted.int16ChannelData {
                let byteCount = Int(converted.frameLength) * MemoryLayout<Int16>.size
                let data = Data(bytes: int16Data[0], count: byteCount)
                self.stateLock.lock()
                self.recordedData.append(data)
                self.stateLock.unlock()
                self.onAudioChunk?(data)
            }
        }

        engine.prepare()
        isRecording = true
        do {
            try engine.start()
        } catch {
            isRecording = false
            inputNode.removeTap(onBus: 0)
            throw error
        }
        self.audioEngine = engine
        print("Type in Voice AudioRecorder: engine started successfully")
    }

    /// Stop recording.
    func stopRecording() {
        print("Type in Voice AudioRecorder: stopRecording()")
        guard isRecording, let engine = audioEngine else {
            print("Type in Voice AudioRecorder: not recording or no engine")
            return
        }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.audioEngine = nil

        DispatchQueue.main.async {
            self.currentLevel = 0.0
            self.frequencyBands = Array(repeating: 0, count: AudioRecorder.bandCount)
        }
        
        stateLock.lock()
        let dataSize = recordedData.count
        stateLock.unlock()
        print("Type in Voice AudioRecorder: stopped; recorded \(dataSize) bytes")
    }
    
    /// Get the accumulated PCM16 audio data
    func getAudioData() throws -> Data {
        stateLock.lock()
        let data = recordedData
        stateLock.unlock()
        guard !data.isEmpty else { throw RecorderError.notRecording }
        return data
    }

    // MARK: - Audio Level (RMS)

    private func updateLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        var rms: Float = 0
        vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(frames))
        let db = 20 * log10(max(rms, 0.000001))
        let normalized = max(0, min(1, (db + 60) / 60))

        DispatchQueue.main.async {
            self.currentLevel = normalized
        }
    }

    // MARK: - Frequency Bands (FFT for waveform visualization)

    private func updateFrequencyBands(buffer: AVAudioPCMBuffer) {
        guard let fftSetup, let channelData = buffer.floatChannelData else { return }
        let fftSize = AudioRecorder.fftSize
        guard Int(buffer.frameLength) >= fftSize else { return }

        // Apply the pre-computed Hann window
        vDSP_vmul(channelData[0], 1, hannWindow, 1, &windowed, 1, vDSP_Length(fftSize))

        realp.withUnsafeMutableBufferPointer { realBuffer in
            imagp.withUnsafeMutableBufferPointer { imagBuffer in
                magnitudes.withUnsafeMutableBufferPointer { magnitudeBuffer in
                    guard let realBase = realBuffer.baseAddress,
                          let imagBase = imagBuffer.baseAddress,
                          let magnitudeBase = magnitudeBuffer.baseAddress else { return }

                    var splitComplex = DSPSplitComplex(realp: realBase, imagp: imagBase)

                    // Pack into split complex
                    windowed.withUnsafeBufferPointer { ptr in
                        ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                        }
                    }

                    // Forward FFT and calculate magnitudes
                    vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                    vDSP_zvmags(&splitComplex, 1, magnitudeBase, 1, vDSP_Length(fftSize / 2))
                }
            }
        }

        // Group into 7 frequency bands
        let bandCount = AudioRecorder.bandCount
        let binsPerBand = (fftSize / 2) / bandCount
        var bands = [Float](repeating: 0, count: bandCount)

        for band in 0..<bandCount {
            let start = band * binsPerBand
            let end = min(start + binsPerBand, fftSize / 2)
            var sum: Float = 0
            for i in start..<end {
                sum += magnitudes[i]
            }
            let avg = sum / Float(end - start)
            let db = 10 * log10(max(avg, 0.000001))
            bands[band] = max(0, min(1, (db + 40) / 40))
        }

        DispatchQueue.main.async {
            self.frequencyBands = bands
        }
    }
}

// MARK: - Errors

enum RecorderError: LocalizedError {
    case formatError
    case converterError
    case notRecording

    var errorDescription: String? {
        switch self {
        case .formatError: return "Could not create audio format"
        case .converterError: return "Could not create audio converter"
        case .notRecording: return "Not currently recording"
        }
    }
}
