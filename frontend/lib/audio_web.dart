import 'audio_control.dart';

import 'dart:typed_data';
import 'package:web/web.dart' as web;
// import 'record_bytes.dart';
// import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:js_interop';
import 'package:record/record.dart';

class AudioImpl extends AudioControl {
  @override
  Future<String> readRecordBytes(String blobUrl) async {
    final web.Response resp = await web.window.fetch(blobUrl.toJS).toDart;
    if (!resp.ok) {
      throw Exception('Failed to fetch blob: ${resp.status}');
    }

    final ByteBuffer buffer = await resp.arrayBuffer().toDart.then(
      (ab) => ab.toDart,
    );
    final Uint8List bytes = buffer.asUint8List();

    return base64Encode(bytes);
  }

  @override
  void playVoicePerPlatform(Uint8List audioBytes) {
    // 웹 전용: Blob 및 HTMLAudioElement 사용
    final blob = web.Blob(
      [audioBytes.toJS].toJS,
      web.BlobPropertyBag(type: 'audio/aac'),
    ); // 컨테이너에 따라 'audio/mp4'로 변경 필요할 수 있음
    final url = web.URL.createObjectURL(blob);
    final audio = web.HTMLAudioElement()..src = url;
    audio.play();
  }

  @override
  RecordConfig getRecordConfig() => const RecordConfig(
    encoder: AudioEncoder.opus, // 웹 최적화
    bitRate: 64000,
    sampleRate: 48000,
  );

  @override
  Future<String?> getStoragePath() async => null; // 웹은 경로가 필요 없음

  @override
  void dispose() {
    // super.dispose();
  }
}
