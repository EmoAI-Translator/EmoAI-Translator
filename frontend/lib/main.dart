import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';
// import 'dart:ui_web' as ui_web;
import 'dart:typed_data';

//For audio, record failed to work on web.
import 'dart:js_util' as js_util;
import 'dart:js' as js;

//for tts
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(const MyApp());
}

class TTS {
  final FlutterTts _tts = FlutterTts();

  Future<void> initializeTTS() async {
    await _tts.setLanguage('ko-KR'); // 한국어
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
  static const int audioSendIntervalMs = 1000;

  Timer? _audioSendTimer;
  final List<Float32List> _audioBuffers = []; //buffer
  // final int _sampleRate = 44100;

  bool _isTransmitting = false;
  String _currentEmotion = 'Unknown';
  String _connectionStatus = 'Disconnected';
  // Map<String, dynamic>? _summaryData;
  double _audioLevel = 0.0; // 0.0 ~ 1.0
  // final List<Float32List> _buffers = []; //buffer
  // final AudioRecorder _recorder = AudioRecorder();
  final List<Float32List> _buffers = [];
  // Uint8List? _recordedBytes;
  TTS tts = TTS();

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
    _scriptProcessor!.connect(_audioContext!.destination!);
    _scriptProcessor!.connect(_audioContext!.destination!);
  }

  void _startAudioAnalysis() {
    if (_audioAnalyzerTimer != null) return;

    _audioAnalyzerTimer = Timer.periodic(
      const Duration(milliseconds: 50), // Update 20 times per second
      (timer) => _analyzeAudioLevel(),
    );

    debugPrint('▶️ Started audio analysis');
  }

  void _stopAudioAnalysis() {
    _audioAnalyzerTimer?.cancel();
    _audioAnalyzerTimer = null;
    setState(() {
      _audioLevel = 0.0;
    });
    debugPrint('⏹️ Stopped audio analysis');
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

  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final status = data['status'] as String?;
      final type = data['type'] as String?;

      if (status == 'success' && type == 'speech') {
        debugPrint('✅ Message from backend: $data');
        setState(() {
          speaker = data['speaker'] ?? 'Unknown';
          // final original_text = jsonDecode(data['original']);
          original = data['original'] ?? {};

          // final original_translated = jsonDecode(data['translated']);
          translated = data['translated'] ?? {};
          emotion = data['emotion'] ?? '';
          emotion_scores = data['emotion_scores'] ?? {};
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

    _audioBuffers.clear(); //이거 안씀
    _buffers.clear();

    _audioSendTimer = Timer.periodic(
      const Duration(milliseconds: 1000), // 1초마다
      (timer) {
        if (_audioBuffers.isNotEmpty) {
          _buffers.addAll(_audioBuffers);
          _audioBuffers.clear();
          debugPrint('📦 Buffered audio chunk: ${_buffers.length} buffers');
        }
      },
    );

    // _audioSendTimer = Timer.periodic(
    //   Duration(milliseconds: audioSendIntervalMs),
    //   (timer) => _sendAudioData(),
    // );

    // if (await _recorder.hasPermission()) {
    // 스트림으로 실시간 버퍼 받기
    // final stream = await _recorder.startStream(
    //   const RecordConfig(),
    //   //encoder: AudioEncoder.pcm16bit, sampleRate: 16000
    // );

    // stream.listen((data) {
    //   // 받은 버퍼 저장
    //   final float32 = Float32List.view(
    //     Uint8List.fromList(data).buffer,
    //     0,
    //     data.length ~/ 4,
    //   );
    //   _buffers.add(float32);
    // }, onError: (e) => print('Error: $e'));
    // // }

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
    if (!_isTransmitting) return;
    _audioSendTimer?.cancel();
    debugPrint('⏹️ Stopped transmitting');
    _stopAudioAnalysis();
    setState(() {
      _isTransmitting = false;
    });
    // debugPrint('⏹️ Stopped capturing frames');

    // await _recorder.stop();
    // final base64String = _encodeAudioToBase64(_buffers);
    // _buffers.clear();

    // if (_recordedBytes == null || _recordedBytes!.isEmpty) {
    //   debugPrint('⚠️ No audio captured');
    //   return;
    // }

    if (_buffers.isEmpty || _channel == null) {
      debugPrint('⚠️ No audio captured to send');
      return;
    }

    final buffersToSend = _buffers.toList();
    _buffers.clear();

    final base64Audio = base64Encode(_encodeWav(buffersToSend));
    ;

    _channel!.sink.add(
      jsonEncode({
        'command': 'transcribe', // 서버와 약속된 오디오 처리 명령어
        'audio': base64Audio,
        'target_lang': 'en',
      }),
    );
    debugPrint('🛑 Sent stop command to backend');
  }

  Uint8List _encodeWav(List<Float32List> audioBuffers) {
    // const int sampleRate = 16000;
    int totalSamples = audioBuffers.fold(0, (sum, buf) => sum + buf.length);

    // PCM 데이터 (16-bit)
    final pcmData = Uint8List(totalSamples * 2);
    int offset = 0;
    for (final buffer in audioBuffers) {
      for (int i = 0; i < buffer.length; i++) {
        int sample = (buffer[i] * 32767).toInt();
        pcmData[offset++] = sample & 0xFF;
        pcmData[offset++] = (sample >> 8) & 0xFF;
      }
    }

    // WAV 헤더 생성
    final header = Uint8List(44);
    // "RIFF"
    header[0] = 0x52;
    header[1] = 0x49;
    header[2] = 0x46;
    header[3] = 0x46;
    // 파일 크기 - 8
    int fileSize = pcmData.length + 36;
    header[4] = fileSize & 0xFF;
    header[5] = (fileSize >> 8) & 0xFF;
    header[6] = (fileSize >> 16) & 0xFF;
    header[7] = (fileSize >> 24) & 0xFF;
    // "WAVE"
    header[8] = 0x57;
    header[9] = 0x41;
    header[10] = 0x56;
    header[11] = 0x45;
    // "fmt "
    header[12] = 0x66;
    header[13] = 0x6D;
    header[14] = 0x74;
    header[15] = 0x20;
    // Subchunk1Size = 16
    header[16] = 16;
    header[17] = 0;
    header[18] = 0;
    header[19] = 0;
    // AudioFormat = 1 (PCM)
    header[20] = 1;
    header[21] = 0;
    // NumChannels = 1 (mono)
    header[22] = 1;
    header[23] = 0;
    // SampleRate = 16000
    header[24] = 0x80;
    header[25] = 0x3E;
    header[26] = 0;
    header[27] = 0;
    // ByteRate = 32000
    header[28] = 0x80;
    header[29] = 0x7D;
    header[30] = 0;
    header[31] = 0;
    // BlockAlign = 2
    header[32] = 2;
    header[33] = 0;
    // BitsPerSample = 16
    header[34] = 16;
    header[35] = 0;
    // "data"
    header[36] = 0x64;
    header[37] = 0x61;
    header[38] = 0x74;
    header[39] = 0x61;
    // Subchunk2Size
    header[40] = pcmData.length & 0xFF;
    header[41] = (pcmData.length >> 8) & 0xFF;
    header[42] = (pcmData.length >> 16) & 0xFF;
    header[43] = (pcmData.length >> 24) & 0xFF;

    // 헤더 + PCM 데이터 합치기
    final wavData = Uint8List(header.length + pcmData.length);
    wavData.setAll(0, header);
    wavData.setAll(header.length, pcmData);
    return wavData;
  }

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
    // final screenSize = MediaQuery.of(context).size;
    final buttonSize = 200.0;

    // Calculate shadow radius based on audio level
    final baseRadius = 20.0;
    final maxRadius = 100.0;
    final shadowRadius = baseRadius + (_audioLevel * (maxRadius - baseRadius));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Status indicator
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
                        color: _connectionStatus == 'Connected'
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

                // Emotion display
                Text(
                  // _currentEmotion,
                  original['lang'] == null
                      ? ''
                      : '[${original['lang']!.toUpperCase()}] ${original['text']!}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 60),

                // Central circular button with audio-reactive glow
                // GestureDetector(
                //   onTap: () {
                //     if (_isTransmitting) {
                //       _stopTransmitting();
                //     } else {
                //       if (_channel != null) {
                //         _startTransmitting();
                //       }
                //     }
                //   },
                //   child: AnimatedContainer(
                //     duration: const Duration(milliseconds: 100),
                //     width: buttonSize,
                //     height: buttonSize,
                //     decoration: BoxDecoration(
                //       shape: BoxShape.circle,
                //       color: _isTransmitting ? Colors.red : Colors.blue,
                //       boxShadow: [
                //         BoxShadow(
                //           color: (_isTransmitting ? Colors.red : Colors.blue)
                //               .withOpacity(0.6),
                //           blurRadius: shadowRadius,
                //           spreadRadius: shadowRadius / 2,
                //         ),
                //       ],
                //     ),
                //     child: Icon(
                //       _isTransmitting ? Icons.stop : Icons.mic,
                //       color: Colors.white,
                //       size: 80,
                //     ),
                //   ),
                // ),
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
                    padding: EdgeInsets.all(buttonSize / 3),
                    backgroundColor: _isTransmitting ? Colors.red : Colors.blue,
                    shadowColor: (_isTransmitting ? Colors.red : Colors.blue)
                        .withOpacity(0.6),
                    elevation: shadowRadius / 2,
                  ),
                  child: Icon(
                    _isTransmitting ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 80,
                  ),
                ),

                const SizedBox(height: 20),

                // Audio level indicator
                if (_isTransmitting)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Audio Level: ${(_audioLevel * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 200,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: _audioLevel,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                Text(
                  translated['text'] == null ? '' : translated['text']!,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 40),
                // 콜렉팅 중에만 나오게
                // if (_isTransmitting)
                //   Container(
                //     margin: const EdgeInsets.only(top: 20),
                //     padding: const EdgeInsets.all(16),
                //     decoration: BoxDecoration(
                //       color: Colors.orange.withOpacity(0.3),
                //       borderRadius: BorderRadius.circular(12),
                //       border: Border.all(color: Colors.orange, width: 2),
                //     ),
                //     child: const Row(
                //       mainAxisSize: MainAxisSize.min,
                //       children: [
                //         SizedBox(
                //           width: 20,
                //           height: 20,
                //           child: CircularProgressIndicator(
                //             strokeWidth: 2,
                //             color: Colors.orange,
                //           ),
                //         ),
                //         SizedBox(width: 12),
                //         Text(
                //           'Collecting emotions...',
                //           style: TextStyle(
                //             color: Colors.orange,
                //             fontSize: 14,
                //             fontWeight: FontWeight.bold,
                //           ),
                //         ),
                //       ],
                //     ),
                //   ),
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
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _isTransmitting
                      ? 'Tap to stop detection'
                      : 'Tap to start detection',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
