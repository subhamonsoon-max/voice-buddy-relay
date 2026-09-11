import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class AudioStreamService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.voicebuddy.audio/pcm_control');
  static const EventChannel _recordEventChannel =
      EventChannel('com.voicebuddy.audio/pcm_record_stream');

  StreamSubscription? _recordSubscription;
  final StreamController<Uint8List> _recordedAudioController =
      StreamController<Uint8List>.broadcast();
  final StreamController<double> _playbackAmplitudeController =
      StreamController<double>.broadcast();

  Stream<Uint8List> get onAudioRecorded => _recordedAudioController.stream;
  Stream<double> get onPlaybackAmplitude => _playbackAmplitudeController.stream;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  /// Initializes audio platform channels
  Future<void> init() async {
    try {
      await _methodChannel.invokeMethod('initAudio');
    } catch (e) {
      // Platform channel may not be available on desktop/web preview
      // Fallback is handled gracefully
    }
  }

  /// Start recording microphone PCM audio (16kHz, 16-bit Mono)
  Future<void> startRecording() async {
    if (_isRecording) return;
    _isRecording = true;

    try {
      await _methodChannel.invokeMethod('startRecording');
      _recordSubscription =
          _recordEventChannel.receiveBroadcastStream().listen((dynamic data) {
        if (data is Uint8List) {
          _recordedAudioController.add(data);
        }
      }, onError: (dynamic error) {
        _isRecording = false;
      });
    } catch (e) {
      // Fallback or preview mode
    }
  }

  /// Stop recording microphone audio
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _isRecording = false;

    try {
      await _recordSubscription?.cancel();
      _recordSubscription = null;
      await _methodChannel.invokeMethod('stopRecording');
    } catch (e) {
      // Fallback
    }
  }

  /// Play incoming PCM audio buffer from Gemini Live (24kHz, 16-bit Mono)
  Future<void> playAudioChunk(Uint8List pcmChunk) async {
    // Calculate RMS amplitude for mouth animation
    final double amplitude = _calculateRms(pcmChunk);
    _playbackAmplitudeController.add(amplitude);

    try {
      await _methodChannel.invokeMethod('playChunk', {'data': pcmChunk});
    } catch (e) {
      // Fallback
    }
  }

  /// Stop/interrupt audio playback immediately
  Future<void> stopPlayback() async {
    _playbackAmplitudeController.add(0.0);
    try {
      await _methodChannel.invokeMethod('stopPlayback');
    } catch (e) {
      // Fallback
    }
  }

  /// Calculate Normalized Root Mean Square (RMS) amplitude from 16-bit PCM bytes
  double _calculateRms(Uint8List pcmBytes) {
    if (pcmBytes.isEmpty) return 0.0;
    int sumSquares = 0;
    final int sampleCount = pcmBytes.length ~/ 2;
    if (sampleCount == 0) return 0.0;

    final ByteData byteData = ByteData.sublistView(pcmBytes);
    for (int i = 0; i < sampleCount; i++) {
      final int sample = byteData.getInt16(i * 2, Endian.little);
      sumSquares += sample * sample;
    }

    final double meanSquare = sumSquares / sampleCount;
    final double rms = sqrt(meanSquare);
    // Normalize 16-bit PCM (max 32768) to 0.0 - 1.0 range with sensitivity boost
    final double normalized = (rms / 32768.0) * 3.5;
    return normalized.clamp(0.0, 1.0);
  }

  void dispose() {
    stopRecording();
    stopPlayback();
    _recordedAudioController.close();
    _playbackAmplitudeController.close();
  }
}
