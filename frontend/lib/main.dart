import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:typed_data';
//For audio, record failed to work on web
import 'dart:js_util' as js_util;
import 'dart:js' as js;

//for tts
import 'package:flutter_tts/flutter_tts.dart';
// import 'audio_process.dart';

void main() {
  runApp(const MyApp());
}

class TTS {
  final FlutterTts _tts = FlutterTts();

  Future<void> initializeTTS() async {
    await _tts.setLanguage('ko-KR'); // Korean
    await _tts.setSpeechRate(0.5); // 0.0 ~ 1.0
    await _tts.setVolume(1.0); // 0.0 ~ 1.0
    await _tts.setPitch(1.0); // 0.5 ~ 2.0
  }

  Future<void> setLanguage(String languageCode) async {
    await _tts.setLanguage(languageCode);
  }

  Future<void> setEmotion(String emotion) async {
    if (emotion == 'happy') {
      await _tts.setPitch(1.2);
    } else if (emotion == 'sad') {
      await _tts.setPitch(0.8);
      await _tts.setSpeechRate(0.8);
    } else if (emotion == 'angry') {
      await _tts.setPitch(1.5);
      await _tts.setSpeechRate(1.5);
    } else {
      await _tts.setPitch(1.0);
    }
  }

  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  Future<void> pause() async {
    await _tts.pause();
  }
}

//supported lanuages, right now, lanuage is hardcoded in surver side
// enum Language { ko, en }

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emo-AI Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const EmotionDetectionPage(),
    );
  }
}

class EmotionDetectionPage extends StatefulWidget {
  const EmotionDetectionPage({super.key});

  @override
  State<EmotionDetectionPage> createState() => _EmotionDetectionPageState();
}

class _EmotionDetectionPageState extends State<EmotionDetectionPage> {
  //connect to backend server
  static const String wsUrl = 'ws://localhost:8000/ws/speech';
  web.MediaStream? _stream;
  Timer? _audioAnalyzerTimer;
  WebSocketChannel? _channel;

  // Audio analysis
  web.AudioContext? _audioContext;
  web.AnalyserNode? _analyserNode;
  web.MediaStreamAudioSourceNode? _audioSource;
  web.ScriptProcessorNode? _scriptProcessor;

  final List<Float32List> _audioBuffers = []; //buffer
  bool _isTransmitting = false;
  String _connectionStatus = 'Disconnected';
  double _audioLevel = 0.0; // 0.0 ~ 1.0
  bool recorderSet = false;

  final List<Float32List> _buffers = [];
  TTS tts = TTS();

  //for frontend
  List<String> Speaker1 = [];
  List<String> Speaker2 = [];
  bool _initialstate = true;
  String _currentLanguage1 = 'en';
  String _currentLanguage2 = 'ko';

  //For auto termination
  late Duration _silenceDuration;
  final double _silenceThreshold = 0.1; // 임계값 (0.0~1.0), 필요시 조정
  final Duration _silenceDurationLimit = const Duration(seconds: 3);

  // Return Example (Backend → Frontend)
  //   {
  //       "status": "success",
  //       "type": "speech",
  //       "speaker": "Speaker 1",
  //       "original": {
  //           "lang": "ko",
  //           "text": "안녕하세요"
  //       },
  //       "translated": {
  //           "timestamp": datetime.utcnow().isoformat(),
  //           "lang": lang,
  //           "text": text,
  //       },
  //       "emotion": "happy",
  //       "emotion_scores": {"happy": 0.95, "sad": 0.02, ...}
  //   }

  //variable for recived data
  String speaker = '';
  Map<String, dynamic> original = {'lang': '', 'text': ''};
  Map<String, dynamic> translated = {'timestamp': '', 'lang': '', 'text': ''};
  String emotion = '';
  Map<String, dynamic> emotion_scores = {
    'happy': 0.0,
    'sad': 0.0,
    'angry': 0.0,
    'neutral': 0.0,
  };

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
    _initializeAudioStream().then((_) {
      debugPrint('Audio stream initialized successfully');
    });
    tts.initializeTTS();
    _silenceDuration = Duration.zero;
  }

  Future<void> _initializeAudioStream() async {
    _buffers.clear();

    final constraints = web.MediaStreamConstraints(audio: true.toJS);
    final jsPromise = web.window.navigator.mediaDevices!.getUserMedia(
      constraints,
    );
    _stream = await js_util.promiseToFuture(jsPromise);
    debugPrint('🎙️ Microphone access granted');

    _audioContext = web.AudioContext();

    _audioSource = _audioContext!.createMediaStreamSource(_stream!);
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
            final v = js_util.getProperty(channelData, i) as num;
            samples[i] = v.toDouble();
          }
          _audioBuffers.add(samples);
        } catch (e) {
          debugPrint('❌ audio process callback error: $e');
        }
      }),
    );
    // final constraints = web.MediaStreamConstraints(audio: true.toJS);
    try {
      final jsPromise = web.window.navigator.mediaDevices!.getUserMedia(
        constraints,
      );
      _stream = await js_util.promiseToFuture(jsPromise);
    } catch (e) {
      debugPrint('❌ Error accessing microphone: $e');
      return;
    }

    //For audio analysis
    _analyserNode = _audioContext!.createAnalyser();
    _analyserNode!.fftSize = 256;
    _audioSource!.connect(_analyserNode!);

    // Initialize audio context for volume analysis
    _audioSource!.connect(_scriptProcessor!);
  }

  Future<void> _startAudioAnalysis() async {
    _audioBuffers.clear();

    // 1. 마이크 접근
    final constraints = web.MediaStreamConstraints(audio: true.toJS);
    final jsPromise = web.window.navigator.mediaDevices!.getUserMedia(
      constraints,
    );
    _stream = await js_util.promiseToFuture(jsPromise);
    debugPrint('🎙️ Microphone access granted');

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

  Future<Uint8List> stopRecordingAndAnalysis() async {
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
    setState(() => _audioLevel = 0.0);

    debugPrint('⏹️ Stopped audio analysis');
    return wavFromBuffers(_audioBuffers);
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

    setState(() {
      // Smooth the audio level changes
      _audioLevel = (_audioLevel * 0.7) + (normalizedLevel * 0.3);
    });

    if (_audioLevel < _silenceThreshold) {
      _silenceDuration += const Duration(milliseconds: 50);

      if (_silenceDuration >= _silenceDurationLimit) {
        debugPrint('🔇 Silence detected for 3 seconds. Auto-stopping...');
        stopRecordingAndAnalysis();
      }
    } else {
      // 다시 음성 감지되면 리셋
      _silenceDuration = Duration.zero;
    }
  }

  void _connectWebSocket() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      setState(() {
        _connectionStatus = 'Connected';
        debugPrint('🔗 Connected to WebSocket at $wsUrl');
      });

      _channel!.stream.listen(
        (message) {
          _handleWebSocketMessage(message);
        },
        onError: (error) {
          debugPrint('❌ WebSocket error: $error');
          setState(() {
            _connectionStatus = 'Error';
          });
        },
        onDone: () {
          debugPrint('❌ WebSocket disconnected');
          setState(() {
            _connectionStatus = 'Disconnected';
          });
        },
      );

      debugPrint('✅ WebSocket connected');
    } catch (e) {
      debugPrint('❌ WebSocket connection error: $e');
      setState(() {
        _connectionStatus = 'Error';
      });
    }
  }

  //  Normally, backend send messages in the following format:
  // {
  //     "status": "success",
  //     "type": "speech",
  //     "speaker": current_speaker,
  //     "original": {"lang": lang, "text": text},
  //     "translated": translated,
  //     "emotion": emotion,
  //     "emotion_scores": scores,
  // }

  void playAudioBase64(String base64Audio) {
    try {
      // Base64 → Uint8List 변환
      final audioBytes = base64Decode(base64Audio);

      // JS Uint8Array 생성
      final uint8Array = js_util.callConstructor(
        js_util.getProperty(js_util.globalThis, 'Uint8Array') as Object,
        [js_util.jsify(audioBytes)],
      );

      // Blob 생성 (audio/wav MIME type)
      final blob = js_util.callConstructor(
        js_util.getProperty(js_util.globalThis, 'Blob') as Object,
        [
          js_util.jsify([uint8Array]),
          js_util.jsify({'type': 'audio/wav'}),
        ],
      );

      // Object URL 생성
      final url =
          js_util.callMethod(
                js_util.getProperty(js_util.globalThis, 'URL'),
                'createObjectURL',
                [blob],
              )
              as String;

      // AudioElement 생성 및 재생 준비
      final audio = web.AudioElement();
      audio.src = url;

      // 로드 완료 시 재생
      audio.onCanPlayThrough.listen((_) {
        final playResult = js_util.callMethod(audio, 'play', []);
        // JS Promise 결과 캐치 (에러 무시 방지)
        js_util.promiseToFuture(playResult).catchError((error) {
          print('Audio playback failed: $error');
        });
      });
    } catch (e) {
      print('❌ Audio playback error: $e');
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final status = data['status'] as String?;
      final type = data['type'] as String?;

      if (status == 'success' && type == 'speech') {
        debugPrint('✅ Message from backend: $data');
        setState(() {
          speaker = data['speaker'] ?? 'Speaker 1';
          original = data['original'] ?? {};
          translated = data['translated'] ?? {};
          emotion = data['emotion'] ?? '';
          emotion_scores = data['emotion_scores'] ?? {};

          // Play TTS audio if available
          final audioB64 = translated['tts_audio_b64'];
          if (audioB64 != null) {
            debugPrint('🔊 Playing TTS audio for $speaker');
            playAudioBase64(audioB64);
          }

          if (speaker == 'Speaker 1') {
            Speaker1.add(
              "${translated['timestamp'] ?? ''}: ${translated['text'] ?? ''}",
            );
            setState(() {
              _currentLanguage1 = translated['lang'] ?? 'ko';
            });
          } else {
            Speaker2.add(
              "${translated['timestamp'] ?? ''}: ${translated['text'] ?? ''}",
            );
          }
        });

        debugPrint(
          '🗣️ Speaker: $speaker, Original: ${original['text']}, Translated: ${translated['text']}, Emotion: $emotion',
        );
      } else if (status == 'error') {
        debugPrint('❌ Message from backend error: ${data['message']}');
      }
    } catch (e) {
      debugPrint('❌ Message parsing error: $e');
    }
  }

  Future<void> _startTransmitting() async {
    if (_isTransmitting || _channel == null) return;
    setState(() {
      _isTransmitting = true;
    });
    _startAudioAnalysis();

    debugPrint('▶️ Started transmitting');
  }

  // Formet to send to backend
  // {
  //     "command": "transcribe",
  //     "audio": "<base64_encoded_audio_string>",
  //     "target_lang": "en"
  // }

  Future<void> _stopTransmitting() async {
    final wav = await stopRecordingAndAnalysis();
    final finalformWav = base64Encode(wav);
    debugPrint('Base64 length: ${finalformWav.length}');
    _channel!.sink.add(
      jsonEncode({
        'command': 'transcribe', // 서버와 약속된 오디오 처리 명령어
        'audio': finalformWav,
        "target_lang1": _currentLanguage1,
        "target_lang2": _currentLanguage2,
      }),
    );
    setState(() {
      _isTransmitting = false;
      _initialstate = false;
    });
  }

  // Float32List를 PCM16으로 변환
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

  // int → little-endian bytes 변환
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

  @override
  void dispose() {
    _audioAnalyzerTimer?.cancel();
    _channel?.sink.close();
    _audioSource?.disconnect();
    _audioContext?.close();

    if (_stream != null) {
      for (int i = 0; i < _stream!.getTracks().length; i++) {
        _stream!.getTracks()[i].stop();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buttonSize = 200.0;

    // Calculate shadow radius based on audio level
    final baseRadius = 20.0;
    final maxRadius = 100.0;
    final shadowRadius = baseRadius + (_audioLevel * (maxRadius - baseRadius));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      // Main content
                      Center(
                        child: Column(
                          // mainAxisAlignment: MainAxisAlignmen  t.center,
                          children: [
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _currentLanguage1 = 'ko';
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _currentLanguage1 == 'ko'
                                        ? Colors.blue
                                        : Colors.grey,
                                  ),
                                  child: Text(
                                    'Korean',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _currentLanguage1 = 'en';
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _currentLanguage1 == 'en'
                                        ? Colors.blue
                                        : Colors.grey,
                                  ),
                                  child: Text(
                                    'English',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _currentLanguage1 = 'ja';
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _currentLanguage1 == 'ja'
                                        ? Colors.blue
                                        : Colors.grey,
                                  ),
                                  child: Text(
                                    'Japanese',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _currentLanguage1 = 'zh';
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _currentLanguage1 == 'zh'
                                        ? Colors.blue
                                        : Colors.grey,
                                  ),
                                  child: Text(
                                    'Chinese',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            // Status indicator
                            Expanded(
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _connectionStatus == 'Connected'
                                              ? Icons.check_circle
                                              : Icons.error,
                                          color:
                                              _connectionStatus == 'Connected'
                                              ? Colors.green
                                              : Colors.red,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          _connectionStatus,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const SizedBox(height: 40),

                                  // // Emotion display
                                  // Text(
                                  //   // _currentEmotion,
                                  //   original['lang'] == null
                                  //       ? ''
                                  //       : '[${original['lang']!.toUpperCase()}] ${original['text']!}',
                                  //   style: const TextStyle(
                                  //     color: Colors.white,
                                  //     fontSize: 32,
                                  //     fontWeight: FontWeight.bold,
                                  //   ),
                                  // ),
                                  const SizedBox(height: 60),
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 100,
                                        ),
                                        width: buttonSize,
                                        height: buttonSize,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _isTransmitting
                                              ? Colors.red
                                              : Colors.blue,
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  (_isTransmitting
                                                          ? Colors.red
                                                          : Colors.blue)
                                                      .withOpacity(0.6),
                                              blurRadius: shadowRadius,
                                              spreadRadius: shadowRadius / 2,
                                            ),
                                          ],
                                        ),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          if (_isTransmitting) {
                                            _stopTransmitting();
                                          } else {
                                            if (_channel != null) {
                                              _startTransmitting();
                                            }
                                          }
                                        },
                                        style: ElevatedButton.styleFrom(
                                          shape: const CircleBorder(),
                                          padding: EdgeInsets.all(
                                            buttonSize / 3,
                                          ),
                                          backgroundColor: _isTransmitting
                                              ? Colors.red
                                              : Colors.blue,
                                          shadowColor:
                                              (_isTransmitting
                                                      ? Colors.red
                                                      : Colors.blue)
                                                  .withOpacity(0.6),
                                          elevation: shadowRadius / 2,
                                        ),
                                        child: Icon(
                                          _isTransmitting
                                              ? Icons.stop
                                              : Icons.mic,
                                          color: Colors.white,
                                          size: 80,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    translated['text'] == null
                                        ? ''
                                        : translated['text']!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 40),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Bottom info panel
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 40,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              // color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_initialstate)
                  Container(
                    width: MediaQuery.of(context).size.width * 0.4,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,

                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: Speaker1.length,
                              itemBuilder: (context, index) {
                                final message = Speaker1[index];
                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[800],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    message,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: Speaker2.length,
                              itemBuilder: (context, index) {
                                final message = Speaker2[index];
                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[800],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    message,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Text(
            _isTransmitting
                ? 'Tap to stop detection'
                : 'Tap to start detection',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
