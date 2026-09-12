import 'dart:async';
import 'package:flutter/material.dart';
import '../config.dart';
import '../services/audio_stream_service.dart';
import '../services/network_guard.dart';
import '../services/websocket_service.dart';
import '../widgets/rive_avatar.dart';
import 'parent_view.dart';

class AvatarScreen extends StatefulWidget {
  const AvatarScreen({super.key});

  @override
  State<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends State<AvatarScreen> {
  late final AudioStreamService _audioService;
  late final WebSocketService _wsService;
  late final NetworkGuard _networkGuard;

  AvatarState _avatarState = AvatarState.idle;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  double _audioAmplitude = 0.0;
  String _liveSubtitle = '';
  StreamSubscription? _stateSub;
  StreamSubscription? _connSub;
  StreamSubscription? _ampSub;
  StreamSubscription? _wifiSub;
  StreamSubscription? _transSub;

  @override
  void initState() {
    super.initState();
    _audioService = AudioStreamService();
    _wsService = WebSocketService(audioService: _audioService);
    _networkGuard = NetworkGuard();

    _audioService.init();
    _networkGuard.init();

    _wifiSub = _networkGuard.onWifiChanged.listen((isWifi) {
      if (isWifi && _connectionStatus != ConnectionStatus.connected) {
        _wsService.connect(AppConfig.wsUrl);
      }
    });

    _stateSub = _wsService.onAvatarStateChanged.listen((state) {
      setState(() => _avatarState = state);
    });

    _connSub = _wsService.onStatusChanged.listen((status) {
      setState(() => _connectionStatus = status);
    });

    _ampSub = _audioService.onPlaybackAmplitude.listen((amp) {
      setState(() => _audioAmplitude = amp);
    });

    _transSub = _wsService.onTranscript.listen((text) {
      setState(() => _liveSubtitle = text);
    });

    // Auto connect
    _wsService.connect(AppConfig.wsUrl);
  }

  void _showParentPinDialog() {
    final TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: const Text('Parent Access',
              style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Enter PIN',
              labelStyle: TextStyle(color: Colors.white70),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim() == AppConfig.parentPin) {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ParentViewScreen()),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Incorrect PIN')),
                  );
                }
              },
              child: const Text('Open'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Stack(
          children: [
            // Hidden Parent trigger in top-right corner
            Positioned(
              top: 12,
              right: 12,
              child: GestureDetector(
                onLongPress: _showParentPinDialog,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_outline,
                    color: Colors.white.withValues(alpha: 0.2),
                    size: 18,
                  ),
                ),
              ),
            ),

            // Connection indicator in top-left (Tappable to retry)
            Positioned(
              top: 16,
              left: 16,
              child: GestureDetector(
                onTap: () {
                  _wsService.connect(AppConfig.wsUrl);
                },
                child: Container(
                  color: Colors.transparent,
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _connectionStatus == ConnectionStatus.connected
                              ? const Color(0xFF4ADE80)
                              : _connectionStatus == ConnectionStatus.connecting
                                  ? Colors.amber
                                  : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _connectionStatus == ConnectionStatus.connected
                            ? 'Anvi is ready'
                            : _connectionStatus == ConnectionStatus.connecting
                                ? 'Connecting...'
                                : 'Offline (Tap to retry)',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Main Content: Avatar + Hold-to-Talk Button
            Column(
              children: [
                const Spacer(flex: 1),

                // Avatar
                Expanded(
                  flex: 5,
                  child: Center(
                    child: RiveAvatarWidget(
                      state: _avatarState,
                      audioAmplitude: _audioAmplitude,
                    ),
                  ),
                ),

                // Subtitle/Prompt text if any
                if (_liveSubtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 8),
                    child: Text(
                      _liveSubtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                const SizedBox(height: 16),

                // Status text
                Text(
                  _avatarState == AvatarState.listening
                      ? 'Listening to you... (Tap to Pause)'
                      : _avatarState == AvatarState.talking
                          ? 'Anvi is speaking...'
                          : 'Tap to start talking to Anvi',
                  style: TextStyle(
                    color: _avatarState == AvatarState.listening
                        ? const Color(0xFF4ADE80)
                        : Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 24),

                // Tap to Start / Tap to Stop Button
                GestureDetector(
                  onTap: () => _wsService.toggleListening(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _avatarState == AvatarState.listening ? 96 : 84,
                    height: _avatarState == AvatarState.listening ? 96 : 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _avatarState == AvatarState.listening
                            ? [
                                const Color(0xFF22C55E),
                                const Color(0xFF16A34A)
                              ]
                            : [
                                const Color(0xFF6366F1),
                                const Color(0xFF4F46E5)
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_avatarState == AvatarState.listening
                                  ? const Color(0xFF22C55E)
                                  : const Color(0xFF6366F1))
                              .withValues(alpha: 0.5),
                          blurRadius: 24,
                          spreadRadius: _avatarState == AvatarState.listening ? 6 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      _avatarState == AvatarState.listening
                          ? Icons.mic
                          : Icons.mic_none,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ),

                const Spacer(flex: 1),
              ],
            ),


          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _connSub?.cancel();
    _ampSub?.cancel();
    _wifiSub?.cancel();
    _transSub?.cancel();
    _audioService.dispose();
    _wsService.dispose();
    _networkGuard.dispose();
    super.dispose();
  }
}
