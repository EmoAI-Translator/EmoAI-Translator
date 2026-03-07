import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'audio_control.dart';

class DebugPanel extends StatefulWidget {
  const DebugPanel({
    super.key,
    this.serverUrl,
    this.connectionStatus,
    this.lastSentPacket,
    this.lastReceivedPacket,
    this.internalVars,
    this.onServerUrlChanged,
  });

  // 외부 코드 수정 없이도 사용할 수 있도록 전부 optional
  final String? serverUrl;
  final int? connectionStatus; // 0=connected, 1=disconnected, 2=error
  final String? lastSentPacket;
  final String? lastReceivedPacket;
  final Map<String, Object?>? internalVars;
  final Function(String)? onServerUrlChanged;

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel> {
  Timer? _ticker;
  Duration _silenceElapsed = Duration.zero;
  static const Duration _tick = Duration(milliseconds: 200);
  static const double _silenceThreshold = 0.1;
  late TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(_tick, (_) => _updateSilenceClock());
    _urlController = TextEditingController(text: widget.serverUrl ?? '');
  }

  void _updateSilenceClock() {
    if (!mounted) return;
    final audio = Provider.of<AudioControl?>(context, listen: false);
    if (audio == null || !audio.isRecording) {
      if (_silenceElapsed != Duration.zero) {
        setState(() {
          _silenceElapsed = Duration.zero;
        });
      }
      return;
    }

    if (audio.audioLevelNotifier.value < _silenceThreshold) {
      setState(() {
        _silenceElapsed += _tick;
      });
    } else if (_silenceElapsed != Duration.zero) {
      setState(() {
        _silenceElapsed = Duration.zero;
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  String _connLabel(int? status) {
    switch (status) {
      case 0:
        return 'Connected';
      case 1:
        return 'Disconnected';
      case 2:
        return 'Error';
      default:
        return 'N/A';
    }
  }

  String _fmtDuration(Duration d) {
    final sec = d.inMilliseconds / 1000.0;
    return '${sec.toStringAsFixed(1)}s';
  }

  String _trimPacket(String? packet) {
    if (packet == null || packet.isEmpty) return 'N/A';
    const maxLen = 220;
    if (packet.length <= maxLen) return packet;
    return '${packet.substring(0, maxLen)}...';
  }

  @override
  Widget build(BuildContext context) {
    final audio = Provider.of<AudioControl?>(context);
    final server = widget.serverUrl ?? 'N/A';
    final uri = Uri.tryParse(server);
    final serverIp = uri?.host.isNotEmpty == true ? uri!.host : 'N/A';

    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 380,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DefaultTextStyle(
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontFamily: 'monospace',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Debug Panel',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _kv('Server URL', server),
                _kv('Server IP', serverIp),
                _kv('Connection', _connLabel(widget.connectionStatus)),
                const SizedBox(height: 8),
                const Divider(height: 8),
                const SizedBox(height: 8),
                const Text(
                  'Change Server URL',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    hintText: 'e.g., ws://192.168.1.100:8000/ws/speech',
                    hintStyle: const TextStyle(fontSize: 10),
                  ),
                  style: const TextStyle(fontSize: 10),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_urlController.text.isNotEmpty &&
                          widget.onServerUrlChanged != null) {
                        widget.onServerUrlChanged!(_urlController.text);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Server URL updated'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                    child: const Text('Apply', style: TextStyle(fontSize: 11)),
                  ),
                ),
                const Divider(height: 16),
                const Divider(height: 16),
                _kv(
                  'Silence Elapsed',
                  audio == null ? 'N/A' : _fmtDuration(_silenceElapsed),
                ),
                _kv(
                  'Recording',
                  audio == null ? 'N/A' : audio.isRecording.toString(),
                ),
                _kv(
                  'Audio Level',
                  audio == null
                      ? 'N/A'
                      : audio.audioLevelNotifier.value.toStringAsFixed(3),
                ),
                _kv('Speaker1', audio?.getSpeaker1 ?? 'N/A'),
                _kv('Speaker2', audio?.getSpeaker2 ?? 'N/A'),
                _kv('Platform', defaultTargetPlatform.name),
                const Divider(height: 16),
                _kv('Sent Packet', _trimPacket(widget.lastSentPacket)),
                _kv('Recv Packet', _trimPacket(widget.lastReceivedPacket)),
                if (widget.internalVars != null &&
                    widget.internalVars!.isNotEmpty) ...[
                  const Divider(height: 16),
                  const Text(
                    'Internal Vars',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  for (final entry in widget.internalVars!.entries)
                    _kv(entry.key, '${entry.value}'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text('$key:')),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
