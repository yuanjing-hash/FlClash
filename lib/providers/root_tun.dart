import 'dart:async';

import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/root_tun.dart';
import 'package:fl_clash/plugins/root_tun.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generated/root_tun.g.dart';

@Riverpod(keepAlive: true)
RootTunPlugin rootTunPlugin(Ref ref) => RootTunPlugin();

@Riverpod(keepAlive: true)
Preferences rootTunPreferences(Ref ref) => preferences;

@Riverpod(keepAlive: true)
class RootTunController extends _$RootTunController {
  StreamSubscription<RootTunEvent>? _subscription;
  Future<void>? _refreshing;
  bool _disposed = false;
  Timer? _reconnect;
  int _subscriptionId = 0;
  late Future<void> _promptHistoryReady;
  Future<void> _promptWrite = Future.value();
  Future<void> _commandReady = Future.value();
  String? _promptEpoch;
  final _shownPromptCodes = <String>{};
  int _promptRevision = 0;

  RootTunPlugin get _plugin => ref.read(rootTunPluginProvider);
  Preferences get _preferences => ref.read(rootTunPreferencesProvider);

  @override
  RootTunViewState build() {
    _promptHistoryReady = _restorePromptHistory();
    ref.onDispose(() {
      _disposed = true;
      _subscriptionId++;
      _reconnect?.cancel();
      unawaited(_subscription?.cancel());
    });
    unawaited(Future<void>.microtask(refresh));
    return const RootTunViewState();
  }

  Future<void> _restorePromptHistory() async {
    final history = await _preferences.getRootTunPromptHistory();
    if (_disposed || history.isEmpty) return;
    _promptEpoch = history.first;
    _shownPromptCodes.addAll(
      history.skip(1).where(RootTunCode.values.contains),
    );
  }

  Future<void> _savePromptHistory() {
    final history = [_promptEpoch!, ..._shownPromptCodes];
    final store = _preferences;
    return _promptWrite = _promptWrite
        .then((_) => store.saveRootTunPromptHistory(history))
        .catchError((Object error) {
          commonPrint.log(
            'Save Root TUN prompt history failed: $error',
            logLevel: LogLevel.warning,
          );
        });
  }

  Future<bool> markPromptShown(RootTunSnapshot snapshot, String code) async {
    if (_disposed ||
        state.snapshot?.epoch != snapshot.epoch ||
        !RootTunCode.values.contains(code) ||
        !_shownPromptCodes.add(code)) {
      return false;
    }
    final revision = _promptRevision;
    await _savePromptHistory();
    return !_disposed &&
        revision == _promptRevision &&
        state.snapshot?.epoch == snapshot.epoch;
  }

  void _failure(Object error) {
    if (_disposed) return;
    state = state.copyWith(
      channelAvailable: false,
      lastChannelError: '$error',
      snapshot: state.snapshot?.copyWith(stale: true),
    );
  }

  void _accept(RootTunSnapshot snapshot, {bool fromAck = false}) {
    if (_disposed) return;
    final current = state.snapshot;
    if (current != null) {
      if (fromAck && snapshot.epoch != current.epoch) return;
      if (snapshot.epoch == current.epoch &&
          (snapshot.seq < current.seq ||
              snapshot.intentRevision < current.intentRevision)) {
        return;
      }
    }
    // TDD §6.1 makes epoch the runtime session domain; sequence, error time and
    // startedAt can change during recovery or be absent while awaiting auth.
    if (_promptEpoch != snapshot.epoch) {
      _promptEpoch = snapshot.epoch;
      _shownPromptCodes.clear();
      _promptRevision++;
      unawaited(_savePromptHistory());
    }
    state = state.copyWith(
      snapshot: snapshot,
      channelAvailable: true,
      event: current?.epoch == snapshot.epoch ? state.event : null,
      commandError: current?.epoch == snapshot.epoch
          ? state.commandError
          : null,
    );
  }

  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    _reconnect?.cancel();
    final id = ++_subscriptionId;
    await _subscription?.cancel();
    _subscription = null;
    await _promptHistoryReady;
    if (_disposed) return;
    try {
      final result = await _plugin.getState();
      if (_disposed) return;
      final snapshot = result.data;
      if (snapshot == null) {
        state = state.copyWith(commandError: result.error);
        return;
      }
      _accept(snapshot);
      if (_disposed || id != _subscriptionId) return;
      _subscription = _plugin
          .events(state.snapshot!)
          .listen(
            (event) {
              if (_disposed || id != _subscriptionId) return;
              try {
                final merged = event.merge(state.snapshot!);
                if (merged == null) {
                  state = state.copyWith(
                    snapshot: state.snapshot?.copyWith(stale: true),
                  );
                  unawaited(Future<void>.microtask(refresh));
                  return;
                }
                final changed = !identical(merged, state.snapshot);
                _accept(merged);
                if (changed) state = state.copyWith(event: event);
              } catch (error) {
                _failure(error);
                unawaited(Future<void>.microtask(refresh));
              }
            },
            onError: (Object error) {
              if (_disposed || id != _subscriptionId) return;
              _failure(error);
              if (error is! RootTunChannelException || !error.notImplemented) {
                _scheduleReconnect();
              }
            },
            onDone: () {
              if (_disposed || id != _subscriptionId) return;
              _failure(
                const RootTunChannelException('events', 'disconnected', null),
              );
              _scheduleReconnect();
            },
          );
    } catch (error) {
      _failure(error);
    }
  }

  void _scheduleReconnect() {
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 3), () {
      if (!_disposed) unawaited(refresh());
    });
  }

  void recordChannelError(Object error) {
    if (!_disposed) state = state.copyWith(lastChannelError: '$error');
  }

  Future<void> detectRoot() async {
    await refresh();
    if (_disposed || state.channelAvailable != true) return;
    try {
      final result = await _plugin.detectRoot();
      if (_disposed) return;
      if (result.data case final snapshot?) _accept(snapshot);
      state = state.copyWith(commandError: result.error);
    } catch (error) {
      _failure(error);
      await refresh();
    }
  }

  Future<void> _command(
    Future<RootTunResult<RootTunAck>> Function() invoke, {
    bool allowWhenStale = false,
    bool resetPrompts = false,
  }) async {
    if (_disposed || (!allowWhenStale && state.snapshot?.stale != false)) {
      return;
    }
    state = state.copyWith(
      pendingCommands: state.pendingCommands + 1,
      commandError: null,
    );
    try {
      if (resetPrompts) {
        _promptRevision++;
        _shownPromptCodes.clear();
        _commandReady = _savePromptHistory();
      }
      await _commandReady;
      if (_disposed) return;
      final result = await invoke();
      if (_disposed) return;
      if (result.data case final ack?) _accept(ack.snapshot, fromAck: true);
      state = state.copyWith(commandError: result.error);
      if (result.error != null) await refresh();
    } catch (error) {
      if (error is RootTunChannelException &&
          error.notImplemented &&
          !_disposed) {
        if (error.method == 'cleanupResidue') {
          state = state.copyWith(cleanupSupported: false);
        }
        if (error.method == 'setAutostart') {
          state = state.copyWith(autostartSupported: false);
        }
      }
      _failure(error);
      await refresh();
    } finally {
      if (!_disposed) {
        state = state.copyWith(pendingCommands: state.pendingCommands - 1);
      }
    }
  }

  Future<void> start() => _command(_plugin.start, resetPrompts: true);
  Future<void> stop(RootTunStopReason reason) =>
      _command(() => _plugin.stop(reason), allowWhenStale: true);
  Future<void> recheckRoot() async {
    await refresh();
    await _command(_plugin.recheckRoot, allowWhenStale: true);
  }

  Future<void> setAutostart(bool enabled) =>
      _command(() => _plugin.setAutostart(enabled));
  Future<void> cleanupResidue() => _command(_plugin.cleanupResidue);
}
