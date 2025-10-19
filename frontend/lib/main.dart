import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;
import 'AVProcess.dart';

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
  late final AVProcess _av;
  String _emotion = 'Neutral';
  String _status = 'Disconnected';
  web.HTMLVideoElement? _video;

  String originalText = '';
  String translatedText = '';
  String originalLanguage = '';
  String translatedLanguage = '';

  @override
  void initState() {
    super.initState();

    _av = AVProcess(
      onSpeechTranslated: (original, translated, originalLang, translatedLang) {
        setState(() {
          originalText = original;
          translatedText = translated;
          originalLanguage = originalLang;
          translatedLanguage = translatedLang;
        });
      },
      onEmotionReceived: (e) => setState(() => _emotion = e),
      onVideoStatusChanged: (s) => setState(() => _status = s),
    );

    _init();
  }

  Future<void> _init() async {
    await _av.initialize();
    await _av.connect();
    // await Future.delayed(Duration(milliseconds: 1000)); // 연결 대기

    // Register video element for Flutter Web rendering
    _video = _av.getVideoElement();
    if (_video != null) {
      ui_web.platformViewRegistry.registerViewFactory(
        'camera-preview',
        (int _) => _video!,
      );
    }
    setState(() {});
  }

  @override
  void dispose() {
    _av.dispose();
    super.dispose();
  }

  void _toggleCapture() {
    if (_av.isCapturing()) {
      _av.stopCapture();
    } else {
      _av.startCapture();
    }
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
                  width: _av.getTargetWidth().toDouble(),
                  height: _av.getTargetHeight().toDouble(),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _status == 'Connected' ? Colors.green : Colors.red,
                      width: 3,
                    ),
                  ),
                  child: _video != null
                      ? HtmlElementView(viewType: 'camera-preview')
                      : const Center(child: CircularProgressIndicator()),
                ),
                const SizedBox(height: 20),

                // Row(
                //   mainAxisAlignment: MainAxisAlignment.center,
                //   children: [
                //     Icon(
                //       _connectionStatus == 'Connected'
                //           ? Icons.check_circle
                //           : Icons.error,
                //       color: _connectionStatus == 'Connected'
                //           ? Colors.green
                //           : Colors.red,
                //     ),
                //     const SizedBox(width: 8),
                //     Text(
                //       'Status: $_connectionStatus',
                //       style: Theme.of(context).textTheme.titleMedium,
                //     ),_toggleCapture
                //   ],
                // ),
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
                          _emotion,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // if (_isCollecting)
                //   Card(
                //     color: Colors.orange.shade50,
                //     child: Padding(
                //       padding: const EdgeInsets.all(16.0),
                //       child: Row(
                //         mainAxisSize: MainAxisSize.min,
                //         children: [
                //           const CircularProgressIndicator(),
                //           const SizedBox(width: 16),
                //           Text(
                //             'Collecting emotions...',
                //             style: TextStyle(color: Colors.orange.shade900),
                //           ),
                //         ],
                //       ),
                //     ),
                //   ),

                // if (_summaryData != null)
                //   Card(
                //     color: Colors.green.shade50,
                //     child: Padding(
                //       padding: const EdgeInsets.all(16.0),
                //       child: Column(
                //         crossAxisAlignment: CrossAxisAlignment.start,
                //         children: [
                //           Text(
                //             'Summary',
                //             style: Theme.of(context).textTheme.titleMedium
                //                 ?.copyWith(fontWeight: FontWeight.bold),
                //           ),
                //           const SizedBox(height: 8),
                //           Text(_summaryData.toString()),
                //         ],
                //       ),
                //     ),
                //   ),

                // const SizedBox(height: 10),
                // Text('Frames Sent: $_frameCount'),

                // const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _toggleCapture,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start/Stop Detection'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade100,
                      ),
                    ),
                    // ElevatedButton.icon(
                    //   onPressed: _av.isCapturing() && !_isCollecting
                    //       ? () => _startCollection(5)
                    //       : null,
                    //   icon: const Icon(Icons.assessment),
                    //   label: const Text('Collect 5s'),
                    //   style: ElevatedButton.styleFrom(
                    //     backgroundColor: Colors.orange.shade100,
                    //   ),
                    // ),
                    // ElevatedButton.icon(
                    //   onPressed: _av.isCapturing() && !_isCollecting
                    //       ? () => _startCollection(10)
                    //       : null,
                    //   icon: const Icon(Icons.analytics),
                    //   label: const Text('Collect 10s'),
                    //   style: ElevatedButton.styleFrom(
                    //     backgroundColor: Colors.orange.shade100,
                    //   ),
                    // ),
                  ],
                ),
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
                          originalText,
                          style: TextStyle(color: Colors.orange.shade900),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
