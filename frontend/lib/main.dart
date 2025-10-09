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
  WebSocketChannel? _channel;
  
  bool _isCapturing = false;
  bool _isCollecting = false;
  int _frameCount = 0;
  String _currentEmotion = 'Unknown';
  String _connectionStatus = 'Disconnected';
  Map<String, dynamic>? _summaryData;

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
        }
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
      
      setState(() {});
      debugPrint('✅ Camera initialized');
    } catch (e) {
      debugPrint('❌ Camera initialization error: $e');
    }
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
    
    debugPrint('▶️ Started capturing frames');
  }

  void _stopCapture() {
    _captureTimer?.cancel();
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
    _channel?.sink.close();
    _stream?.getTracks().forEach((track) => track.stop());
    _videoElement?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Emotion Detection'),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: targetWidth.toDouble(),
                  height: targetHeight.toDouble(),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _connectionStatus == 'Connected' 
                          ? Colors.green 
                          : Colors.red,
                      width: 3,
                    ),
                  ),
                  child: _videoElement != null
                      ? HtmlElementView(viewType: 'camera-preview')
                      : const Center(child: CircularProgressIndicator()),
                ),
                const SizedBox(height: 20),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _connectionStatus == 'Connected' 
                          ? Icons.check_circle 
                          : Icons.error,
                      color: _connectionStatus == 'Connected' 
                          ? Colors.green 
                          : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Status: $_connectionStatus',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                
                const SizedBox(height: 10),
                
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text(
                          'Current Emotion',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _currentEmotion,
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 10),
                
                if (_isCollecting)
                  Card(
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(width: 16),
                          Text(
                            'Collecting emotions...',
                            style: TextStyle(color: Colors.orange.shade900),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                if (_summaryData != null)
                  Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Summary',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(_summaryData.toString()),
                        ],
                      ),
                    ),
                  ),
                
                const SizedBox(height: 10),
                Text('Frames Sent: $_frameCount'),
                
                const SizedBox(height: 20),
                
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _isCapturing ? null : _startCapture,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Detection'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isCapturing ? _stopCapture : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop Detection'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade100,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isCapturing && !_isCollecting
                          ? () => _startCollection(5)
                          : null,
                      icon: const Icon(Icons.assessment),
                      label: const Text('Collect 5s'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade100,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _isCapturing && !_isCollecting
                          ? () => _startCollection(10)
                          : null,
                      icon: const Icon(Icons.analytics),
                      label: const Text('Collect 10s'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade100,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}