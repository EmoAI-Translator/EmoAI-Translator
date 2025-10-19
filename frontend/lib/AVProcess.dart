import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'dart:typed_data'; // audio
import 'package:flutter/foundation.dart'; // for debug
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:js_util' as js_util;
import 'dart:js' as js;

class AVProcess {
  // callback functions to call from main
  final Function(String status)? onVideoStatusChanged;
  final Function(String status)? onAudioStatusChanged;
  final Function(String emotion)? onEmotionReceived;
  final Function()? onFrameProcessed;
  final Function(web.HTMLVideoElement HTMLVideoElement)? onCameraInitialized;
  final Function(
    String original,
    String translated,
    String originalLang,
    String translatedLang,
  )?
  onSpeechTranslated;

  //video ocmponents
  web.HTMLVideoElement? _HTMLVideoElement;
  web.HTMLCanvasElement? _canvasElement;
  web.MediaStream? _stream;
  Timer? _videoCaptureTimer;
  WebSocketChannel? _videoChannel;
  bool _isCapturing = false;

  // // audio elements
  web.AudioContext? _audioContext;
  web.MediaStreamAudioSourceNode? _audioSource;
  web.ScriptProcessorNode? _scriptProcessor;
  WebSocketChannel? _audioChannel;
  Timer? _audioSendTimer;
  final List<Float32List> _audioBuffers = []; //buffer
  int _sampleRate = 44100;

  // connect to backend server
  static const String videoUrl = 'ws://localhost:8000/ws/emotion';
  static const String audioUrl = 'ws://localhost:8000/ws/speech';

  // Set video resolution
  static const int targetWidth = 640;
  static const int targetHeight = 480;
  static const int fps = 5;
  static const int videoCaptureIntervalMs = 1000 ~/ fps;

  int getTargetWidth() => targetWidth;
  int getTargetHeight() => targetHeight;
  bool isCapturing() => _isCapturing;

  // Set audio parameters
  static const int audioSendIntervalMs = 1000;

  AVProcess({
    this.onVideoStatusChanged,
    this.onAudioStatusChanged,
    this.onEmotionReceived,
    this.onFrameProcessed,
    this.onCameraInitialized,
    this.onSpeechTranslated,
  });

  Future<void> initialize() async {
    try {
      final constraints = {
        'video': {'width': targetWidth, 'height': targetHeight},
        'audio': true,
      };

      //set media stream
      _stream = await js_util.promiseToFuture<web.MediaStream>(
        web.window.navigator.mediaDevices!.getUserMedia(
          js_util.jsify(constraints) as web.MediaStreamConstraints,
        ),
      );

      //initialize video
      _HTMLVideoElement = web.HTMLVideoElement()
        ..autoplay = true
        ..srcObject = _stream;

      _canvasElement = web.HTMLCanvasElement()
        ..width = targetWidth
        ..height = targetHeight;

      //initialize audio
      _audioContext = web.AudioContext();
      _audioSource = _audioContext!.createMediaStreamSource(_stream!);
      _scriptProcessor = _audioContext!.createScriptProcessor(4096, 1, 1);
      // Use JS interop to register onaudioprocess because the Dart wrapper may not expose a stream getter
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
              final v = js_util.getProperty(channelData, i) as num;
              samples[i] = v.toDouble();
            }
            _audioBuffers.add(samples);
          } catch (e) {
            debugPrint('❌ audio process callback error: $e');
          }
        }),
      );
      _audioSource!.connect(_scriptProcessor!);
      _scriptProcessor!.connect(_audioContext!.destination!);
      _scriptProcessor!.connect(_audioContext!.destination!);

      onCameraInitialized?.call(_HTMLVideoElement!);
      debugPrint('✅ Camera and Mic initialized successfully');
    } catch (e) {
      debugPrint('❌ AV initialization error: $e');
    }
  }

  Future<void> connect() async {
    // void connect() {
    _connectVideoWebSocket();
    _connectAudioWebSocket();
    // await Future.delayed(Duration(milliseconds: 1000));
  }

  web.HTMLVideoElement? getVideoElement() => _HTMLVideoElement;

  void _connectVideoWebSocket() {
    try {
      _videoChannel = WebSocketChannel.connect(Uri.parse(videoUrl));
      onVideoStatusChanged?.call('Connected');
      _videoChannel!.stream.listen(
        (message) => _handleWebSocketMessage(message),
        onError: (error) => onVideoStatusChanged?.call('Error'),
        onDone: () => onVideoStatusChanged?.call('Disconnected'),
      );
    } catch (e) {
      onVideoStatusChanged?.call('Error');
    }
  }

  void _connectAudioWebSocket() {
    try {
      _audioChannel = WebSocketChannel.connect(Uri.parse(audioUrl));
      onAudioStatusChanged?.call('Connected');

      _audioChannel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);

            // 음성 인식 & 번역 응답 처리
            if (data['status'] == 'success' && data['type'] == 'speech') {
              final original = data['original'];
              final translated = data['translated'];

              onSpeechTranslated?.call(
                original['text'] ?? '',
                translated['text'] ?? '',
                original['lang'] ?? '',
                translated['lang'] ?? '',
              );
              debugPrint(
                '✅ Speech translated: ${original['text']} → ${translated['text']}',
              );
            }
            // 에러 응답 처리
            else if (data['status'] == 'error') {
              debugPrint('❌ Speech error: ${data['message']}');
            }
          } catch (e) {
            debugPrint('❌ Audio message parsing error: $e');
          }
        },
        onError: (error) => onAudioStatusChanged?.call('Error'),
        onDone: () => onAudioStatusChanged?.call('Disconnected'),
      );
    } catch (e) {
      onAudioStatusChanged?.call('Error');
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      if (data['status'] == 'success' && data['type'] == 'realtime') {
        onEmotionReceived?.call(data['emotion'] ?? 'Unknown');
      }
    } catch (e) {
      debugPrint('❌ Message parsing error: $e');
    }
  }

  void startCapture() {
    if (_isCapturing) return;
    _isCapturing = true;

    _videoCaptureTimer = Timer.periodic(
      Duration(milliseconds: videoCaptureIntervalMs),
      (timer) => _captureAndSendFrame(),
    );

    _audioSendTimer = Timer.periodic(
      Duration(milliseconds: audioSendIntervalMs),
      (timer) => _sendAudioData(),
    );
    debugPrint('▶️ Started capturing video and audio');
  }

  void stopCapture() {
    if (!_isCapturing) return;
    _videoCaptureTimer?.cancel();
    _audioSendTimer?.cancel();
    _isCapturing = false;
    debugPrint('⏹️ Stopped capturing');
  }

  void _captureAndSendFrame() {
    if (_HTMLVideoElement == null ||
        _canvasElement == null ||
        _videoChannel == null)
      return;
    final context = _canvasElement!.context2D;
    context.drawImageScaled(
      _HTMLVideoElement!,
      0,
      0,
      targetWidth.toDouble(),
      targetHeight.toDouble(),
    );
    final dataUrl = _canvasElement!.toDataUrl('image/jpeg', 0.8);
    final base64Data = dataUrl.split(',')[1];
    _videoChannel!.sink.add(
      jsonEncode({'command': 'detect', 'frame': base64Data}),
    );
    onFrameProcessed?.call();
  }

  // Send audio data to server
  void _sendAudioData() {
    if (_audioBuffers.isEmpty || _audioChannel == null) return;

    final buffersToSend = List<Float32List>.from(_audioBuffers);
    _audioBuffers.clear();

    final base64Audio = _encodeAudioToBase64(buffersToSend);

    _audioChannel!.sink.add(
      jsonEncode({
        'command': 'transcribe', // 서버와 약속된 오디오 처리 명령어
        'audio': base64Audio,
        'sample_rate': _sampleRate,
      }),
    );
  }

  // Encode autio buffer to Base64
  String _encodeAudioToBase64(List<Float32List> buffers) {
    final pcmData = BytesBuilder();
    for (final buffer in buffers) {
      for (final sample in buffer) {
        final pcm16 = (sample.clamp(-1.0, 1.0) * 32767).toInt();
        pcmData.addByte(pcm16 & 0xFF);
        pcmData.addByte((pcm16 >> 8) & 0xFF);
      }
    }
    return base64Encode(pcmData.toBytes());
  }

  void dispose() {
    _videoCaptureTimer?.cancel();
    _audioSendTimer?.cancel();
    _videoChannel?.sink.close();
    _audioChannel?.sink.close();
    final tracks = _stream?.getTracks();
    if (tracks != null) {
      for (int i = 0; i < tracks.length; i++) {
        tracks[i].stop();
      }
    }
    _scriptProcessor?.disconnect();
    _audioSource?.disconnect();
    _audioContext?.close();
  }
}
