import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:provider/provider.dart';
import 'audio_control.dart';
// import 'ip.dart';

void main() {
  // debugPrint("hi");
  runApp(const MyApp());
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
      home: ChangeNotifierProvider<AudioControl>(
        create: (context) => AudioControl.create(),
        child: const EmotionDetectionPage(),
      ),
    );
  }
}

class EmotionDetectionPage extends StatefulWidget {
  const EmotionDetectionPage({super.key});

  @override
  State<EmotionDetectionPage> createState() => _EmotionDetectionPageState();
}

class _EmotionDetectionPageState extends State<EmotionDetectionPage> {
  late AudioControl audio;

  //connect to backend server
  static String wsUrl = 'wss://api.emoai.us/ws/speech';
  WebSocketChannel? _channel;

  bool _isRecording = false;
  String _connectionStatus = 'Disconnected';
  double _audioLevel = 0.0; // 0.0 ~ 1.0
  bool recorderSet = false;

  //for frontend
  List<List<String>> _speakerText = [[], []];
  bool _isInitialstate = true;
  List<String> _speakerLanguage = ['ko', 'en'];
  List<String> _speakerEmotion = ['neu', 'neu'];

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
    _initializeAudio();
    _connectWebSocket();
    debugPrint('Audio stream initialized successfully');
  }

  void _initializeAudio() {
    audio = Provider.of<AudioControl>(context, listen: false);
    try {
      audio.requestPermission();
    } catch (e) {
      debugPrint('❌ Error accessing microphone: $e');
      return;
    }
    audio.speaker1 = 'ko';
    audio.speaker2 = 'en';

    //   audio.setOnAudioDataReady((audioJson) {
    //     if (_channel != null) {
    //       _channel?.sink.add(audioJson);
    //     }
    //   });

    //   audio.setOnRecordingStateChanged((isRecording) {
    //     setState(() {
    //       _isRecording = isRecording;
    //       if (!isRecording) _isInitialstate = false;
    //     });
    //   });
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
        // debugPrint('✅ Message from backend: $data');
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
            audio.playVoice(audioB64);
          }

          if (speaker == 'Speaker 1') {
            _speakerText[0].add("${translated['text'] ?? ''}");
            setState(() {
              _speakerLanguage[1] = translated['lang'] ?? 'ko';
              _speakerEmotion[0] = emotion;
            });
          } else {
            _speakerText[1].add("${translated['text'] ?? ''}");
            setState(() {
              _speakerEmotion[1] = emotion;
            });
          }
        });

        debugPrint(
          'Speaker: $speaker, Original: ${original['text']}, Translated: ${translated['text']}, Emotion: $emotion',
        );
      } else if (status == 'error') {
        debugPrint('Message from backend error: ${data['message']}');
      }
    } catch (e) {
      debugPrint('Message parsing error: $e');
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || _channel == null) return;
    setState(() {
      _isRecording = true;
    });
    debugPrint('▶️ Started recording');

    try {
      final String? audioJson = await audio.startRecording();
      if (audioJson != null && _channel != null) {
        debugPrint('Sending audio data to backend...');
        _channel!.sink.add(audioJson);
      }
    } catch (e) {
      debugPrint('Recording error: $e');
    } finally {
      // setState(() {
      //   _isRecording = false;
      // });
    }
  }

  // Formet to send to backend
  // {
  //     "command": "transcribe",
  //     "audio": "<base64_encoded_audio_string>",
  //     "target_lang": "en"
  // }

  Future<void> _stopRecording() async {
    await audio.stopRecording();
    setState(() {
      _isRecording = false;
    });
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }
  ///////////////////////////////////////////////////////////////////
  /// UI Area
  ///////////////////////////////////////////////////////////////////

  Widget _desktopLayout() {
    final height = MediaQuery.of(context).size.height;
    final buttonSize = 200.0;

    // Calculate shadow radius based on audio level
    final baseRadius = 20.0;
    final maxRadius = 100.0;
    final shadowRadius =
        baseRadius + (_audioLevel * (maxRadius - baseRadius) * 2);

    return Scaffold(
      // backgroundColor: Colors.black,
      backgroundColor: Colors.blue[50],
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
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _languageButton('ko', 'Korean'),
                                const SizedBox(width: 8),
                                _languageButton('en', 'English'),
                                const SizedBox(width: 8),
                                _languageButton('zh', 'Chinese'),
                                const SizedBox(width: 8),
                                _languageButton('ja', 'Japanese'),
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
                                      // color: Colors.black54,
                                      color: Colors.green[100],
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
                                            // color: Colors.white,
                                            color: Colors.black,

                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 40),
                                  const SizedBox(height: 60),
                                  _micButton(height),
                                  const SizedBox(height: 20),
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
                              // color: Colors.black54,
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isInitialstate)
                  Container(
                    width: MediaQuery.of(context).size.width * 0.4,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _textArea(0),
                        const SizedBox(height: 16),
                        _textArea(1),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Text(
            _isRecording ? 'Tap to stop detection' : 'Tap to start detection',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _mobileLayout() {
    final _height = MediaQuery.of(context).size.height;
    final _width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.blue[50],
      body: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _textArea(0),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        // Main content
                        Center(
                          child: Column(
                            children: [
                              const SizedBox(height: 10),

                              Center(
                                child: SizedBox(
                                  height: 20,
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    children: [
                                      _languageButton('ko', 'Korean'),
                                      const SizedBox(width: 8),
                                      _languageButton('en', 'English'),
                                      const SizedBox(width: 8),
                                      _languageButton('zh', 'Chinese'),
                                      const SizedBox(width: 8),
                                      _languageButton('ja', 'Japanese'),
                                    ],
                                  ),
                                ),
                              ),
                              // Status indicator
                              Expanded(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    SizedBox(
                                      height: 10,
                                      // width: _width * 0.8,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Container(
                                          width: 4,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color:
                                                _connectionStatus == 'Connected'
                                                ? Colors.green
                                                : Colors.red,
                                          ),
                                        ),
                                      ),
                                    ),

                                    _micButton(_height),

                                    const SizedBox(height: 10),

                                    // const SizedBox(height: 10),
                                    // const SizedBox(height: 40),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Bottom info panel
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _textArea(1),
          ],
        ),
      ),
    );
  }

  Widget _micButton(double height) {
    final audioControl = Provider.of<AudioControl>(context, listen: false);
    final buttonSize = height * 0.2;
    final baseRadius = buttonSize * 0.1;
    final maxRadius = buttonSize * 0.5;
    return ValueListenableBuilder<double>(
      valueListenable: audioControl.audioLevelNotifier,
      builder: (context, audioLevel, child) {
        final shadowRadius =
            baseRadius + (audioLevel * (maxRadius - baseRadius) * 2);

        return Stack(
          alignment: Alignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording ? Colors.red : Colors.blue,
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording ? Colors.red : Colors.blue)
                        .withOpacity(0.8),
                    blurRadius: shadowRadius,
                    spreadRadius: shadowRadius / 2,
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (_isRecording) {
                  _stopRecording();
                } else {
                  if (_channel != null) {
                    _startRecording();
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.all(buttonSize / 3),
                backgroundColor: _isRecording ? Colors.red : Colors.blue,
                shadowColor: (_isRecording ? Colors.red : Colors.blue)
                    .withOpacity(0.6),
                elevation: shadowRadius / 2,
              ),
              child: Icon(
                _isRecording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 80,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _languageButton(String languageCode, String label) {
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _speakerLanguage[0] = languageCode;
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: _speakerLanguage[0] == languageCode
            ? Colors.blue
            : Colors.grey,
      ),
      child: Text(label, style: const TextStyle(color: Colors.white)),
    );
  }

  Color _getEmotionColor(String? emotion, double _opacityFactor) {
    if (emotion == 'hap') return Colors.yellow.withOpacity(_opacityFactor);
    if (emotion == 'sad') return Colors.grey.withOpacity(_opacityFactor);
    if (emotion == 'ang') return Colors.red.withOpacity(_opacityFactor);
    return Colors.blue.withOpacity(_opacityFactor);
  }

  Widget _textArea(int speakerNo) {
    // if (!_isInitialstate) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: _getEmotionColor(_speakerEmotion[speakerNo], 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _speakerText[speakerNo].length,
          itemBuilder: (context, index) {
            final message = _speakerText[speakerNo][index];
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getEmotionColor(_speakerEmotion[speakerNo], 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            );
          },
        ),
      ),
    );
    // }
    // return SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final _width = MediaQuery.of(context).size.width;

    if (_width < 800) {
      return _mobileLayout();
    } else {
      return _desktopLayout();
    }
  }
}
