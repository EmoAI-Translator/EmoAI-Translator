import 'dart:js_interop';

import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:ui_web' as ui_web;
import 'dart:typed_data';

import 'dart:js_util' as js_util;

void main() {
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
  web.MediaStream? _stream;
  Timer? _audioAnalyzerTimer;
  WebSocketChannel? _channel;

  // Audio analysis
  web.AudioContext? _audioContext;
  web.AnalyserNode? _analyserNode;
  web.MediaStreamAudioSourceNode? _audioSource;

  bool _isCapturing = false;
  bool _isCollecting = false;
  String _currentEmotion = 'Unknown';
  String _connectionStatus = 'Disconnected';
  Map<String, dynamic>? _summaryData;
  double _audioLevel = 0.0; // 0.0 ~ 1.0

  // TODO: connect to backend server
  static const String wsUrl = 'ws://localhost:8000/ws/emotion';

  @override
  void initState() {
    super.initState();
    _initializeAudio();
    _connectWebSocket();
  }

  Future<void> _initializeAudio() async {
    final constraints = web.MediaStreamConstraints(audio: true.toJS);
    try {
      // 1️⃣ Promise → Future 변환
      final jsPromise = web.window.navigator.mediaDevices!.getUserMedia(
        constraints,
      );
      _stream = await js_util.promiseToFuture(jsPromise);

      // Initialize audio context for volume analysis
      _initializeAudioAnalyzer();

      setState(() {});
      debugPrint('✅ Audio initialized');
    } catch (e) {
      debugPrint('❌ Audio initialization error: $e');
    }
  }

  void _initializeAudioAnalyzer() {
    try {
      _audioContext = web.AudioContext();
      _analyserNode = _audioContext!.createAnalyser();
      _analyserNode!.fftSize = 256;

      _audioSource = _audioContext!.createMediaStreamSource(_stream!);
      _audioSource!.connect(_analyserNode!);

      debugPrint('✅ Audio analyzer initialized');
    } catch (e) {
      debugPrint('❌ Audio analyzer initialization error: $e');
    }
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

    // Calculate average volume
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

  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      final status = data['status'];
      final type = data['type'];

      if (status == 'success' && type == 'realtime') {
        setState(() {
          _currentEmotion = data['emotion'] ?? 'Unknown';
          _isCollecting = data['collecting'] ?? false;
        });
      } else if (status == 'started' && type == 'collection') {
        debugPrint('📊 Started collecting for ${data['duration']} seconds');
      } else if (status == 'success' && type == 'summary') {
        setState(() {
          _summaryData = data['data'];
          _isCollecting = false;
        });
        debugPrint('📈 Summary received: $_summaryData');
      } else if (status == 'error') {
        debugPrint('❌ Backend error: ${data['message']}');
      }
    } catch (e) {
      debugPrint('❌ Message parsing error: $e');
    }
  }

  void _startCapture() {
    if (_isCapturing || _channel == null) return;

    setState(() {
      _isCapturing = true;
    });

    _startAudioAnalysis();

    debugPrint('▶️ Started capturing frames');
  }

  void _stopCapture() {
    _stopAudioAnalysis();
    setState(() {
      _isCapturing = false;
    });
    debugPrint('⏹️ Stopped capturing frames');

    if (_channel != null) {
      final message = jsonEncode({'command': 'stop'});
      _channel!.sink.add(message);
      debugPrint('🛑 Sent stop command to backend');
    }
  }

  void _startCollection(int duration) {
    if (_channel == null) return;

    final message = jsonEncode({
      'command': 'start_collect',
      'duration': duration,
    });

    _channel!.sink.add(message);

    setState(() {
      _summaryData = null;
    });

    debugPrint('📊 Requested emotion collection for $duration seconds');
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
    final screenSize = MediaQuery.of(context).size;
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
                  _currentEmotion,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 60),

                // Central circular button with audio-reactive glow
                GestureDetector(
                  onTap: () {
                    if (_isCapturing) {
                      _stopCapture();
                    } else {
                      if (_channel != null) {
                        _startCapture();
                      }
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: buttonSize,
                    height: buttonSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isCapturing ? Colors.red : Colors.blue,
                      boxShadow: [
                        BoxShadow(
                          color: (_isCapturing ? Colors.red : Colors.blue)
                              .withOpacity(0.6),
                          blurRadius: shadowRadius,
                          spreadRadius: shadowRadius / 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isCapturing ? Icons.stop : Icons.mic,
                      color: Colors.white,
                      size: 80,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Audio level indicator
                if (_isCapturing)
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

                const SizedBox(height: 40),
                // Collection status
                if (_isCollecting)
                  Container(
                    margin: const EdgeInsets.only(top: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange, width: 2),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.orange,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Collecting emotions...',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _isCapturing
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
