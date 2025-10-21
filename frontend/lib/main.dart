import 'package:flutter/material.dart';

import 'dart:async'; 
import 'dart:convert';
import 'dart:html' as html;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:ui_web' as ui_web;

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
  html.VideoElement? _videoElement;
  html.CanvasElement? _canvasElement;
  html.MediaStream? _stream;
  Timer? _captureTimer;
  Timer? _audioAnalyzerTimer;
  WebSocketChannel? _channel;

  // Audio analysis
  html.AudioContext? _audioContext;
  html.AnalyserNode? _analyserNode;
  html.MediaStreamAudioSourceNode? _audioSource;

  bool _isCapturing = false;
  bool _isCollecting = false;
  int _frameCount = 0;
  String _currentEmotion = 'Unknown';
  String _connectionStatus = 'Disconnected';
  Map<String, dynamic>? _summaryData;
  double _audioLevel = 0.0; // 0.0 ~ 1.0

  static const int targetWidth = 640;
  static const int targetHeight = 480;
  static const int fps = 5;
  static const int captureIntervalMs = 1000 ~/ fps;
  
  // TODO: connect to backend server
  static const String wsUrl = 'ws://localhost:8000/ws/emotion';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _connectWebSocket();
  }

  Future<void> _initializeCamera() async {
    try {
      _stream = await html.window.navigator.mediaDevices!.getUserMedia({
        'video': {
          'width': targetWidth,
          'height': targetHeight,
        },
        'audio': true,
      });

      _videoElement = html.VideoElement()
        ..autoplay = true
        ..srcObject = _stream
        ..width = targetWidth
        ..height = targetHeight //TODO: modifiy it to screen in future.
        ..style.border = '2px solid #4CAF50' 
        ..style.objectFit = 'cover'
        ..style.display = 'block';

    ui_web.platformViewRegistry.registerViewFactory(
      'camera-preview',
      (int viewId) => _videoElement!,
    );

      _canvasElement = html.CanvasElement(
        width: targetWidth,
        height: targetHeight,
      );

      // Controlling inside the flutter
      //html.document.body!.append(_videoElement!);

      // Initialize audio context for volume analysis
      _initializeAudioAnalyzer();

      setState(() {});
      debugPrint('✅ Camera initialized');
    } catch (e) {
      debugPrint('❌ Camera initialization error: $e');
    }
  }

  void _initializeAudioAnalyzer() {
    try {
      _audioContext = html.AudioContext();
      _analyserNode = _audioContext!.createAnalyser();
      _analyserNode!.fftSize = 256;

      _audioSource = _audioContext!.createMediaStreamSource(_stream!);
      _audioSource!.connectNode(_analyserNode!);

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

    final dataArray = html.Uint8List(_analyserNode!.frequencyBinCount);
    _analyserNode!.getByteFrequencyData(dataArray);

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
      _frameCount = 0;
    });

    _captureTimer = Timer.periodic(
      Duration(milliseconds: captureIntervalMs),
      (timer) => _captureAndSendFrame(),
    );

    _startAudioAnalysis();

    debugPrint('▶️ Started capturing frames');
  }

  void _stopCapture() {
    _captureTimer?.cancel();
    _stopAudioAnalysis();
    setState(() {
      _isCapturing = false;
    });
    debugPrint('⏹️ Stopped capturing frames');
  }

  void _captureAndSendFrame() {
    if (_videoElement == null || _canvasElement == null || _channel == null) return;

    try {
      final context = _canvasElement!.context2D;
      
      context.drawImageScaled(
        _videoElement!,
        0,
        0,
        targetWidth,
        targetHeight,
      );

      final dataUrl = _canvasElement!.toDataUrl('image/jpeg', 0.8);
      final base64Data = dataUrl.split(',')[1];

      final message = jsonEncode({
        'command': 'detect',
        'frame': base64Data,
      });

      _channel!.sink.add(message);

      setState(() {
        _frameCount++;
      });
      
    } catch (e) {
      debugPrint('❌ Frame capture error: $e');
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
    _captureTimer?.cancel();
    _audioAnalyzerTimer?.cancel();
    _channel?.sink.close();
    _audioSource?.disconnect();
    _audioContext?.close();
    _stream?.getTracks().forEach((track) => track.stop());
    _videoElement?.remove();
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
          // Video background
          if (_videoElement != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.3,
                child: HtmlElementView(viewType: 'camera-preview'),
              ),
            ),

          // Main content
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Status indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

                // Frame count
                if (_isCapturing)
                  Text(
                    'Frames: $_frameCount',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),

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
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}