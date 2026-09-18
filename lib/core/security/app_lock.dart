import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../db/local_store.dart';

class AppLockState {
  const AppLockState({required this.enabled, required this.unlocked});
  final bool enabled;
  final bool unlocked;

  /// The lock screen should block the app when locking is on and not yet unlocked.
  bool get isBlocking => enabled && !unlocked;

  AppLockState copyWith({bool? enabled, bool? unlocked}) =>
      AppLockState(enabled: enabled ?? this.enabled, unlocked: unlocked ?? this.unlocked);
}

class AppLockController extends StateNotifier<AppLockState> {
  AppLockController() : super(const AppLockState(enabled: false, unlocked: true)) {
    final enabled = _meta('app_lock_enabled') == 'true';
    // When locking is enabled, start locked and require auth on launch.
    state = AppLockState(enabled: enabled, unlocked: !enabled);
  }

  final _auth = LocalAuthentication();

  String _meta(String key) {
    final rows = LocalStore.db.select('SELECT value FROM app_meta WHERE key = ?', [key]);
    return rows.isEmpty ? '' : rows.first['value'] as String;
  }

  void _set(String key, String value) {
    LocalStore.db.execute('INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)', [key, value]);
  }

  Future<bool> isSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Prompts the OS for biometric / device-credential authentication.
  Future<bool> authenticate({String reason = 'Desbloquea Nexo'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('app_lock auth error: $e');
      return false;
    }
  }

  /// Unlocks the app after a successful auth prompt.
  Future<bool> unlock() async {
    final ok = await authenticate();
    if (ok) state = state.copyWith(unlocked: true);
    return ok;
  }

  /// Re-locks (e.g. when the app goes to background).
  void lock() {
    if (state.enabled) state = state.copyWith(unlocked: false);
  }

  /// Both directions require a successful auth: enabling so the user can't
  /// lock themselves out without working credentials, disabling so someone
  /// with momentary access to an unlocked phone can't silently strip the lock.
  Future<bool> setEnabled(bool enabled) async {
    final ok = await authenticate(
      reason: enabled ? 'Confirma para activar el bloqueo' : 'Confirma para desactivar el bloqueo',
    );
    if (!ok) return false;
    _set('app_lock_enabled', enabled ? 'true' : 'false');
    state = AppLockState(enabled: enabled, unlocked: true);
    return true;
  }
}

final appLockProvider = StateNotifierProvider<AppLockController, AppLockState>(
  (ref) => AppLockController(),
);
