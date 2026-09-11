import 'package:flutter/material.dart';
import 'package:rive/rive.dart' hide LinearGradient;
import '../services/websocket_service.dart';

class RiveAvatarWidget extends StatefulWidget {
  final AvatarState state;
  final double audioAmplitude; // 0.0 to 1.0

  const RiveAvatarWidget({
    super.key,
    required this.state,
    required this.audioAmplitude,
  });

  @override
  State<RiveAvatarWidget> createState() => _RiveAvatarWidgetState();
}

class _RiveAvatarWidgetState extends State<RiveAvatarWidget> {
  SMIBool? _isListeningInput;
  SMIBool? _isTalkingInput;
  SMINumber? _volumeInput;
  Artboard? _riveArtboard;
  bool _riveLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadRiveFile();
  }

  void _loadRiveFile() async {
    try {
      final data = await RiveFile.asset('assets/avatar.riv');
      final artboard = data.mainArtboard;
      var controller =
          StateMachineController.fromArtboard(artboard, 'AvatarState');
      if (controller != null) {
        artboard.addController(controller);
        _isListeningInput = controller.findInput<bool>('isListening') as SMIBool?;
        _isTalkingInput = controller.findInput<bool>('isTalking') as SMIBool?;
        _volumeInput = controller.findInput<double>('volume') as SMINumber?;
      }
      setState(() {
        _riveArtboard = artboard;
      });
    } catch (e) {
      // If assets/avatar.riv is not yet provided, fallback to rich built-in animation
      setState(() {
        _riveLoadFailed = true;
      });
    }
  }

  @override
  void didUpdateWidget(covariant RiveAvatarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_riveArtboard != null) {
      _isListeningInput?.value = widget.state == AvatarState.listening;
      _isTalkingInput?.value = widget.state == AvatarState.talking;
      _volumeInput?.value = widget.audioAmplitude * 100.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_riveArtboard != null && !_riveLoadFailed) {
      return Rive(artboard: _riveArtboard!);
    }

    // Built-in high-quality visual avatar fallback
    return _buildBuiltinAvatar(context);
  }

  Widget _buildBuiltinAvatar(BuildContext context) {
    final double mouthHeight =
        widget.state == AvatarState.talking ? 8.0 + (widget.audioAmplitude * 32.0) : 6.0;
    final Color glowColor = widget.state == AvatarState.listening
        ? const Color(0xFF4ADE80)
        : widget.state == AvatarState.talking
            ? const Color(0xFF60A5FA)
            : const Color(0xFFA78BFA);

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF818CF8), Color(0xFFC084FC)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: glowColor.withValues(alpha: 0.5),
              blurRadius: 30 + (widget.audioAmplitude * 25),
              spreadRadius: 6 + (widget.audioAmplitude * 10),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Eyes
            Positioned(
              top: 75,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildEye(widget.state == AvatarState.listening),
                  const SizedBox(width: 48),
                  _buildEye(widget.state == AvatarState.listening),
                ],
              ),
            ),
            // Cheeks
            Positioned(
              top: 118,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCheek(),
                  const SizedBox(width: 90),
                  _buildCheek(),
                ],
              ),
            ),
            // Mouth
            Positioned(
              top: 130,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 60),
                width: 38 + (widget.audioAmplitude * 14),
                height: mouthHeight,
                decoration: BoxDecoration(
                  color: const Color(0xFF3730A3),
                  borderRadius: BorderRadius.circular(mouthHeight / 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEye(bool isListening) {
    return Container(
      width: isListening ? 22 : 18,
      height: isListening ? 24 : 20,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1B4B),
        shape: BoxShape.circle,
      ),
      child: Align(
        alignment: Alignment.topRight,
        child: Container(
          margin: const EdgeInsets.all(3),
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildCheek() {
    return Container(
      width: 24,
      height: 14,
      decoration: BoxDecoration(
        color: const Color(0xFFF472B6).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(7),
      ),
    );
  }
}
