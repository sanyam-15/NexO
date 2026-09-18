import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Connection state for the local Claude Code / Codex bridge (`cli_bridge`).
///
/// The bridge is a tiny OpenAI-compatible server the user runs in Termux (see
/// `tools/nexo-ai-bridge/`). This controller only checks its health.
enum BridgeStatus { unknown, checking, connected, disconnected }

class BridgeState {
  const BridgeState({
    this.status = BridgeStatus.unknown,
    this.backends = const [],
    this.error,
  });

  final BridgeStatus status;
  final List<String> backends;
  final String? error;

  bool get isConnected => status == BridgeStatus.connected;
  bool get isBusy => status == BridgeStatus.checking;

  BridgeState copyWith({
    BridgeStatus? status,
    List<String>? backends,
    Object? error = _sentinel,
  }) {
    return BridgeState(
      status: status ?? this.status,
      backends: backends ?? this.backends,
      error: identical(error, _sentinel) ? this.error : error as String?,
    );
  }

  static const Object _sentinel = Object();
}

class CliBridgeController extends StateNotifier<BridgeState> {
  CliBridgeController() : super(const BridgeState());

  /// Health endpoint lives at the server root (`/health`), not under `/v1`.
  String _origin(String baseUrl) {
    var b = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (b.toLowerCase().endsWith('/v1')) b = b.substring(0, b.length - 3);
    return b.replaceAll(RegExp(r'/+$'), '');
  }

  /// GET {origin}/health and reflect the result in state.
  Future<void> check(String baseUrl, String token) async {
    final origin = _origin(baseUrl);
    if (origin.isEmpty) {
      state = state.copyWith(
          status: BridgeStatus.disconnected, error: 'URL base vacía.');
      return;
    }
    state = state.copyWith(status: BridgeStatus.checking, error: null);
    try {
      final res = await http.get(
        Uri.parse('$origin/health'),
        headers: {
          if (token.trim().isNotEmpty)
            'authorization': 'Bearer ${token.trim()}',
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final backends = (body is Map && body['backends'] is List)
            ? (body['backends'] as List).map((e) => e.toString()).toList()
            : const <String>[];
        state = state.copyWith(
            status: BridgeStatus.connected, backends: backends, error: null);
      } else if (res.statusCode == 401) {
        state = state.copyWith(
            status: BridgeStatus.disconnected, error: 'Token inválido (401).');
      } else {
        state = state.copyWith(
            status: BridgeStatus.disconnected,
            error: 'HTTP ${res.statusCode}.');
      }
    } catch (e) {
      state = state.copyWith(
          status: BridgeStatus.disconnected, error: _friendly(e));
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('Connection refused') ||
        s.contains('Connection failed') ||
        s.contains('SocketException')) {
      return 'Sin respuesta (¿el bridge está apagado?).';
    }
    if (s.contains('TimeoutException')) {
      return 'Timeout: el bridge no respondió a tiempo.';
    }
    return s;
  }
}

final cliBridgeProvider =
    StateNotifierProvider<CliBridgeController, BridgeState>(
  (ref) => CliBridgeController(),
);
