import 'dart:convert';

import 'package:fl_clash/manager/android_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/models/root_tun.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/root_tun.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/preferences.dart';
import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';
import '../support/root_tun_controller.dart';

class _RecordingSetupAction extends SetupAction {
  static final requests = <bool>[];
  static final runTimes = <DateTime?>[];

  @override
  Future<bool> setRunning(bool running, {bool initialize = false}) async {
    requests.add(running);
    return true;
  }

  @override
  void syncRunTime(DateTime? startedAt) => runTimes.add(startedAt);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late SharedPreferences store;
  late TestRootTunController rootTun;

  setUp(() async {
    await mockPreferences();
    store = await SharedPreferences.getInstance();
    _RecordingSetupAction.requests.clear();
    _RecordingSetupAction.runTimes.clear();
    rootTun = TestRootTunController();
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        setupActionProvider.overrideWith(_RecordingSetupAction.new),
        rootTunControllerProvider.overrideWith(() => rootTun),
        // Bypassing private addresses computes the routes in Isolate.run, which
        // the fake clock never lets finish.
        networkSettingProvider.overrideWithBuild(
          (_, _) => const NetworkProps(bypassPrivateRoute: false),
        ),
      ],
    );
    container.listen(rootTunControllerProvider, (_, _) {});
    globalState.container = container;
  });

  tearDown(() => container.dispose());

  Future<void> pumpAndroidManager(WidgetTester tester) async {
    await container.read(vpnOptionsProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          child: AndroidManager(child: SizedBox(key: Key('child'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders its child unchanged', (tester) async {
    await pumpAndroidManager(tester);

    expect(find.byKey(const Key('child')), findsOneWidget);
    expect(tester.takeException(), null);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mirrors a stopped VPN without requesting another stop', (
    tester,
  ) async {
    await pumpAndroidManager(tester);
    rootTun.emit(
      rootTun.initial.copyWith(
        mode: RootTunMode.vpn,
        state: RootTunState.running,
      ),
    );
    final listener =
        tester.state(find.byType(AndroidManager)) as ServiceListener;

    listener.onServiceStopped();
    await tester.pump();

    expect(_RecordingSetupAction.requests, isEmpty);
    expect(_RecordingSetupAction.runTimes, [null]);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final state in [
    RootTunState.starting,
    RootTunState.running,
    RootTunState.recovering,
  ]) {
    testWidgets('an embedded service stop cannot stop Root TUN while $state', (
      tester,
    ) async {
      await pumpAndroidManager(tester);
      rootTun.emit(
        rootTun.initial.copyWith(
          mode: RootTunMode.rootTun,
          rootTunEnabled: true,
          state: state,
        ),
      );
      final listener =
          tester.state(find.byType(AndroidManager)) as ServiceListener;

      listener.onServiceStopped();
      listener.onServiceStopped();
      await tester.pump();

      expect(_RecordingSetupAction.requests, isEmpty);
      expect(_RecordingSetupAction.runTimes, isEmpty);
      expect(rootTun.view.snapshot!.state, state);

      listener.onServiceRunTimeChanged(null);
      expect(_RecordingSetupAction.runTimes, [null]);
      expect(_RecordingSetupAction.requests, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('mirrors native root runtime without sending another command', (
    tester,
  ) async {
    await pumpAndroidManager(tester);
    final listener =
        tester.state(find.byType(AndroidManager)) as ServiceListener;
    final startedAt = DateTime.fromMillisecondsSinceEpoch(1234);

    listener.onServiceRunTimeChanged(startedAt);
    listener.onServiceRunTimeChanged(null);
    await tester.pump();

    expect(_RecordingSetupAction.runTimes, [startedAt, null]);
    expect(_RecordingSetupAction.requests, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('persists shared state after the debounce window', (
    tester,
  ) async {
    await pumpAndroidManager(tester);
    expect(store.getString('sharedState'), isNull);

    container.read(appSettingProvider.notifier).value = const AppSettingProps(
      testUrl: 'http://shared.test',
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final raw = store.getString('sharedState');
    expect(raw, isNotNull);
    final restored = SharedState.fromJson(
      json.decode(raw!) as Map<String, Object?>,
    );
    expect(restored.onlyStatisticsProxy, isFalse);
    expect(tester.takeException(), null);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('does not persist when shared state is unchanged', (
    tester,
  ) async {
    await pumpAndroidManager(tester);

    container.read(appSettingProvider.notifier).value = const AppSettingProps();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(store.getString('sharedState'), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
