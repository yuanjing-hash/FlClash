import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/root_tun.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'action.dart';
import 'app.dart';
import 'root_tun.dart';
import 'state.dart';

part 'generated/connection_status.g.dart';

enum ConnectionPhase {
  stopped,
  starting,
  awaitingAuth,
  running,
  recovering,
  stopping,
  failed;

  bool get canProbe => this == stopped || this == running;
}

@riverpod
ConnectionPhase connectionPhase(Ref ref, {SupportPlatform? platform}) {
  final progress = ref.watch(setupActionProvider);
  if (progress == RunProgress.stopping) return ConnectionPhase.stopping;
  if ((platform ?? SupportPlatform.currentPlatform) ==
      SupportPlatform.Android) {
    final snapshot = ref.watch(rootTunControllerProvider).snapshot;
    if (snapshot?.state == RootTunState.stopping) {
      return ConnectionPhase.stopping;
    }
    if (snapshot?.mode == RootTunMode.rootTun) {
      if (snapshot!.stale) return ConnectionPhase.failed;
      return switch (snapshot.state) {
        RootTunState.awaitingAuth => ConnectionPhase.awaitingAuth,
        RootTunState.starting => ConnectionPhase.starting,
        RootTunState.running => ConnectionPhase.running,
        RootTunState.recovering => ConnectionPhase.recovering,
        RootTunState.stopping => ConnectionPhase.stopping,
        RootTunState.failed || RootTunState.degraded => ConnectionPhase.failed,
        RootTunState.disabled =>
          progress == RunProgress.starting
              ? ConnectionPhase.starting
              : ConnectionPhase.stopped,
      };
    }
  }
  if (progress == RunProgress.starting) return ConnectionPhase.starting;
  return ref.watch(isStartProvider)
      ? ConnectionPhase.running
      : ConnectionPhase.stopped;
}
