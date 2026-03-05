import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'audio_control.dart';

class AudioImpl extends AudioControl {
  static final AudioPlayer _player = AudioPlayer();

  @override
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    final granted = status.isGranted;
    if (granted) {
      return super.requestPermission();
    }
    return false;
  }

  @override
  Future<String> readRecordBytes(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final encoded = base64Encode(bytes);

    // 모바일은 녹음 데이터 파일을 즉시 폐기한다.
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // 삭제 실패는 전송 자체를 막지 않도록 무시
    }

    return encoded;
  }

  @override
  RecordConfig getRecordConfig() => const RecordConfig(
    encoder: AudioEncoder.opus,
    bitRate: 64000,
    sampleRate: 48000,
    numChannels: 1,
  );

  @override
  Future<String?> getStoragePath() async {
    final dir = await getTemporaryDirectory();
    final name = 'rec_${DateTime.now().millisecondsSinceEpoch}.ogg';
    return p.join(dir.path, name);
  }

  @override
  String getAudioFormat() => 'audio/ogg;codecs=opus';

  @override
  void playVoicePerPlatform(Uint8List audioBytes) {
    _player.play(BytesSource(audioBytes));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
