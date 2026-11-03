import 'dart:async';

import 'package:fl_clash/models/root_tun.dart';
import 'package:fl_clash/providers/root_tun.dart';
import 'package:fl_clash/views/dashboard/widgets/card.dart';
import 'package:fl_clash/views/dashboard/widgets/connection_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';
import '../../support/root_tun_controller.dart';

void main() {
  Future<void> pump(WidgetTester tester, TestRootTunController root) async {
    await tester.pumpWidget(
      TestApp(
        locale: const Locale('en'),
        overrides: [rootTunControllerProvider.overrideWith(() => root)],
        child: const Scaffold(
          body: SizedBox(width: 380, child: ConnectionModeCard()),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'mode choice keeps the proxy stopped and waits for native selection',
    (tester) async {
      final root = TestRootTunController()..selectionGate = Completer<void>();
      await pump(tester, root);
      expect(find.text('Traffic takeover'), findsOneWidget);
      await tester.tap(find.text('Root TUN'));
      await tester.pump();
      expect(root.selections, [RootTunMode.rootTun]);
      expect(root.view.snapshot!.state, RootTunState.stopping);
      expect(
        tester
            .widgetList<DashboardConnectedButton>(
              find.byType(DashboardConnectedButton),
            )
            .every((button) => button.onTap == null),
        isTrue,
      );
      root.selectionGate!.complete();
      await tester.pumpAndSettle();
      expect(root.view.snapshot!.mode, RootTunMode.rootTun);
      expect(root.view.snapshot!.state, RootTunState.disabled);
      await tester.tap(find.text('VPN'));
      await tester.pumpAndSettle();
      expect(root.selections, [RootTunMode.rootTun, RootTunMode.vpn]);
      expect(root.view.snapshot!.state, RootTunState.disabled);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed selection retains the previous mode and shows the error',
    (tester) async {
      final root = TestRootTunController()..failSelection = true;
      await pump(tester, root);
      await tester.tap(find.text('Root TUN'));
      await tester.pumpAndSettle();
      expect(root.view.snapshot!.rootTunEnabled, isFalse);
      expect(find.textContaining('switch', findRichText: true), findsWidgets);
      expect(
        tester
            .widgetList<DashboardConnectedButton>(
              find.byType(DashboardConnectedButton),
            )
            .first
            .selected,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
