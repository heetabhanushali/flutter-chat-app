import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  // ── Singleton ──────────────────────────────────────────────
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();
  // ──────────────────────────────────────────────────────────

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  StreamSubscription? _connectivitySub;
  Timer? _periodicCheck;
  bool _isOnline = true;
  bool _monitoring = false;

  bool get isOnline => _isOnline;
  Stream<bool> get onConnectivityChanged => _controller.stream;

  /// Start monitoring. Safe to call multiple times.
  void startMonitoring() {
    if (_monitoring) return;
    _monitoring = true;

    // 1. Listen to OS-level connectivity changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        _setOnline(false);
      } else {
        // OS says connected — verify with a real check
        verifyConnection();
      }
    });

    // 2. Periodic check when offline — try to recover every 10s
    _periodicCheck = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_isOnline) {
        verifyConnection();
      }
    });

    // 3. Check right now
    verifyConnection();
  }

  /// Actively verify internet by doing a DNS lookup
  Future<bool> verifyConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));

      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        _setOnline(true);
        return true;
      }
    } catch (_) {}

    _setOnline(false);
    return false;
  }

  void _setOnline(bool online) {
    if (_isOnline == online) return;
    _isOnline = online;
    _controller.add(online);
  }

  void reportOnline() => _setOnline(true);

  void reportOffline() {
    _setOnline(false);
    Future.delayed(const Duration(seconds: 2), () => verifyConnection());
  }

  void dispose() {
    _connectivitySub?.cancel();
    _periodicCheck?.cancel();
    _controller.close();
    _monitoring = false;
  }
}