import 'audio_control.dart';
import 'dart:async';
// import 'package:web/web.dart' as web;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'dart:io';

class AudioImpl extends AudioControl {
  // List<String> _speakerLanguage = ['ko', 'en'];

  // web.MediaStream? _stream;
  Timer? _audioAnalyzerTimer;
  // Audio analysis
  // web.AudioContext? _audioContext;
  // web.AnalyserNode? _analyserNode;
  // web.MediaStreamAudioSourceNode? _audioSource;
  // web.ScriptProcessorNode? _scriptProcessor;

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

  //opus conversion
  final AudioRecorder _recorder = AudioRecorder();

  // record가 실제로 만든 포맷을 “우리가 선언”해서 서버에 보냄
  // 웹은 보통 webm/opus, 모바일은 m4a가 흔함
  String _audioFormat = kIsWeb ? 'audio/webm;codecs=opus' : 'audio/mp4';

  @override
  double get audioLevel => _audioLevel;

  @override
  Future<bool> requestPermission() async {
    final permission = await _recorder.hasPermission();
    if (permission) debugPrint('🎙️ Microphone access granted');
    return permission;
  }

  @override
  Future<void> startRecording() async {
    if (_isRecording) return;

    final permission = await _recorder.hasPermission();
    if (!permission) {
      throw Exception('No microphone permission');
    }

    final ext = kIsWeb ? 'webm' : 'm4a';
    _audioFormat = kIsWeb ? 'audio/webm;codecs=opus' : 'audio/mp4';
    final path = await _makeTempPath(extension: ext);

    _isRecording = true;

    await _recorder.start(
      RecordConfig(
        encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 48000,
      ),
      path: path,
    );

    debugPrint('▶️ Started Recording');

    // _startAudioAnalysis();
  }

  // Future<void> _startAudioAnalysis() async {
  // _audioLevel = 0.0;
  // _silenceDuration = Duration.zero;
  //
  // _audioContext = web.AudioContext();
  // _audioSource = _audioContext!.createMediaStreamSource(_stream!);
  //
  // _analyserNode = _audioContext!.createAnalyser();
  // _analyserNode!.fftSize = 256; // 예시 값, 분석 해상도
  //
  // _audioSource!.connect(_analyserNode!);
  //
  // _audioSource!.connect(_scriptProcessor!);
  // _scriptProcessor!.connect(_audioContext!.destination);
  //
  // _audioAnalyzerTimer = Timer.periodic(
  // const Duration(milliseconds: 50),
  // (_) => _analyzeAudioLevel(),
  // );
  // }

  // void _analyzeAudioLevel() {
  //   if (_analyserNode == null) return;

  //   final dataArray = Uint8List(_analyserNode!.frequencyBinCount);
  //   // final jsArray = js_util.jsify(dataArray);
  //   // _analyserNode!.getByteFrequencyData(jsArray);

  //   // Calculate average vocaplume
  //   double sum = 0;
  //   for (var i = 0; i < dataArray.length; i++) {
  //     sum += dataArray[i];
  //   }
  //   final average = sum / dataArray.length;

  //   // Normalize to 0.0 - 1.0 and apply smoothing
  //   final normalizedLevel = (average / 255.0).clamp(0.0, 1.0);

  //   // Smooth the audio level changes
  //   _audioLevel = (_audioLevel * 0.7) + (normalizedLevel * 0.3);
  //   notifyListeners();

  //   if (_audioLevel < _silenceThreshold) {
  //     _silenceDuration += const Duration(milliseconds: 50);

  //     if (_silenceDuration >= _silenceDurationLimit) {
  //       debugPrint('🔇 Silence detected for 3 seconds. Auto-stopping...');
  //       _stopTransmitting();
  //     }
  //   } else {
  //     // 다시 음성 감지되면 리셋
  //     _silenceDuration = Duration.zero;
  //   }
  // }

  Future<void> stopAndTransmit({
    required String speaker1,
    required String speaker2,
    required void Function(String json) sendJson,
  }) async {
    if (!_isRecording) return;

    final path = await _recorder.stop();
    _isRecording = false;
    _audioLevel = 0.0;
    notifyListeners();

    if (path == null) {
      throw Exception('Recording stop returned null path');
    }

    final bytes = await File(path).readAsBytes();
    final b64 = base64Encode(bytes);

    final payload = jsonEncode({
      'command': 'transcribe',
      'audio_format': _audioFormat, // 서버에서 suffix/ffmpeg 처리용
      'audio': b64,
      'target_lang1': speaker1,
      'target_lang2': speaker2,
    });

    sendJson(payload);
  }

  Future<void> _stopTransmitting() async {
    final bytes = await stopRecording();
    final b64 = base64Encode(bytes);

    debugPrint('Base64 length: ${b64.length}');

    _isRecording = false;

    notifyListeners();
    //_onRecordingStateChanged?.call(false);
    callOnRecordingStateChanged(false);

    final audioJson = jsonEncode({
      'command': 'transcribe', // 서버와 약속된 오디오 처리 명령어
      "audio_format": "audio/web,;codecs=opus",
      'audio': b64,
      "target_lang1": getSpeaker1,
      "target_lang2": getSpeaker2,
    });

    // _onAudioDataReady?.call(audioJson);
    callOnAudioDataReady(audioJson);
    notifyListeners();
    debugPrint("Audio data encoded");
  }

  // @override
  // Future<Uint8List> stopRecording() async {
  //   _scriptProcessor?.disconnect();
  //   _analyserNode?.disconnect();
  //   _audioSource?.disconnect();

  // Stop all tracks in the MediaStream (getTracks() returns a JSArray)
  // if (_stream != null) {
  //   final tracks = js_util.callMethod(_stream!, 'getTracks', []);
  //   final length = js_util.getProperty(tracks, 'length') as int;
  //   for (var i = 0; i < length; i++) {
  //     final track = js_util.getProperty(tracks, i);
  //     if (track != null) {
  //       js_util.callMethod(track, 'stop', []);
  //     }
  //   }
  // }

  //   _audioAnalyzerTimer?.cancel();
  //   _audioAnalyzerTimer = null;
  //   _audioLevel = 0.0;
  //   _isRecording = false;
  //   debugPrint('⏹️ Stopped audio analysis');
  //   return wavFromBuffers(_audioBuffers);
  // }

  Future<Uint8List> stopRecordingBytes() async {
    if (!_isRecording) return Uint8List(0);

    final path = await _recorder.stop();
    _isRecording = false;

    if (path == null) {
      throw Exception('Recorder returned null path');
    }

    final bytes = await File(path).readAsBytes();

    // 임시파일 정리 (선택)
    try {
      await File(path).delete();
    } catch (_) {}

    return bytes;
  }

  Future<Map<String, dynamic>> stopAndMakePayload({
    required String speaker1,
    required String speaker2,
  }) async {
    final bytes = await stopRecordingBytes();
    final b64 = base64Encode(bytes);

    debugPrint("Autdio format" + _audioFormat + "\n");

    return {
      'command': 'transcribe',
      'audio_format': _audioFormat,
      'audio': b64,
      'target_lang1': speaker1,
      'target_lang2': speaker2,
    };
  }

  @override
  void playAudioBase64(String base64Audio) {
    // const double speed = 1.0; // 재생 속도 설정 (1.0 = 기본 속도)
    // try {
    //   // Base64 → Uint8List 변환
    //   final audioBytes = base64Decode(base64Audio);

    //   // JS Uint8Array 생성
    //   final uint8Array = js_util.callConstructor(
    //     js_util.getProperty(js_util.globalThis, 'Uint8Array') as Object,
    //     [js_util.jsify(audioBytes)],
    //   );

    //   // Blob 생성 (audio/wav MIME type)
    //   final blob = js_util.callConstructor(
    //     js_util.getProperty(js_util.globalThis, 'Blob') as Object,
    //     [
    //       js_util.jsify([uint8Array]),
    //       js_util.jsify({'type': 'audio/wav'}),
    //     ],
    //   );

    //   // Object URL 생성
    //   final url =
    //       js_util.callMethod(
    //             js_util.getProperty(js_util.globalThis, 'URL'),
    //             'createObjectURL',
    //             [blob],
    //           )
    //           as String;

    //   // AudioElement 생성 및 재생
    //   final audio = web.AudioElement();
    //   audio.src = url;
    //   audio.playbackRate = speed; // ✅ 재생 속도 설정 (1.0 = 기본, 1.5 = 1.5배속)

    //   audio.onCanPlayThrough.listen((_) {
    //     final playResult = js_util.callMethod(audio, 'play', []);
    //     js_util.promiseToFuture(playResult).catchError((error) {
    //       print('Audio playback failed: $error');
    //     });
    //   });
    // } catch (e) {
    //   print('❌ Audio playback error: $e');
    // }
  }

  Future<String> _makeTempPath({required String extension}) async {
    final dir = await getTemporaryDirectory();
    final name = 'rec_${DateTime.now().millisecondsSinceEpoch}.$extension';
    return p.join(dir.path, name);
  }

  @override
  void dispose() {
    _audioAnalyzerTimer?.cancel();
    // _channel?.sink.close();
    // _audioSource?.disconnect();
    // _audioContext?.close();

    // if (_stream != null) {
    //   for (int i = 0; i < _stream!.getTracks().length; i++) {
    //     _stream!.getTracks()[i].stop();
    //   }
    // }
    // super.dispose();
  }
}
