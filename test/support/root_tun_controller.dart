import 'dart:async';

import 'package:fl_clash/models/root_tun.dart';
import 'package:fl_clash/providers/root_tun.dart';

import 'root_tun.dart';

class TestRootTunController extends RootTunController {
  TestRootTunController({RootTunSnapshot? snapshot})
    : initial =
          snapshot ??
          RootTunSnapshot.fromJson(
            rootTunSnapshotJson(
              enabled: false,
              autostart: false,
              state: 'disabled',
            ),
          );

  final RootTunSnapshot initial;
  final selections = <RootTunMode>[];
  Completer<void>? selectionGate;
  bool failSelection = false;

  RootTunViewState get view => state;

  @override
  RootTunViewState build() =>
      RootTunViewState(snapshot: initial, channelAvailable: true);

  void emit(RootTunSnapshot snapshot) =>
      state = state.copyWith(snapshot: snapshot);

  @override
  Future<void> selectMode(RootTunMode mode) async {
    selections.add(mode);
    final previous = state.snapshot!;
    state = state.copyWith(
      pendingCommands: 1,
      snapshot: previous.copyWith(state: RootTunState.stopping),
    );
    await selectionGate?.future;
    if (!ref.mounted) return;
    state = failSelection
        ? state.copyWith(
            pendingCommands: 0,
            snapshot: previous,
            commandError: const RootTunError(
              code: RootTunCode.modeSwitchFailed,
              retryable: true,
              details: {},
            ),
          )
        : RootTunViewState(
            channelAvailable: true,
            snapshot: previous.copyWith(
              mode: mode,
              rootTunEnabled: mode == RootTunMode.rootTun,
              state: RootTunState.disabled,
              startedAt: null,
            ),
          );
  }
}
