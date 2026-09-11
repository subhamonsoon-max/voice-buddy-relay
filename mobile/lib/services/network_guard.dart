import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkGuard {
  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _wifiStatusController =
      StreamController<bool>.broadcast();

  Stream<bool> get onWifiChanged => _wifiStatusController.stream;
  bool _isWifi = false;
  bool get isWifi => _isWifi;

  Future<void> init() async {
    final List<ConnectivityResult> results =
        await _connectivity.checkConnectivity();
    _updateStatus(results);

    _connectivity.onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      _updateStatus(results);
    });
  }

  void _updateStatus(List<ConnectivityResult> results) {
    // Check if Wi-Fi is one of the active networks
    _isWifi = results.contains(ConnectivityResult.wifi);
    _wifiStatusController.add(_isWifi);
  }

  void dispose() {
    _wifiStatusController.close();
  }
}
