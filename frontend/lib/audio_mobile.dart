import 'audio_control.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'package:record/record.dart'; // package:record 사용
import 'package:permission_handler/permission_handler.dart'; // 권한 관리

typedef OnAudioDataReady = void Function(String audioJson);
typedef OnRecordingStateChanged = void Function(bool isRecording);

class AudioImpl extends AudioControl {
  // 모바일 녹음기 인스턴스
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<List<int>>? _recordSub;

  // 오디오 데이터 버퍼 (PCM 16bit 데이터를 모으기 위함)
  final List<int> _audioBytesBuffer = [];

  bool _isRecording = false;
  double _audioLevel = 0.0;

  // 침묵 감지 관련
  late Duration _silenceDuration;
  final double _silenceThreshold = 0.05; // 모바일 마이크 감도에 따라 조절 필요
  final Duration _silenceDurationLimit = const Duration(seconds: 2);
  Timer? _silenceTimer;

  OnAudioDataReady? _onAudioDataReady;
  OnRecordingStateChanged? _onRecordingStateChanged;

  AudioMobile({
    OnAudioDataReady? onAudioDataReady,
    OnRecordingStateChanged? onRecordingStateChanged,
  }) {
    _onAudioDataReady = onAudioDataReady;
    _onRecordingStateChanged = onRecordingStateChanged;
  }

  @override
  double get audioLevel => _audioLevel;

  // AudioControlImpl({onAudioDataReady, onRecordingStateChanged}) {
  //   _onAudioDataReady = onAudioDataReady;
  //   _onRecordingStateChanged = onRecordingStateChanged;
  // }

  @override
  Future<bool> requestPermission() async {
    // Permission Handler 사용
    var status = await Permission.microphone.request();
    if (status.isGranted) {
      debugPrint('Microphone access granted');
      return true;
    } else {
      debugPrint('Microphone access denied');
      return false;
    }
  }

  @override
  Future<void> startRecording() async {
    if (_isRecording) return;

    // 권한 재확인
    if (!await _audioRecorder.hasPermission()) {
      debugPrint('❌ No permission to record');
      return;
    }

    try {
      _isRecording = true;
      _audioBytesBuffer.clear();
      _silenceDuration = Duration.zero;
      _audioLevel = 0.0;

      debugPrint('▶️ Started Mobile Recording');
      notifyListeners();

      // 스트림 시작 (PCM 16bit, 16000Hz, Mono 권장 - STT 서버 스펙에 맞춤)
      final stream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );

      _recordSub = stream.listen((data) {
        // 1. 데이터 버퍼에 저장
        _audioBytesBuffer.addAll(data);

        // 2. 실시간 볼륨 분석
        _analyzeAudioLevel(data);
      });

      // 침묵 감지 타이머 시작 (0.1초마다 체크)
      _silenceTimer = Timer.periodic(const Duration(milliseconds: 100), (
        timer,
      ) {
        _checkSilence();
      });

      _onRecordingStateChanged?.call(true);
    } catch (e) {
      debugPrint("❌ Error starting record: $e");
      _isRecording = false;
    }
  }

  // 들어오는 PCM 데이터 덩어리를 분석하여 볼륨 계산
  void _analyzeAudioLevel(List<int> data) {
    // PCM 16bit는 2바이트가 1개의 샘플 (-32768 ~ 32767)
    // 데이터가 너무 많으므로 일부만 샘플링하여 계산 (성능 최적화)
    double sumSquares = 0.0;
    int sampleCount = 0;

    for (int i = 0; i < data.length; i += 2) {
      if (i + 1 >= data.length) break;

      // Little Endian 변환
      int byte1 = data[i];
      int byte2 = data[i + 1];
      int s16 = (byte2 << 8) | byte1;

      // 부호 있는 16비트 정수로 변환
      if (s16 > 32767) s16 -= 65536;

      // -1.0 ~ 1.0 정규화
      double normalized = s16 / 32768.0;
      sumSquares += normalized * normalized;
      sampleCount++;
    }

    if (sampleCount > 0) {
      // RMS (Root Mean Square) 계산
      double rms = sqrt(sumSquares / sampleCount);

      // 스무딩 적용
      _audioLevel = (_audioLevel * 0.7) + (rms * 0.3);
      notifyListeners();
    }
  }

  void _checkSilence() {
    if (!_isRecording) return;

    if (_audioLevel < _silenceThreshold) {
      _silenceDuration += const Duration(milliseconds: 100);
      if (_silenceDuration >= _silenceDurationLimit) {
        debugPrint('🔇 Silence detected on Mobile. Auto-stopping...');
        _stopTransmitting();
      }
    } else {
      _silenceDuration = Duration.zero;
    }
  }

  Future<void> _stopTransmitting() async {
    if (!_isRecording) return;

    final wavBytes = await stopRecording();
    final base64Wav = base64Encode(wavBytes);

    debugPrint('Encoded Audio Length: ${base64Wav.length}');

    final audioJson = jsonEncode({
      'command': 'transcribe',
      'audio': base64Wav,
      "target_lang1": getSpeaker1, // AudioControl의 getter
      "target_lang2": getSpeaker2, // AudioControl의 getter
    });

    _onAudioDataReady?.call(audioJson);
    notifyListeners();
  }

  @override
  Future<Uint8List> stopRecording() async {
    _isRecording = false;
    _silenceTimer?.cancel();
    await _recordSub?.cancel();
    await _audioRecorder.stop(); // 스트림 중지

    debugPrint('⏹️ Stopped mobile recording');

    _onRecordingStateChanged?.call(false);
    notifyListeners();

    // Raw PCM 데이터를 WAV 포맷으로 변환 (헤더 추가)
    return _pcmToWav(Uint8List.fromList(_audioBytesBuffer));
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _recordSub?.cancel();
    _audioRecorder.dispose();
  }

  Uint8List _pcmToWav(Uint8List pcmBytes) {
    final int sampleRate = 16000;
    final int channels = 1;
    final int byteRate = sampleRate * channels * 2; // 16bit = 2bytes

    final header = ByteData(44);
    final totalDataLen = pcmBytes.length;
    final totalFileSize = totalDataLen + 36;

    // RIFF header
    _writeString(header, 0, 'RIFF');
    header.setUint32(4, totalFileSize, Endian.little);
    _writeString(header, 8, 'WAVE');

    // fmt chunk
    _writeString(header, 12, 'fmt ');
    header.setUint32(16, 16, Endian.little); // PCM chunk size
    header.setUint16(20, 1, Endian.little); // Audio format 1 (PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, channels * 2, Endian.little); // Block align
    header.setUint16(34, 16, Endian.little); // Bits per sample

    // data chunk
    _writeString(header, 36, 'data');
    header.setUint32(40, totalDataLen, Endian.little);

    final wavBytes = Uint8List(44 + pcmBytes.length);
    wavBytes.setRange(0, 44, header.buffer.asUint8List());
    wavBytes.setRange(44, 44 + pcmBytes.length, pcmBytes);

    return wavBytes;
  }

  void _writeString(ByteData data, int offset, String value) {
    for (int i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }
}
