import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/models/root_tun.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/root_tun.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/config/root_tun.dart';
import 'package:fl_clash/views/root_tun_logs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/app_paths.dart';
import '../helpers/test_app.dart';
import '../support/root_tun.dart';

class _SavingPicker extends FilePickerPlatform {
  final saved = Completer<void>();
  String? savedMimeType;
  Uint8List? savedBytes;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedMimeType = mimeType;
    savedBytes = bytes;
    saved.complete();
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('$packageName/root_tun');
  const events = MethodChannel('$packageName/root_tun/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ProviderContainer container;
  late Map<String, dynamic> snapshot;
  late List<MethodCall> calls;
  late String? autostartError;
  late Map<String, dynamic>? diagnostics;
  late Directory directory;
  late FilePickerPlatform originalPicker;
  late _SavingPicker savingPicker;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('root_tun_view_');
    await useAppPaths(directory);
    originalPicker = FilePickerPlatform.instance;
    savingPicker = _SavingPicker();
    FilePickerPlatform.instance = savingPicker;
    autostartError = null;
    diagnostics = null;
    container = ProviderContainer();
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(400, 1800);
    snapshot = rootTunSnapshotJson(
      state: 'disabled',
      enabled: false,
      autostart: false,
    );
    calls = [];
    messenger.setMockMethodCallHandler(events, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'getState' || call.method == 'detectRoot') {
        return rootTunSuccess(snapshot);
      }
      if (call.method == 'setAutostart' && autostartError != null) {
        if (autostartError == 'MissingPluginException') {
          throw MissingPluginException();
        }
        throw PlatformException(code: autostartError!);
      }
      if (call.method == 'exportDiagnostics' && diagnostics != null) {
        return rootTunSuccess(diagnostics!);
      }
      if (call.method == 'exportDiagnostics' || call.method == 'getLogs') {
        throw MissingPluginException();
      }
      final arguments = rootTunMap(call.arguments);
      return rootTunSuccess({
        'requestId': arguments['requestId'],
        'intentRevision': 8,
        'disposition': 'accepted',
        'snapshot': snapshot,
      });
    });
  });
  tearDown(() async {
    container.dispose();
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
    FilePickerPlatform.instance = originalPicker;
    await directory.delete(recursive: true);
  });

  Future<void> pump(
    WidgetTester tester, {
    Widget? view,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          locale: const Locale('zh', 'CN'),
          themeMode: themeMode,
          child: Scaffold(
            body: view ?? ListView(children: const [RootTunSection()]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'degraded switch stays visible, disabled and explains the reason on tap',
    (tester) async {
      snapshot = rootTunSnapshotJson(
        state: 'degraded',
        enabled: false,
        autostart: false,
        manager: 'none',
        auth: 'notGranted',
        error: RootTunCode.rootNotFound,
      );
      await pump(tester);
      final toggle = tester.widget<Switch>(find.byType(Switch).first);
      expect(toggle.value, false);
      expect(toggle.onChanged, isNull);
      expect(find.textContaining('未检测到 root 权限'), findsOneWidget);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('未检测到 root 权限'), findsNWidgets(2));
      expect(calls.where((call) => call.method == 'start'), isEmpty);
      await tester.tap(find.text('确定').last);
      await tester.pumpAndSettle();
    },
  );

  for (final active in [false, true]) {
    testWidgets(
      'stale switch permits disabling only (active=$active) and recheck',
      (tester) async {
        snapshot = rootTunSnapshotJson(
          state: active ? 'running' : 'disabled',
          enabled: active,
          autostart: false,
        )..['stale'] = true;
        await pump(tester);
        expect(find.textContaining('状态核对中'), findsOneWidget);
        final toggle = tester.widget<Switch>(find.byType(Switch).first);
        expect(toggle.value, active);
        expect(toggle.onChanged, active ? isNotNull : isNull);
        expect(
          tester.widget<Switch>(find.byType(Switch).last).onChanged,
          isNull,
        );
        if (active) {
          await tester.tap(find.byType(Switch).first);
          await tester.pumpAndSettle();
          expect(
            rootTunMap(
              calls.lastWhere((call) => call.method == 'stop').arguments,
            )['reason'],
            'disable',
          );
        }
        await tester.tap(find.text('重新检测'));
        await tester.pumpAndSettle();
        expect(calls.any((call) => call.method == 'recheckRoot'), true);
        expect(calls.where((call) => call.method == 'start'), isEmpty);
      },
    );
  }

  for (final code in ['notImplemented', 'MissingPluginException']) {
    testWidgets('unsupported autostart is hidden after $code', (tester) async {
      snapshot = rootTunSnapshotJson(autostart: false);
      autostartError = code;
      await pump(tester);
      expect(find.text('开机自启'), findsOneWidget);
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(calls.any((call) => call.method == 'setAutostart'), true);
      expect(find.text('开机自启'), findsNothing);
      expect(find.byType(Switch), findsOneWidget);
      expect(
        container.read(rootTunControllerProvider).lastChannelError,
        contains(code),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Flutter saves diagnostics with the native MIME type', (
    tester,
  ) async {
    final file = File('${directory.path}/diagnostics.zip');
    final bytes = Uint8List.fromList([80, 75, 3, 4]);
    await tester.runAsync(() => file.writeAsBytes(bytes));
    diagnostics = {
      'path': file.path,
      'sizeBytes': bytes.length,
      'mimeType': 'application/x-zip-compressed',
    };
    await pump(tester);
    await tester.ensureVisible(find.text('导出诊断日志'));
    await tester.runAsync(() async {
      await tester.tap(find.text('导出诊断日志'));
      await savingPicker.saved.future.timeout(const Duration(seconds: 5));
    });
    await tester.pumpAndSettle();
    expect(savingPicker.savedMimeType, diagnostics!['mimeType']);
    expect(savingPicker.savedBytes, bytes);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'KernelSU awaitingAuth has manager guidance, recheck and cancel without a countdown',
    (tester) async {
      snapshot = rootTunSnapshotJson(
        state: 'awaitingAuth',
        auth: 'notGranted',
        autostart: false,
        error: RootTunCode.rootGrantRequiredInManager,
      )..['stale'] = true;
      await pump(tester);
      await tester.tap(find.text('确定').last);
      await tester.pumpAndSettle();
      expect(find.text('请到管理器中给 FlClash 授权'), findsOneWidget);
      expect(find.text('打开管理器'), findsOneWidget);
      expect(find.text('我已授权，重新检测'), findsOneWidget);
      expect(find.textContaining('剩余'), findsNothing);
      await tester.pump(const Duration(seconds: 31));
      expect(
        container.read(rootTunControllerProvider).snapshot!.state,
        RootTunState.awaitingAuth,
      );
      await tester.tap(find.text('我已授权，重新检测'));
      await tester.pumpAndSettle();
      expect(calls.any((call) => call.method == 'recheckRoot'), true);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        rootTunMap(
          calls.lastWhere((call) => call.method == 'stop').arguments,
        )['reason'],
        'cancelAuth',
      );
    },
  );

  testWidgets(
    'Magisk countdown displays the deadline without cancelling native authorization',
    (tester) async {
      snapshot = rootTunSnapshotJson(
        state: 'awaitingAuth',
        manager: 'magisk',
        auth: 'notGranted',
        autostart: false,
      )..['authDeadlineAt'] = DateTime.now().millisecondsSinceEpoch + 30000;
      await pump(tester);
      expect(find.textContaining('等待 root 授权，剩余'), findsOneWidget);
      expect(find.text('打开管理器'), findsNothing);
      await tester.pump(const Duration(seconds: 31));
      expect(calls.where((call) => call.method == 'stop'), isEmpty);
      expect(
        container.read(rootTunControllerProvider).snapshot!.state,
        RootTunState.awaitingAuth,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('failed confirmation acknowledges failure and autostart is off', (
    tester,
  ) async {
    snapshot = rootTunSnapshotJson(
      state: 'failed',
      error: RootTunCode.coreStartFailed,
    )..['stale'] = true;
    await pump(tester);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, false);
    expect(tester.widget<Switch>(find.byType(Switch).last).value, false);
    await tester.tap(find.text('确定').last);
    await tester.pumpAndSettle();
    expect(
      rootTunMap(
        calls.lastWhere((call) => call.method == 'stop').arguments,
      )['reason'],
      'acknowledgeFailure',
    );
  });

  testWidgets(
    'missing native channel exposes diagnostic details and export fallback',
    (tester) async {
      messenger.setMockMethodCallHandler(
        methods,
        (_) async => throw MissingPluginException(),
      );
      await pump(tester, themeMode: ThemeMode.dark);
      expect(find.textContaining('原生层未就绪'), findsOneWidget);
      await tester.ensureVisible(find.text('诊断信息'));
      await tester.tap(find.text('诊断信息'));
      await tester.pumpAndSettle();
      expect(find.textContaining('MissingPluginException'), findsOneWidget);
      await tester.ensureVisible(find.text('导出诊断日志'));
      await tester.tap(find.text('导出诊断日志'));
      await tester.pumpAndSettle();
      expect(find.text('原生端尚未支持导出诊断'), findsNWidgets(2));
      await tester.tap(find.text('确定').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'logs paginate and keep native paths visible without reading root files',
    (tester) async {
      var pages = 0;
      messenger.setMockMethodCallHandler(methods, (call) async {
        if (call.method != 'getLogs') return rootTunSuccess(snapshot);
        final args = rootTunMap(call.arguments);
        expect(args['cursor'], pages == 0 ? null : '1');
        pages++;
        return rootTunSuccess({
          'sourcePath': '/data/adb/flclash-root/logs',
          'entries': [
            {
              'cursor': '$pages',
              'at': 123,
              'level': 'info',
              'code': null,
              'message': 'entry $pages',
            },
          ],
          'nextCursor': pages == 1 ? '1' : null,
          'eof': pages == 2,
        });
      });
      await pump(tester, view: const RootTunLogsView());
      expect(find.text('/data/adb/flclash-root/logs'), findsOneWidget);
      expect(find.textContaining('entry 1'), findsOneWidget);
      await tester.tap(find.text('加载更多'));
      await tester.pumpAndSettle();
      expect(find.textContaining('entry 2'), findsOneWidget);
      expect(pages, 2);
    },
  );
}
