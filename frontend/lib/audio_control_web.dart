import 'audio_control.dart';
import 'dart:js_interop';
import 'dart:async';
import 'dart:typed_data';
import 'dart:js_util' as js_util;
import 'dart:js' as js;
import 'package:web/web.dart' as web;
import 'dart:convert';
import 'package:flutter/foundation.dart';
// import 'package:provider/provider.dart';

typedef OnAudioDataReady = void Function(String audioJson);
typedef OnRecordingStateChanged = void Function(bool isRecording);

class AudioControlWeb extends AudioControl {
  // List<String> _speakerLanguage = ['ko', 'en'];

  web.MediaStream? _stream;
  Timer? _audioAnalyzerTimer;
  // Audio analysis
  web.AudioContext? _audioContext;
  web.AnalyserNode? _analyserNode;
  web.MediaStreamAudioSourceNode? _audioSource;
  web.ScriptProcessorNode? _scriptProcessor;

  final List<Float32List> _audioBuffers = []; //buffer
  bool _isRecording = false;
  double _audioLevel = 0.0; // 0.0 ~ 1.0
  bool recorderSet = false;

  //For auto termination
  late Duration _silenceDuration;
  final double _silenceThreshold = 0.1; // 임계값 (0.0~1.0), 필요시 조정
  final Duration _silenceDurationLimit = const Duration(seconds: 2);

  OnAudioDataReady? _onAudioDataReady;
  OnRecordingStateChanged? _onRecordingStateChanged;

  AudioControlImpl({onAudioDataReady, onRecordingStateChanged}) {
    _onAudioDataReady = onAudioDataReady;
    _onRecordingStateChanged = onRecordingStateChanged;
  }

  @override
  Future<bool> requestPermission() async {
    final constraints = web.MediaStreamConstraints(audio: true.toJS);
    final jsPromise = web.window.navigator.mediaDevices!.getUserMedia(
      constraints,
    );
    _stream = await js_util.promiseToFuture(jsPromise);
    debugPrint('🎙️ Microphone access granted');
    return true;
  }

  @override
  Future<void> startRecording() async {
    if (_isRecording) return;
    _isRecording = true;
    debugPrint('▶️ Started Recording');
    _startAudioAnalysis();
  }

  Future<void> _startAudioAnalysis() async {
    _audioBuffers.clear();
    _audioLevel = 0.0;
    _silenceDuration = Duration.zero;

    // 2. AudioContext + MediaStreamSource
    _audioContext = web.AudioContext();
    _audioSource = _audioContext!.createMediaStreamSource(_stream!);

    // 3. ScriptProcessorNode (녹음)
    _scriptProcessor = _audioContext!.createScriptProcessor(4096, 1, 1);
    js_util.setProperty(
      _scriptProcessor!,
      'onaudioprocess',
      js.allowInterop((event) {
        try {
          final inputBuffer = js_util.getProperty(event, 'inputBuffer');
          final channelData = js_util.callMethod(
            inputBuffer,
            'getChannelData',
            [0],
          );
          final length = js_util.getProperty(channelData, 'length') as int;
          final samples = Float32List(length);
          for (var i = 0; i < length; i++) {
            samples[i] = js_util.getProperty(channelData, i) as double;
          }
          _audioBuffers.add(samples);
        } catch (e) {
          debugPrint('❌ audio process error: $e');
        }
      }),
    );

    _analyserNode = _audioContext!.createAnalyser();
    _analyserNode!.fftSize = 256; // 예시 값, 분석 해상도
    _audioSource!.connect(_analyserNode!);

    _audioSource!.connect(_scriptProcessor!);
    _scriptProcessor!.connect(_audioContext!.destination);

    _audioAnalyzerTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _analyzeAudioLevel(),
    );
  }

  void _analyzeAudioLevel() {
    if (_analyserNode == null) return;

    final dataArray = Uint8List(_analyserNode!.frequencyBinCount);
    final jsArray = js_util.jsify(dataArray);
    _analyserNode!.getByteFrequencyData(jsArray);

    // Calculate average vocaplume
    double sum = 0;
    for (var i = 0; i < dataArray.length; i++) {
      sum += dataArray[i];
    }
    final average = sum / dataArray.length;

    // Normalize to 0.0 - 1.0 and apply smoothing
    final normalizedLevel = (average / 255.0).clamp(0.0, 1.0);

    // Smooth the audio level changes
    _audioLevel = (_audioLevel * 0.7) + (normalizedLevel * 0.3);
    notifyListeners();

    if (_audioLevel < _silenceThreshold) {
      _silenceDuration += const Duration(milliseconds: 50);

      if (_silenceDuration >= _silenceDurationLimit) {
        debugPrint('🔇 Silence detected for 3 seconds. Auto-stopping...');
        _stopTransmitting();
      }
    } else {
      // 다시 음성 감지되면 리셋
      _silenceDuration = Duration.zero;
    }
  }

  Future<void> _stopTransmitting() async {
    final wav = await stopRecording();
    final finalformWav = base64Encode(wav);
    debugPrint('Base64 length: ${finalformWav.length}');
    _isRecording = false;
    notifyListeners();
    //_onRecordingStateChanged?.call(false);
    callOnRecordingStateChanged(false);

    final audioJson = jsonEncode({
      'command': 'transcribe', // 서버와 약속된 오디오 처리 명령어
      'audio': finalformWav,
      "target_lang1": getSpeaker1,
      "target_lang2": getSpeaker2,
    });

    // _onAudioDataReady?.call(audioJson);
    callOnAudioDataReady(audioJson);
    notifyListeners();
    debugPrint("Audio data encoded");
  }

  @override
  Future<Uint8List> stopRecording() async {
    _scriptProcessor?.disconnect();
    _analyserNode?.disconnect();
    _audioSource?.disconnect();

    // Stop all tracks in the MediaStream (getTracks() returns a JSArray)
    if (_stream != null) {
      final tracks = js_util.callMethod(_stream!, 'getTracks', []);
      final length = js_util.getProperty(tracks, 'length') as int;
      for (var i = 0; i < length; i++) {
        final track = js_util.getProperty(tracks, i);
        if (track != null) {
          js_util.callMethod(track, 'stop', []);
        }
      }
    }

    _audioAnalyzerTimer?.cancel();
    _audioAnalyzerTimer = null;
    _audioLevel = 0.0;
    _isRecording = false;
    debugPrint('⏹️ Stopped audio analysis');
    return wavFromBuffers(_audioBuffers);
  }

  @override
  void dispose() {
    _audioAnalyzerTimer?.cancel();
    // _channel?.sink.close();
    _audioSource?.disconnect();
    _audioContext?.close();

    if (_stream != null) {
      for (int i = 0; i < _stream!.getTracks().length; i++) {
        _stream!.getTracks()[i].stop();
      }
    }
    // super.dispose();
  }
}
