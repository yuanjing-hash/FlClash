import 'dart:async';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/models/root_tun.dart';
import 'package:fl_clash/plugins/root_tun.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/root_tun.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('$packageName/root_tun');
  const eventControl = MethodChannel('$packageName/root_tun/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(eventControl, null);
  });

  test('uses contract maps, UUIDs, stop reasons and Ack semantics', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getState' || call.method == 'detectRoot') {
        return rootTunSuccess(rootTunSnapshotJson());
      }
      final args = rootTunMap(call.arguments);
      return rootTunSuccess({
        'requestId': args['requestId'],
        'intentRevision': 8,
        'disposition': 'accepted',
        'snapshot': rootTunSnapshotJson(state: 'starting'),
      });
    });
    final plugin = RootTunPlugin();
    await plugin.getState();
    await plugin.detectRoot();
    await plugin.recheckRoot();
    await plugin.requestAuth();
    final start = await plugin.start();
    expect(start.data!.snapshot.state, RootTunState.starting);
    for (final reason in RootTunStopReason.values) {
      await plugin.stop(reason);
      expect(rootTunMap(calls.last.arguments)['reason'], reason.name);
    }
    await plugin.setAutostart(false);
    expect(rootTunMap(calls.last.arguments)['enabled'], false);
    await plugin.cleanupResidue();
    expect(calls.first.arguments, isEmpty);
    expect(calls[1].arguments, isEmpty);
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    for (final call in calls.skip(2)) {
      expect(rootTunMap(call.arguments)['requestId'], matches(uuid));
    }
  });

  for (final code in ['missing', 'notImplemented', 'CORE_ERROR']) {
    test(
      'missing native implementation is a diagnostic exception: $code',
      () async {
        if (code != 'missing') {
          messenger.setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(
              code: code,
              details: {'phase': 'connect'},
            ),
          );
        }
        await expectLater(
          RootTunPlugin().getState(),
          throwsA(
            isA<RootTunChannelException>().having(
              (e) => e.code,
              'code',
              code == 'missing' ? 'MissingPluginException' : code,
            ),
          ),
        );
      },
    );
  }

  test(
    'timeouts leave the command running and permit the same requestId retry',
    () async {
      final pending = Completer<Object?>();
      final ids = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) {
        ids.add(rootTunMap(call.arguments)['requestId'] as String);
        return pending.future;
      });
      final plugin = RootTunPlugin(
        commandTimeout: const Duration(milliseconds: 10),
      );
      const id = '7fb480b6-08a9-4113-8505-912671462d51';
      final timeout = isA<RootTunChannelException>()
          .having((e) => e.code, 'code', 'timeout')
          .having((e) => e.requestId, 'requestId', id);
      await expectLater(plugin.start(requestId: id), throwsA(timeout));
      final retry = plugin.start(requestId: id);
      pending.complete(
        rootTunSuccess({
          'requestId': id,
          'intentRevision': 8,
          'disposition': 'coalesced',
          'snapshot': rootTunSnapshotJson(),
        }),
      );
      expect((await retry).data!.disposition, RootTunDisposition.coalesced);
      expect(ids, [id, id]);
    },
  );

  test('log pagination and export Result match the wire contract', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getLogs') {
        expect(call.arguments, {'cursor': 'before', 'limit': 1});
        return rootTunSuccess({
          'sourcePath': '/data/adb/flclash-root/logs',
          'entries': [
            {
              'cursor': '1',
              'at': 123,
              'level': 'info',
              'code': null,
              'message': 'ready',
            },
          ],
          'nextCursor': '1',
          'eof': false,
        });
      }
      expect(call.method, 'exportDiagnostics');
      expect(rootTunMap(call.arguments)['requestId'], isNotEmpty);
      return rootTunSuccess({
        'path': '/data/user/0/app/cache/diagnostics.zip',
        'sizeBytes': 123,
        'mimeType': 'application/zip',
      });
    });
    final plugin = RootTunPlugin();
    expect(
      (await plugin.getLogs(cursor: 'before', limit: 1)).data!.nextCursor,
      '1',
    );
    final diagnostics = (await plugin.exportDiagnostics()).data!;
    expect(diagnostics.sizeBytes, 123);
    expect(diagnostics.mimeType, 'application/zip');
    expect(() => plugin.getLogs(limit: 501), throwsRangeError);
  });

  testWidgets('export has a 20 second timeout, commands 2 and getters 3', (
    tester,
  ) async {
    final pending = <String, Completer<Object?>>{
      for (final method in ['start', 'getState', 'exportDiagnostics'])
        method: Completer<Object?>(),
    };
    messenger.setMockMethodCallHandler(
      channel,
      (call) => pending[call.method]!.future,
    );
    final plugin = RootTunPlugin();
    final timeout = isA<RootTunChannelException>().having(
      (e) => e.code,
      'code',
      'timeout',
    );
    final start = expectLater(plugin.start(), throwsA(timeout));
    var getterDone = false;
    final getter = expectLater(
      plugin.getState(),
      throwsA(timeout),
    ).then((_) => getterDone = true);
    var exported = false;
    final export = plugin.exportDiagnostics().then((result) {
      exported = true;
      return result.data!;
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await start;
    expect(getterDone, false);
    expect(exported, false);
    await tester.pump(const Duration(seconds: 1));
    await getter;
    await tester.pump(const Duration(seconds: 16));
    expect(exported, false);
    pending['exportDiagnostics']!.complete(
      rootTunSuccess({
        'path': '/data/user/0/app/cache/diagnostics.zip',
        'sizeBytes': 123,
        'mimeType': 'application/zip',
      }),
    );
    await tester.pump();
    expect((await export).mimeType, 'application/zip');

    pending['exportDiagnostics'] = Completer<Object?>();
    const id = '7fb480b6-08a9-4113-8505-912671462d51';
    final timedOutExport = expectLater(
      plugin.exportDiagnostics(requestId: id),
      throwsA(timeout.having((e) => e.requestId, 'requestId', id)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    await timedOutExport;
    for (final completer in pending.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    await tester.pump();
  });

  test(
    'missing event listen is delivered through the stream, without FlutterError',
    () async {
      final errors = <Object>[];
      final subscription = RootTunPlugin()
          .events(RootTunSnapshot.fromJson(rootTunSnapshotJson()))
          .listen((_) {}, onError: errors.add);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(errors.single, isA<RootTunChannelException>());
      await subscription.cancel();
    },
  );

  test('event subscription resumes from getState epoch and seq', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(eventControl, (call) async {
      calls.add(call);
      return null;
    });
    final received = <RootTunEvent>[];
    final subscription = RootTunPlugin()
        .events(RootTunSnapshot.fromJson(rootTunSnapshotJson()))
        .listen(received.add);
    await Future<void>.delayed(Duration.zero);
    expect(calls.single.method, 'listen');
    expect(calls.single.arguments, {
      'schemaVersion': 1,
      'epoch': 'boot1',
      'afterSeq': 42,
    });
    await messenger.handlePlatformMessage(
      eventControl.name,
      const StandardMethodCodec().encodeSuccessEnvelope(rootTunEventJson()),
      (_) {},
    );
    expect(received.single.seq, 43);
    await subscription.cancel();
    expect(calls.last.method, 'cancel');
  });
}
