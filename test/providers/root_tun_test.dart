import 'dart:async';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/models/root_tun.dart';
import 'package:fl_clash/plugins/root_tun.dart';
import 'package:fl_clash/providers/root_tun.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/root_tun.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('$packageName/root_tun');
  const events = MethodChannel('$packageName/root_tun/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ProviderContainer container;

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));
  Future<void> send(Map<String, dynamic> json) =>
      messenger.handlePlatformMessage(
        events.name,
        const StandardMethodCodec().encodeSuccessEnvelope(json),
        (_) {},
      );

  setUp(() {
    container = ProviderContainer();
    messenger.setMockMethodCallHandler(events, (_) async => null);
  });
  tearDown(() async {
    container.dispose();
    await settle();
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(events, null);
  });

  for (final code in ['missing', 'notImplemented', 'CORE_ERROR']) {
    test(
      'provider exposes native unavailability instead of an uncaught error: $code',
      () async {
        if (code != 'missing') {
          messenger.setMockMethodCallHandler(
            methods,
            (_) async => throw PlatformException(code: code),
          );
        }
        expect(container.read(rootTunControllerProvider).snapshot, isNull);
        await settle();
        final value = container.read(rootTunControllerProvider);
        expect(value.channelAvailable, false);
        expect(
          value.lastChannelError,
          contains(code == 'missing' ? 'MissingPluginException' : code),
        );
        expect(value.snapshot, isNull);
      },
    );
  }

  test(
    'getState precedes listen; a delta gap resynchronizes and resubscribes',
    () async {
      final order = <String>[];
      var gets = 0;
      messenger.setMockMethodCallHandler(methods, (call) async {
        order.add(call.method);
        return rootTunSuccess(rootTunSnapshotJson(seq: ++gets == 1 ? 42 : 45));
      });
      messenger.setMockMethodCallHandler(events, (call) async {
        order.add(call.method);
        if (call.method == 'listen') {
          expect(rootTunMap(call.arguments)['afterSeq'], gets == 1 ? 42 : 45);
        }
        return null;
      });
      container.read(rootTunControllerProvider);
      await settle();
      expect(order.take(2), ['getState', 'listen']);
      await send(rootTunEventJson(seq: 45, baseSeq: 44));
      await settle();
      expect(gets, 2);
      expect(order, ['getState', 'listen', 'cancel', 'getState', 'listen']);
      expect(container.read(rootTunControllerProvider).snapshot!.seq, 45);
    },
  );

  test('communication failure preserves running snapshot as stale', () async {
    var missing = false;
    messenger.setMockMethodCallHandler(methods, (_) async {
      if (missing) {
        throw PlatformException(
          code: 'CORE_ERROR',
          details: {'phase': 'connect'},
        );
      }
      return rootTunSuccess(rootTunSnapshotJson());
    });
    container.read(rootTunControllerProvider);
    await settle();
    missing = true;
    await container.read(rootTunControllerProvider.notifier).refresh();
    final value = container.read(rootTunControllerProvider);
    expect(value.snapshot!.state, RootTunState.running);
    expect(value.snapshot!.stale, true);
    expect(value.channelAvailable, false);
    expect(value.lastChannelError, contains('CORE_ERROR'));
  });

  test('late Ack cannot overwrite the current intent revision', () async {
    final pending = Completer<Object?>();
    String? requestId;
    messenger.setMockMethodCallHandler(methods, (call) async {
      if (call.method == 'start') {
        requestId = rootTunMap(call.arguments)['requestId'] as String;
        return pending.future;
      }
      return rootTunSuccess(rootTunSnapshotJson());
    });
    container.read(rootTunControllerProvider);
    await settle();
    final command = container.read(rootTunControllerProvider.notifier).start();
    await settle();
    await send(
      rootTunEventJson(changes: {'intentRevision': 10, 'state': 'stopping'}),
    );
    await settle();
    pending.complete(
      rootTunSuccess({
        'requestId': requestId,
        'intentRevision': 9,
        'disposition': 'accepted',
        'snapshot': rootTunSnapshotJson(
          seq: 44,
          revision: 9,
          state: 'starting',
        ),
      }),
    );
    await command;
    final value = container.read(rootTunControllerProvider);
    expect(value.snapshot!.intentRevision, 10);
    expect(value.snapshot!.state, RootTunState.stopping);
    expect(value.pendingCommands, 0);
    expect(value.lastChannelError, isNull);
  });

  test(
    'stale state allows every stop reason and recheck but blocks writes',
    () async {
      final calls = <MethodCall>[];
      final snapshot = rootTunSnapshotJson()..['stale'] = true;
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        if (call.method == 'getState') return rootTunSuccess(snapshot);
        return rootTunSuccess({
          'requestId': rootTunMap(call.arguments)['requestId'],
          'intentRevision': snapshot['intentRevision'],
          'disposition': 'accepted',
          'snapshot': snapshot,
        });
      });
      final controller = container.read(rootTunControllerProvider.notifier);
      await controller.refresh();
      calls.clear();

      await controller.start();
      await controller.setAutostart(false);
      await controller.cleanupResidue();
      expect(calls, isEmpty);

      for (final reason in RootTunStopReason.values) {
        await controller.stop(reason);
        expect(calls.last.method, 'stop');
        expect(rootTunMap(calls.last.arguments)['reason'], reason.name);
      }
      await controller.recheckRoot();
      expect(calls.map((call) => call.method), [
        for (final _ in RootTunStopReason.values) 'stop',
        'getState',
        'recheckRoot',
      ]);
      final value = container.read(rootTunControllerProvider);
      expect(value.snapshot!.stale, true);
      expect(value.pendingCommands, 0);
      expect(value.lastChannelError, isNull);
    },
  );

  for (final code in [
    'notImplemented',
    'MissingPluginException',
    'CORE_ERROR',
  ]) {
    test('autostart capability handles $code and survives refresh', () async {
      messenger.setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'setAutostart') {
          if (code == 'MissingPluginException') throw MissingPluginException();
          throw PlatformException(code: code);
        }
        return rootTunSuccess(rootTunSnapshotJson());
      });
      final controller = container.read(rootTunControllerProvider.notifier);
      await controller.refresh();
      expect(
        container.read(rootTunControllerProvider).autostartSupported,
        true,
      );

      await controller.setAutostart(false);
      await controller.refresh();
      final value = container.read(rootTunControllerProvider);
      expect(value.autostartSupported, code == 'CORE_ERROR');
      expect(value.cleanupSupported, true);
      expect(value.snapshot!.autostartEnabled, true);
      expect(value.pendingCommands, 0);
      expect(value.lastChannelError, contains(code));
    });
  }

  test(
    'a timed-out command refreshes state without sending cancellation',
    () async {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          rootTunPluginProvider.overrideWithValue(
            RootTunPlugin(commandTimeout: const Duration(milliseconds: 10)),
          ),
        ],
      );
      final calls = <String>[];
      final pending = Completer<Object?>();
      messenger.setMockMethodCallHandler(methods, (call) {
        calls.add(call.method);
        if (call.method == 'start') return pending.future;
        return Future.value(rootTunSuccess(rootTunSnapshotJson()));
      });
      container.read(rootTunControllerProvider);
      await settle();
      await container.read(rootTunControllerProvider.notifier).start();
      expect(calls, ['getState', 'start', 'getState']);
      expect(
        container.read(rootTunControllerProvider).lastChannelError,
        contains('requestId='),
      );
      expect(
        container.read(rootTunControllerProvider).snapshot!.state,
        RootTunState.running,
      );
      pending.complete(null);
    },
  );
}
