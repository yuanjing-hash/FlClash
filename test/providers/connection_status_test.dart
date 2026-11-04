import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/root_tun.dart';
import 'package:fl_clash/providers/connection_status.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/providers/root_tun.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/root_tun.dart';
import '../support/root_tun_controller.dart';

class _Progress extends SetupAction {
  @override
  RunProgress build() => RunProgress.idle;

  void show(RunProgress progress) => state = progress;
}

void main() {
  test('an early zero runtime does not end Root startup; failure does', () {
    final root = TestRootTunController(
      snapshot: RootTunSnapshot.fromJson(
        rootTunSnapshotJson(state: 'disabled'),
      ),
    );
    final setup = _Progress();
    final container = ProviderContainer(
      overrides: [
        rootTunControllerProvider.overrideWith(() => root),
        setupActionProvider.overrideWith(() => setup),
        appVisibleProvider.overrideWithBuild((_, _) => false),
      ],
    );
    addTearDown(container.dispose);
    container.read(setupActionProvider);
    setup.syncRunTime(DateTime.now());
    setup.show(RunProgress.starting);
    setup.syncRunTime(null);
    expect(container.read(setupActionProvider), RunProgress.starting);
    expect(container.read(isStartProvider), isTrue);
    root.emit(root.initial.copyWith(state: RootTunState.failed));
    setup.syncRunTime(null);
    expect(container.read(setupActionProvider), RunProgress.idle);
    expect(container.read(isStartProvider), isFalse);
  });

  test(
    'confirmed Root readiness drives the route before the legacy timer report',
    () {
      final root = TestRootTunController(
        snapshot: RootTunSnapshot.fromJson(rootTunSnapshotJson()),
      );
      final container = ProviderContainer(
        overrides: [
          rootTunControllerProvider.overrideWith(() => root),
          setupActionProvider.overrideWithBuild((_, _) => RunProgress.idle),
          connectionPhaseProvider().overrideWith(
            (ref) => ref.watch(
              connectionPhaseProvider(platform: SupportPlatform.Android),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(isStartProvider), isFalse);
      expect(container.read(routeTrackerProvider).proxied, isTrue);
    },
  );

  test('Root readiness overrides the optimistic running flag', () {
    final root = TestRootTunController(
      snapshot: RootTunSnapshot.fromJson(
        rootTunSnapshotJson(),
      ).copyWith(state: RootTunState.starting),
    );
    final container = ProviderContainer(
      overrides: [rootTunControllerProvider.overrideWith(() => root)],
    );
    addTearDown(container.dispose);
    final provider = connectionPhaseProvider(platform: SupportPlatform.Android);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    container.read(runTimeProvider.notifier).value = 1;
    expect(container.read(provider), ConnectionPhase.starting);
    for (final (native, shown) in [
      (RootTunState.awaitingAuth, ConnectionPhase.awaitingAuth),
      (RootTunState.running, ConnectionPhase.running),
      (RootTunState.recovering, ConnectionPhase.recovering),
      (RootTunState.failed, ConnectionPhase.failed),
      (RootTunState.stopping, ConnectionPhase.stopping),
      (RootTunState.disabled, ConnectionPhase.stopped),
    ]) {
      root.emit(root.initial.copyWith(state: native));
      expect(container.read(provider), shown);
    }
    root.emit(root.initial.copyWith(state: RootTunState.running, stale: true));
    expect(container.read(provider).canProbe, isFalse);
  });

  for (final mode in [RootTunMode.off, RootTunMode.vpn]) {
    test('VPN finishes startup after a native runtime report from $mode', () {
      final root = TestRootTunController(
        snapshot: RootTunSnapshot.fromJson(
          rootTunSnapshotJson(
            enabled: false,
            autostart: false,
            state: 'disabled',
          ),
        ).copyWith(mode: mode),
      );
      final progress = _Progress();
      final container = ProviderContainer(
        overrides: [
          rootTunControllerProvider.overrideWith(() => root),
          setupActionProvider.overrideWith(() => progress),
          appVisibleProvider.overrideWithBuild((_, _) => false),
        ],
      );
      addTearDown(container.dispose);
      final provider = connectionPhaseProvider(
        platform: SupportPlatform.Android,
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      progress.show(RunProgress.starting);
      expect(container.read(provider), ConnectionPhase.starting);
      expect(container.read(provider).canProbe, isFalse);
      final startedAt = DateTime.now().subtract(const Duration(seconds: 5));
      progress.syncRunTime(startedAt);
      expect(container.read(provider), ConnectionPhase.running);
      expect(container.read(provider).canProbe, isTrue);
      expect(container.read(runTimeProvider), greaterThanOrEqualTo(5_000));
      progress.syncRunTime(null);
      expect(container.read(provider), ConnectionPhase.stopped);
    });
  }

  test('VPN waits for the native runtime report after command acceptance', () {
    final root = TestRootTunController();
    final progress = _Progress();
    final container = ProviderContainer(
      overrides: [
        rootTunControllerProvider.overrideWith(() => root),
        setupActionProvider.overrideWith(() => progress),
      ],
    );
    addTearDown(container.dispose);
    final provider = connectionPhaseProvider(platform: SupportPlatform.Android);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    progress.show(RunProgress.starting);
    container.read(runTimeProvider.notifier).value = 1;
    expect(container.read(provider), ConnectionPhase.starting);
    progress.show(RunProgress.idle);
    expect(container.read(provider), ConnectionPhase.running);
    progress.show(RunProgress.stopping);
    expect(container.read(provider), ConnectionPhase.stopping);
    container.read(runTimeProvider.notifier).value = null;
    progress.show(RunProgress.idle);
    expect(container.read(provider), ConnectionPhase.stopped);
  });
}
