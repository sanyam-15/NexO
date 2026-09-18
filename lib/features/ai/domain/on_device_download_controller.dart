import 'package:flutter_gemma/flutter_gemma.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/ai/on_device_gemma_client.dart';
import '../../../core/ai/on_device_models.dart';
import '../../../core/db/local_store.dart';

enum DownloadPhase { idle, downloading, resumable, importable, installing, installed, error }

class ModelDownloadState {
  const ModelDownloadState(this.phase, {this.percent = 0, this.error});
  final DownloadPhase phase;
  final int percent;
  final String? error;
}

/// App-lifetime owner of on-device model download state.
///
/// Progress lives here (not in widget State) so it survives navigating away,
/// screen-off, and widget rebuilds — the bug where the bar reset to 0%. A
/// persisted "pending" marker lets a download that was cut by a reboot be
/// resumed on next launch (flutter_gemma resumes from the partial file).
class OnDeviceDownloadController extends StateNotifier<Map<String, ModelDownloadState>> {
  OnDeviceDownloadController(this._ref) : super(const {}) {
    _init();
  }

  final Ref _ref;
  final Map<String, CancelToken> _cancels = {};

  static const _pendingKey = 'ai_ondevice_pending';
  static const _profileId = 'gemma_device';

  String? _pending() {
    final rows = LocalStore.db.select('SELECT value FROM app_meta WHERE key = ?', [_pendingKey]);
    final v = rows.isEmpty ? '' : rows.first['value'] as String;
    return v.trim().isEmpty ? null : v.trim();
  }

  void _setPending(String? id) {
    if (id == null) {
      LocalStore.db.execute('DELETE FROM app_meta WHERE key = ?', [_pendingKey]);
    } else {
      LocalStore.db.execute('INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)', [_pendingKey, id]);
    }
  }

  void _set(String id, ModelDownloadState s) => state = {...state, id: s};

  Future<void> _init() async {
    await refreshInstalled();
  }

  /// Recomputes each model's state from disk: installed > a sideloaded file
  /// ready to import > a resumable interrupted download > idle. Never disturbs
  /// a download that is actively running.
  Future<void> refreshInstalled() async {
    try {
      final installed = (await OnDeviceGemma.installed()).toSet();
      final pending = _pending();
      final map = {...state};
      for (final m in kOnDeviceModels) {
        if (state[m.id]?.phase == DownloadPhase.downloading ||
            state[m.id]?.phase == DownloadPhase.installing) {
          continue;
        }
        if (installed.contains(m.id)) {
          map[m.id] = const ModelDownloadState(DownloadPhase.installed, percent: 100);
        } else if (await OnDeviceGemma.hasLocalFile(m.id)) {
          map[m.id] = const ModelDownloadState(DownloadPhase.importable);
        } else if (pending == m.id) {
          map[m.id] = const ModelDownloadState(DownloadPhase.resumable);
        } else {
          map[m.id] = const ModelDownloadState(DownloadPhase.idle);
        }
      }
      state = map;
    } catch (_) {/* plugin unavailable → leave state as-is */}
  }

  /// Registers a sideloaded model file (adb push / manual copy) without any
  /// network download, then activates it.
  Future<void> import(OnDeviceModel model) async {
    _set(model.id, const ModelDownloadState(DownloadPhase.installing));
    try {
      await OnDeviceGemma.importFromFile(model);
      _setPending(null);
      _set(model.id, const ModelDownloadState(DownloadPhase.installed, percent: 100));
      activate(model.id);
    } catch (e) {
      _set(model.id, ModelDownloadState(DownloadPhase.error, error: e.toString()));
    }
  }

  /// Starts (or resumes/attaches to) a download. Safe to call repeatedly —
  /// flutter_gemma attaches to an in-flight task or resumes from the partial.
  Future<void> start(OnDeviceModel model, {String? token}) async {
    if (state[model.id]?.phase == DownloadPhase.downloading) return;
    _setPending(model.id);
    _set(model.id, const ModelDownloadState(DownloadPhase.downloading, percent: 0));
    final cancel = CancelToken();
    _cancels[model.id] = cancel;
    try {
      await OnDeviceGemma.download(
        model,
        token: token,
        cancelToken: cancel,
        onProgress: (p) {
          if (state[model.id]?.phase == DownloadPhase.downloading) {
            _set(model.id, ModelDownloadState(DownloadPhase.downloading, percent: p));
          }
        },
      );
      _setPending(null);
      _set(model.id, const ModelDownloadState(DownloadPhase.installed, percent: 100));
      activate(model.id); // freshly downloaded model becomes the active one
    } catch (e) {
      final msg = e.toString();
      if (msg.toLowerCase().contains('cancel')) {
        _setPending(null);
        _set(model.id, const ModelDownloadState(DownloadPhase.idle));
      } else {
        // keep the pending marker so the partial can be resumed later
        _set(model.id, ModelDownloadState(DownloadPhase.error, error: msg));
      }
    } finally {
      _cancels.remove(model.id);
    }
  }

  void cancel(String id) {
    _cancels[id]?.cancel('Cancelado por el usuario');
    _setPending(null);
    _set(id, const ModelDownloadState(DownloadPhase.idle));
  }

  /// Makes [modelId] the active provider model and turns AI on.
  void activate(String modelId) {
    final n = _ref.read(aiConfigProvider.notifier);
    n.updateProvider(_profileId, model: modelId);
    n.selectProvider(_profileId);
    n.setEnabled(true);
  }

  Future<void> remove(String id) async {
    try {
      await OnDeviceGemma.remove(id);
    } finally {
      _setPending(null);
      _set(id, const ModelDownloadState(DownloadPhase.idle));
    }
  }
}

final onDeviceDownloadProvider =
    StateNotifierProvider<OnDeviceDownloadController, Map<String, ModelDownloadState>>(
  (ref) => OnDeviceDownloadController(ref),
);
