import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'audio_stream_service.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

enum AvatarState {
  idle,
  listening,
  talking,
}

class WebSocketService {
  final AudioStreamService audioService;
  WebSocketChannel? _channel;
  StreamSubscription? _wsSubscription;
  StreamSubscription? _audioRecordSubscription;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  AvatarState _avatarState = AvatarState.idle;

  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<AvatarState> _avatarStateController =
      StreamController<AvatarState>.broadcast();
  final StreamController<String> _transcriptController =
      StreamController<String>.broadcast();

  Stream<ConnectionStatus> get onStatusChanged => _statusController.stream;
  Stream<AvatarState> get onAvatarStateChanged => _avatarStateController.stream;
  Stream<String> get onTranscript => _transcriptController.stream;

  ConnectionStatus get status => _status;
  AvatarState get avatarState => _avatarState;

  WebSocketService({required this.audioService});

  String? _lastWsUrl;
  Timer? _reconnectTimer;

  /// Connect to the Python Relay server WebSocket
  Future<void> connect(String wsUrl) async {
    _lastWsUrl = wsUrl;
    if (_status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting) {
      return;
    }

    _setStatus(ConnectionStatus.connecting);

    try {
      final uri = Uri.parse(wsUrl);
      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      // Listen for incoming messages from backend
      _wsSubscription = _channel!.stream.listen(
        _handleIncomingMessage,
        onError: (error) {
          _setStatus(ConnectionStatus.error);
          _setAvatarState(AvatarState.idle);
          _scheduleReconnect();
        },
        onDone: () {
          _setStatus(ConnectionStatus.disconnected);
          _setAvatarState(AvatarState.idle);
          _scheduleReconnect();
        },
      );

      // Listen for recorded mic audio frames from AudioStreamService
      _audioRecordSubscription =
          audioService.onAudioRecorded.listen((Uint8List pcmChunk) {
        if (_status == ConnectionStatus.connected) {
          _channel?.sink.add(pcmChunk);
        }
      });
    } catch (e) {
      _setStatus(ConnectionStatus.error);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_status != ConnectionStatus.connected && _lastWsUrl != null) {
        connect(_lastWsUrl!);
      }
    });
  }

  void _handleIncomingMessage(dynamic message) {
    if (message is Uint8List) {
      // Received raw PCM audio chunk from Gemini Live
      _setAvatarState(AvatarState.talking);
      audioService.playAudioChunk(message);
    } else if (message is List<int>) {
      final bytes = Uint8List.fromList(message);
      _setAvatarState(AvatarState.talking);
      audioService.playAudioChunk(bytes);
    } else if (message is String) {
      try {
        final Map<String, dynamic> data = jsonDecode(message);
        final String? type = data['type'];

        if (type == 'ping') {
          // Server keepalive — ignore silently
        } else if (type == 'status' && data['status'] == 'ready') {
          _setStatus(ConnectionStatus.connected);
          _setAvatarState(AvatarState.idle);
        } else if (type == 'interrupted') {
          audioService.stopPlayback();
          _setAvatarState(AvatarState.idle);
        } else if (type == 'turn_complete') {
          _setAvatarState(AvatarState.idle);
        } else if (type == 'transcript') {
          final text = data['text'] ?? '';
          _transcriptController.add(text);
        }
      } catch (e) {
        // Ignored
      }
    }
  }

  /// Toggle continuous listening mode (Tap to Start / Tap to Stop)
  Future<void> toggleListening() async {
    if (_status != ConnectionStatus.connected) return;

    if (audioService.isRecording) {
      // User tapped to Stop/Pause
      await audioService.stopRecording();
      _sendJson({'type': 'end_of_turn'});
      _setAvatarState(AvatarState.idle);
    } else {
      // User tapped to Start continuous voice call
      await audioService.stopPlayback();
      _setAvatarState(AvatarState.listening);
      await audioService.startRecording();
    }
  }

  /// Start recording (for tap to start)
  Future<void> startListening() async {
    if (_status != ConnectionStatus.connected || audioService.isRecording) return;
    await audioService.stopPlayback();
    _setAvatarState(AvatarState.listening);
    await audioService.startRecording();
  }

  /// Stop recording (for tap to stop)
  Future<void> stopListening() async {
    if (!audioService.isRecording) return;
    await audioService.stopRecording();
    _sendJson({'type': 'end_of_turn'});
    _setAvatarState(AvatarState.idle);
  }

  /// Backward compatible hold methods
  Future<void> onHoldStart() async => startListening();
  Future<void> onHoldStop() async => stopListening();

  void _sendJson(Map<String, dynamic> jsonMap) {
    if (_channel != null && _status == ConnectionStatus.connected) {
      _channel!.sink.add(jsonEncode(jsonMap));
    }
  }

  void _setStatus(ConnectionStatus s) {
    _status = s;
    _statusController.add(s);
  }

  void _setAvatarState(AvatarState s) {
    _avatarState = s;
    _avatarStateController.add(s);
  }

  Future<void> disconnect() async {
    await audioService.stopRecording();
    await audioService.stopPlayback();
    await _audioRecordSubscription?.cancel();
    await _wsSubscription?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setStatus(ConnectionStatus.disconnected);
    _setAvatarState(AvatarState.idle);
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _avatarStateController.close();
    _transcriptController.close();
  }
}
