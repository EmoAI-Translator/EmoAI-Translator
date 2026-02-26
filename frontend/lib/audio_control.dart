import 'package:flutter/foundation.dart';
import 'audio_web.dart' if (dart.library.io) 'audio_mobile.dart';
import 'package:record/record.dart';
import 'dart:async';
// import 'package:path_provider/path_provider.dart';
// import 'package:path/path.dart' as p;
import 'dart:convert';

class AudioControl extends ChangeNotifier {
  static AudioControl create() {
    return AudioImpl();
  }

  //audio recordings
  final AudioRecorder _recorder = AudioRecorder();
  Completer<String>? _recordCompleter;

  //for audio analysis
  StreamSubscription<Amplitude>? _ampSub;
  Timer? _audioAnalyzerTimer;
  bool _isRecording = false;
  double _audioLevel = 0.0; // 0.0 ~ 1.0
  final ValueNotifier<double> audioLevelNotifier = ValueNotifier(0.0);
  bool recorderSet = false;

  //For auto termination
  late Duration _silenceDuration;
  final double _silenceThreshold = 0.1; // 임계값 (0.0~1.0), 필요시 조정
  final Duration _silenceDurationLimit = const Duration(seconds: 2);

  //audio format depending on platform
  // String _audioFormat = kIsWeb ? 'audio/webm;codecs=opus' : 'audio/mp4';

  final List<String> _speakerLanguage = ['ko', 'en'];

  Future<bool> requestPermission() async {
    final permission = await _recorder.hasPermission();
    if (permission) debugPrint('🎙️ Microphone access granted');
    return permission;
  }

  Future<String?> startRecording() async {
    if (_isRecording) return null;

    final permission = await _recorder.hasPermission();
    if (!permission) throw Exception('No microphone permission');

    _isRecording = true;
    _recordCompleter = Completer<String>();

    final config = getRecordConfig();
    final path = await getStoragePath();

    // final ext = kIsWeb ? 'webm' : 'm4a';
    // _audioFormat = kIsWeb ? 'audio/webm;codecs=opus' : 'audio/mp4';
    // final path = await _makeTempPath(extension: ext);

    await _recorder.start(
      config,
      path: path ?? '',
    );

    _silenceDuration = Duration.zero;
    _ampSub?.cancel();
    _ampSub = _recorder
        .onAmplitudeChanged(Duration(milliseconds: 50))
        .listen(
          _analyzeAudioLevel,
          onError: (e, st) {
            debugPrint('Amplitude stream erorr: $e');
          },
        );

    debugPrint('Started Recording');

    return _recordCompleter!.future;
  }

  void _analyzeAudioLevel(Amplitude amp) {
    final db = amp.current;

    // 예: -60dB 이하는 거의 무음으로 보고, 0dB을 1.0으로 매핑
    const double floorDb = -60.0;
    final normalized = ((db - floorDb) / (0.0 - floorDb)).clamp(0.0, 1.0);

    // Smooth the audio level changes
    // _audioLevel = (_audioLevel * 0.7) + (normalized * 0.3);
    audioLevelNotifier.value =
        (audioLevelNotifier.value * 0.7) + (normalized * 0.3);

    if (_audioLevel < _silenceThreshold) {
      _silenceDuration += const Duration(milliseconds: 50);

      if (_silenceDuration >= _silenceDurationLimit) {
        debugPrint('Silence detected for 3 seconds. Auto-stopping...');
        stopRecording();
      }
    } else {
      // 다시 음성 감지되면 리셋
      _silenceDuration = Duration.zero;
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _isRecording = false;

    await _ampSub!.cancel();
    _ampSub = null;

    _audioLevel = 0.0;
    audioLevelNotifier.value = 0.0;

    final path = await _recorder.stop();
    if (path == null) {
      _recordCompleter!.completeError("No file path");
      return;
    }

    final bytes = await readRecordBytes(path);

    final audioJson = jsonEncode({
      'command': 'transcribe', // 서버와 약속된 오디오 처리 명령어
      "audio_format": "audio/web,;codecs=opus",
      'audio': bytes,
      "target_lang1": getSpeaker1,
      "target_lang2": getSpeaker2,
    });
    _recordCompleter!.complete(audioJson);
  }

  // Future<String> _makeTempPath({required String extension}) async {
  //   final dir = await getTemporaryDirectory();
  //   final name = 'rec_${DateTime.now().millisecondsSinceEpoch}.$extension';
  //   return p.join(dir.path, name);
  // }

  double get audioLevel => _audioLevel;
  bool get isRecording => _isRecording;

  String get getSpeaker1 => _speakerLanguage[0];
  String get getSpeaker2 => _speakerLanguage[1];

  set speaker1(String lang) => _speakerLanguage[0] = lang;
  set speaker2(String lang) => _speakerLanguage[1] = lang;

  @protected
  Future<String> readRecordBytes(String blobUrl) async {
    throw UnsupportedError('Platform not supported');
  }

  @protected
  RecordConfig getRecordConfig() {
    throw UnsupportedError('Platform not supported');
  }

  @protected
  Future<String?> getStoragePath() {
    throw UnsupportedError('Platform not supported');
  }

  void playVoice(String base64Audio) {
    final Uint8List audioBytes = base64Decode(base64Audio);
    playVoicePerPlatform(audioBytes);
  }

  @protected
  void playVoicePerPlatform(Uint8List audioBytes) {
    throw UnsupportedError('Platform not supported');
  }
}
