import 'dart:async';

import 'package:fl_clash/models/root_tun.dart';
import 'package:fl_clash/plugins/root_tun.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generated/root_tun.g.dart';

@Riverpod(keepAlive: true)
RootTunPlugin rootTunPlugin(Ref ref) => RootTunPlugin();

@Riverpod(keepAlive: true)
class RootTunController extends _$RootTunController {
  StreamSubscription<RootTunEvent>? _subscription;
  Future<void>? _refreshing;
  bool _disposed = false;
  Timer? _reconnect;
  int _subscriptionId = 0;

  RootTunPlugin get _plugin => ref.read(rootTunPluginProvider);

  @override
  RootTunViewState build() {
    ref.onDispose(() {
      _disposed = true;
      _subscriptionId++;
      _reconnect?.cancel();
      unawaited(_subscription?.cancel());
    });
    unawaited(Future<void>.microtask(refresh));
    return const RootTunViewState();
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
    Future<RootTunResult<RootTunAck>> Function() invoke,
  ) async {
    if (_disposed || state.snapshot?.stale != false) return;
    state = state.copyWith(
      pendingCommands: state.pendingCommands + 1,
      commandError: null,
    );
    try {
      final result = await invoke();
      if (_disposed) return;
      if (result.data case final ack?) _accept(ack.snapshot, fromAck: true);
      state = state.copyWith(commandError: result.error);
      if (result.error != null) await refresh();
    } catch (error) {
      if (error is RootTunChannelException &&
          error.method == 'cleanupResidue' &&
          error.notImplemented &&
          !_disposed) {
        state = state.copyWith(cleanupSupported: false);
      }
      _failure(error);
      await refresh();
    } finally {
      if (!_disposed) {
        state = state.copyWith(pendingCommands: state.pendingCommands - 1);
      }
    }
  }

  Future<void> start() => _command(_plugin.start);
  Future<void> stop(RootTunStopReason reason) =>
      _command(() => _plugin.stop(reason));
  Future<void> recheckRoot() async {
    await refresh();
    await _command(_plugin.recheckRoot);
  }

  Future<void> setAutostart(bool enabled) =>
      _command(() => _plugin.setAutostart(enabled));
  Future<void> cleanupResidue() => _command(_plugin.cleanupResidue);
}
