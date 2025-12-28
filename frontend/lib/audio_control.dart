// lib/services/audio_recorder_service.dart
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'audio_web.dart' if (dart.library.io) 'audio_mobile.dart';

typedef OnAudioDataReady = void Function(String audioJson);
typedef OnRecordingStateChanged = void Function(bool isRecording);

class AudioControl extends ChangeNotifier {
  static AudioControl create() {
    return AudioImpl();
  }

  List<String> _speakerLanguage = ['ko', 'en'];

  OnAudioDataReady? _onAudioDataReady;
  OnRecordingStateChanged? _onRecordingStateChanged;

  Future<bool> requestPermission() async {
    throw UnsupportedError('Platform not supported');
  }

  Future<void> startRecording() async {
    throw UnsupportedError('Platform not supported');
  }

  Future<Uint8List> stopRecording() async {
    throw UnsupportedError('Platform not supported');
  }

  double get audioLevel => 0.0;
  bool get isRecording => false;

  String get getSpeaker1 => _speakerLanguage[0];
  String get getSpeaker2 => _speakerLanguage[1];

  set speaker1(String lang) => _speakerLanguage[0] = lang;
  set speaker2(String lang) => _speakerLanguage[1] = lang;

  void setOnAudioDataReady(OnAudioDataReady callback) {
    _onAudioDataReady = callback;
  }

  void setOnRecordingStateChanged(OnRecordingStateChanged callback) {
    _onRecordingStateChanged = callback;
  }

  // 콜백 실행 헬퍼
  void callOnAudioDataReady(String audioJson) {
    _onAudioDataReady?.call(audioJson);
  }

  void callOnRecordingStateChanged(bool isRecording) {
    _onRecordingStateChanged?.call(isRecording);
  }

  void playAudioBase64(String base64Audio) {
    throw UnsupportedError('Platform not supported');
  }

  Uint8List wavFromBuffers(List<Float32List> buffers) {
    final allSamples = Float32List(
      buffers.fold<int>(0, (a, b) => a + b.length),
    );
    var offset = 0;
    for (var chunk in buffers) {
      allSamples.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return encodeWav(allSamples);
  }

  // WAV 인코딩
  Uint8List encodeWav(
    Float32List samples, {
    int sampleRate = 44100,
    int numChannels = 1,
  }) {
    final pcmData = float32ToPCM16(samples);
    final wav = BytesBuilder();

    // RIFF 헤더
    wav.add(utf8.encode('RIFF'));
    wav.add(_intToBytes32(36 + pcmData.length)); // ChunkSize
    wav.add(utf8.encode('WAVE'));

    // fmt 서브청크
    wav.add(utf8.encode('fmt '));
    wav.add(_intToBytes32(16)); // Subchunk1Size
    wav.add(_intToBytes16(1)); // AudioFormat PCM
    wav.add(_intToBytes16(numChannels));
    wav.add(_intToBytes32(sampleRate));
    wav.add(_intToBytes32(sampleRate * numChannels * 2)); // ByteRate
    wav.add(_intToBytes16(numChannels * 2)); // BlockAlign
    wav.add(_intToBytes16(16)); // BitsPerSample

    // data 서브청크
    wav.add(utf8.encode('data'));
    wav.add(_intToBytes32(pcmData.length));
    wav.add(pcmData);

    return wav.toBytes();
  }

  Uint8List float32ToPCM16(Float32List samples) {
    final buffer = Uint8List(samples.length * 2);
    final byteData = buffer.buffer.asByteData();
    for (var i = 0; i < samples.length; i++) {
      var s = samples[i];
      s = s.clamp(-1.0, 1.0);
      byteData.setInt16(i * 2, (s * 32767).toInt(), Endian.little);
    }
    return buffer;
  }

  Uint8List _intToBytes16(int value) {
    final bytes = Uint8List(2);
    final bd = bytes.buffer.asByteData();
    bd.setInt16(0, value, Endian.little);
    return bytes;
  }

  Uint8List _intToBytes32(int value) {
    final bytes = Uint8List(4);
    final bd = bytes.buffer.asByteData();
    bd.setInt32(0, value, Endian.little);
    return bytes;
  }
}
