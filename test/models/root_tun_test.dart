import 'package:fl_clash/models/root_tun.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/root_tun.dart';

void main() {
  test('diagnostics MIME type defaults to ZIP and preserves native values', () {
    for (final mimeType in [
      null,
      'application/zip',
      'application/x-zip-compressed',
    ]) {
      final json = <String, dynamic>{
        'path': '/data/user/0/app/cache/diagnostics.zip',
        'sizeBytes': 123,
        'mimeType': ?mimeType,
      };
      final diagnostics = RootTunDiagnostics.fromJson(json);
      expect(diagnostics.mimeType, mimeType ?? 'application/zip');
      expect(RootTunDiagnostics.fromJson(diagnostics.toJson()), diagnostics);
    }
  });

  test('all eight states and supported enum values parse and round trip', () {
    for (final state in RootTunState.values) {
      final json = rootTunSnapshotJson(state: state.name)
        ..['futureField'] = true;
      final snapshot = RootTunSnapshot.fromJson(json);
      expect(snapshot.state, state);
      expect(snapshot.rootManager, RootManager.kernelSu);
      expect(RootTunSnapshot.fromJson(snapshot.toJson()), snapshot);
    }
    expect(RootTunCode.values.length, 27);
  });

  test(
    'required nullable fields, integer types and enum values are strict',
    () {
      for (final key in rootTunSnapshotJson().keys) {
        expect(
          () => RootTunSnapshot.fromJson(rootTunSnapshotJson()..remove(key)),
          throwsA(anything),
          reason: key,
        );
      }
      for (final invalid in [
        {'state': 'authorized'},
        {'rootManager': 'superSu'},
        {'authStatus': 'allowed'},
        {'mode': 'direct'},
        {'schemaVersion': 2},
        {'seq': -1},
        {'seq': 1.5},
        {'intentRevision': -1},
        {'rootTunEnabled': false},
        {'lastErrorCode': 'CORE_ERROR'},
        {
          'warnings': ['UNKNOWN'],
        },
      ]) {
        expect(
          () =>
              RootTunSnapshot.fromJson({...rootTunSnapshotJson(), ...invalid}),
          throwsA(anything),
        );
      }
    },
  );

  test('Result enforces success and failure envelopes', () {
    final result = RootTunResult.decode(
      rootTunSuccess(rootTunSnapshotJson()),
      RootTunSnapshot.fromJson,
    );
    expect(result.data!.state, RootTunState.running);
    expect(result.error, isNull);
    final failure = RootTunResult.decode({
      'ok': false,
      'data': null,
      'error': {
        'code': RootTunCode.rootNotFound,
        'details': {},
        'retryable': false,
      },
    }, RootTunSnapshot.fromJson);
    expect(failure.error!.code, RootTunCode.rootNotFound);
    expect(
      () => RootTunResult.decode({
        'ok': true,
        'data': rootTunSnapshotJson(),
      }, RootTunSnapshot.fromJson),
      throwsFormatException,
    );
    expect(
      () => RootTunResult.decode({
        'ok': false,
        'data': rootTunSnapshotJson(),
        'error': null,
      }, RootTunSnapshot.fromJson),
      throwsFormatException,
    );
  });

  test(
    'delta preserves omitted fields and applies explicit null and code-only events',
    () {
      final initial = RootTunSnapshot.fromJson(
        rootTunSnapshotJson(error: RootTunCode.coreCrashedRecovering),
      );
      final event = RootTunEvent.fromMessage(
        rootTunEventJson(
          changes: {
            'state': 'recovering',
            'lastErrorCode': null,
            'lastErrorAt': null,
          },
        ),
      );
      final merged = event.merge(initial)!;
      expect(merged.seq, 43);
      expect(merged.state, RootTunState.recovering);
      expect(merged.rootManager, initial.rootManager);
      expect(merged.lastErrorCode, isNull);
      expect(merged.lastErrorAt, isNull);
      final info = RootTunEvent.fromMessage(
        rootTunEventJson(seq: 44, baseSeq: 43, code: RootTunCode.coreRecovered),
      );
      expect(info.merge(merged)!.seq, 44);
      expect(info.merge(merged)!.state, RootTunState.recovering);
    },
  );

  test('old events drop, gaps and new-epoch deltas request resync', () {
    final initial = RootTunSnapshot.fromJson(rootTunSnapshotJson());
    expect(
      RootTunEvent.fromMessage(rootTunEventJson(seq: 42)).merge(initial),
      same(initial),
    );
    for (final json in [
      rootTunEventJson(seq: 44),
      rootTunEventJson(baseSeq: 41),
      rootTunEventJson(epoch: 'boot2'),
      rootTunEventJson(changes: {'intentRevision': 7}),
    ]) {
      expect(RootTunEvent.fromMessage(json).merge(initial), isNull);
    }
  });

  test('complete snapshot replaces the mirror on a new epoch', () {
    final initial = RootTunSnapshot.fromJson(rootTunSnapshotJson());
    final json = rootTunSnapshotJson(
      epoch: 'boot2',
      seq: 0,
      revision: 0,
      enabled: false,
      autostart: false,
      state: 'disabled',
    );
    final event = RootTunEvent.fromMessage(
      rootTunEventJson(epoch: 'boot2', seq: 0, snapshot: json),
    );
    expect(event.merge(initial), RootTunSnapshot.fromJson(json));
    expect(
      () => RootTunEvent.fromMessage(rootTunEventJson(snapshot: json)),
      throwsFormatException,
    );
  });
}
