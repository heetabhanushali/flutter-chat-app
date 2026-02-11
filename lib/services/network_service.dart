import 'dart:io';
import 'dart:async';
import 'package:chat_app/services/connectivity_service.dart';

class NetworkService {
  // ── Singleton ──────────────────────────────────────────────
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();
  // ──────────────────────────────────────────────────────────

  final ConnectivityService _connectivity = ConnectivityService();

  bool get isOnline => _connectivity.isOnline;

  void reportOnline() => _connectivity.reportOnline();
  void reportOffline() => _connectivity.reportOffline();

  /// Wraps any async call with network error handling.
  Future<T> call<T>({
    required Future<T> Function() action,
    required T fallback,
  }) async {
    try {
      final result = await action();
      _connectivity.reportOnline();
      return result;
    } catch (e) {
      if (isNetworkError(e)) {
        _connectivity.reportOffline();
        return fallback;
      }
      rethrow;
    }
  }

  /// Returns null on network error
  Future<T?> callOrNull<T>({
    required Future<T> Function() action,
  }) async {
    try {
      final result = await action();
      _connectivity.reportOnline();
      return result;
    } catch (e) {
      if (isNetworkError(e)) {
        _connectivity.reportOffline();
        return null;
      }
      rethrow;
    }
  }

  /// Silently fails on network error
  Future<void> callSilent({
    required Future<void> Function() action,
  }) async {
    try {
      await action();
      _connectivity.reportOnline();
    } catch (e) {
      if (isNetworkError(e)) {
        _connectivity.reportOffline();
        return;
      }
      rethrow;
    }
  }

  /// Network/connectivity errors — RETRYABLE
  bool isNetworkError(dynamic e) {
    if (e is SocketException) return true;
    if (e is TimeoutException) return true;

    final msg = e.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('connection reset') ||
        msg.contains('connection closed') ||
        msg.contains('handshakeexception') ||
        msg.contains('connection timed out') ||
        msg.contains('network is unreachable') ||
        msg.contains('no address associated') ||
        msg.contains('no route to host') ||
        msg.contains('timed out') ||
        msg.contains('errno = 7') ||
        msg.contains('errno = 101') ||
        msg.contains('errno = 110') ||
        msg.contains('errno = 111') ||
        msg.contains('clientexception');
  }

  /// Server errors — NOT RETRYABLE (will never succeed no matter how many retries)
  bool isNonRetryableError(dynamic e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('403') ||
        msg.contains('409') ||
        msg.contains('unique constraint') ||
        msg.contains('duplicate key') ||
        msg.contains('violates') ||
        msg.contains('not found') ||
        msg.contains('unauthorized') ||
        msg.contains('forbidden');
  }
}