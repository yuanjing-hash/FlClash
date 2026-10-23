// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../root_tun.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RootTunSnapshot _$RootTunSnapshotFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('_RootTunSnapshot', json, ($checkedConvert) {
  $checkKeys(
    json,
    requiredKeys: const [
      'schemaVersion',
      'epoch',
      'seq',
      'intentRevision',
      'state',
      'rootManager',
      'authStatus',
      'mode',
      'rootTunEnabled',
      'autostartEnabled',
      'lastErrorCode',
      'lastErrorAt',
      'warnings',
      'authDeadlineAt',
      'startedAt',
      'updatedAt',
      'stale',
    ],
  );
  final val = _RootTunSnapshot(
    schemaVersion: $checkedConvert('schemaVersion', (v) => _rootTunInt(v)),
    epoch: $checkedConvert('epoch', (v) => v as String),
    seq: $checkedConvert('seq', (v) => _rootTunInt(v)),
    intentRevision: $checkedConvert('intentRevision', (v) => _rootTunInt(v)),
    state: $checkedConvert(
      'state',
      (v) => $enumDecode(_$RootTunStateEnumMap, v),
    ),
    rootManager: $checkedConvert(
      'rootManager',
      (v) => $enumDecode(_$RootManagerEnumMap, v),
    ),
    authStatus: $checkedConvert(
      'authStatus',
      (v) => $enumDecode(_$AuthStatusEnumMap, v),
    ),
    mode: $checkedConvert('mode', (v) => $enumDecode(_$RootTunModeEnumMap, v)),
    rootTunEnabled: $checkedConvert('rootTunEnabled', (v) => v as bool),
    autostartEnabled: $checkedConvert('autostartEnabled', (v) => v as bool),
    lastErrorCode: $checkedConvert('lastErrorCode', (v) => v as String?),
    lastErrorAt: $checkedConvert('lastErrorAt', (v) => _rootTunNullableInt(v)),
    warnings: $checkedConvert(
      'warnings',
      (v) => (v as List<dynamic>).map((e) => e as String).toList(),
    ),
    authDeadlineAt: $checkedConvert(
      'authDeadlineAt',
      (v) => _rootTunNullableInt(v),
    ),
    startedAt: $checkedConvert('startedAt', (v) => _rootTunNullableInt(v)),
    updatedAt: $checkedConvert('updatedAt', (v) => _rootTunInt(v)),
    stale: $checkedConvert('stale', (v) => v as bool),
  );
  return val;
});

Map<String, dynamic> _$RootTunSnapshotToJson(_RootTunSnapshot instance) =>
    <String, dynamic>{
      'schemaVersion': instance.schemaVersion,
      'epoch': instance.epoch,
      'seq': instance.seq,
      'intentRevision': instance.intentRevision,
      'state': _$RootTunStateEnumMap[instance.state]!,
      'rootManager': _$RootManagerEnumMap[instance.rootManager]!,
      'authStatus': _$AuthStatusEnumMap[instance.authStatus]!,
      'mode': _$RootTunModeEnumMap[instance.mode]!,
      'rootTunEnabled': instance.rootTunEnabled,
      'autostartEnabled': instance.autostartEnabled,
      'lastErrorCode': instance.lastErrorCode,
      'lastErrorAt': instance.lastErrorAt,
      'warnings': instance.warnings,
      'authDeadlineAt': instance.authDeadlineAt,
      'startedAt': instance.startedAt,
      'updatedAt': instance.updatedAt,
      'stale': instance.stale,
    };

const _$RootTunStateEnumMap = {
  RootTunState.disabled: 'disabled',
  RootTunState.awaitingAuth: 'awaitingAuth',
  RootTunState.starting: 'starting',
  RootTunState.running: 'running',
  RootTunState.recovering: 'recovering',
  RootTunState.stopping: 'stopping',
  RootTunState.failed: 'failed',
  RootTunState.degraded: 'degraded',
};

const _$RootManagerEnumMap = {
  RootManager.magisk: 'magisk',
  RootManager.kernelSu: 'kernelsu',
  RootManager.apatch: 'apatch',
  RootManager.none: 'none',
  RootManager.unknown: 'unknown',
};

const _$AuthStatusEnumMap = {
  AuthStatus.unknown: 'unknown',
  AuthStatus.notGranted: 'notGranted',
  AuthStatus.granted: 'granted',
  AuthStatus.denied: 'denied',
  AuthStatus.revoked: 'revoked',
};

const _$RootTunModeEnumMap = {
  RootTunMode.rootTun: 'rootTun',
  RootTunMode.vpn: 'vpn',
  RootTunMode.off: 'off',
};

_RootTunError _$RootTunErrorFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_RootTunError', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['code', 'details', 'retryable']);
      final val = _RootTunError(
        code: $checkedConvert('code', (v) => v as String),
        details: $checkedConvert('details', (v) => v as Map<String, dynamic>),
        retryable: $checkedConvert('retryable', (v) => v as bool),
      );
      return val;
    });

Map<String, dynamic> _$RootTunErrorToJson(_RootTunError instance) =>
    <String, dynamic>{
      'code': instance.code,
      'details': instance.details,
      'retryable': instance.retryable,
    };

_RootTunAck _$RootTunAckFromJson(Map<String, dynamic> json) => $checkedCreate(
  '_RootTunAck',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'requestId',
        'intentRevision',
        'disposition',
        'snapshot',
      ],
    );
    final val = _RootTunAck(
      requestId: $checkedConvert('requestId', (v) => v as String),
      intentRevision: $checkedConvert('intentRevision', (v) => _rootTunInt(v)),
      disposition: $checkedConvert(
        'disposition',
        (v) => $enumDecode(_$RootTunDispositionEnumMap, v),
      ),
      snapshot: $checkedConvert(
        'snapshot',
        (v) => RootTunSnapshot.fromJson(v as Map<String, dynamic>),
      ),
    );
    return val;
  },
);

Map<String, dynamic> _$RootTunAckToJson(_RootTunAck instance) =>
    <String, dynamic>{
      'requestId': instance.requestId,
      'intentRevision': instance.intentRevision,
      'disposition': _$RootTunDispositionEnumMap[instance.disposition]!,
      'snapshot': instance.snapshot.toJson(),
    };

const _$RootTunDispositionEnumMap = {
  RootTunDisposition.accepted: 'accepted',
  RootTunDisposition.coalesced: 'coalesced',
};

_RootTunLogEntry _$RootTunLogEntryFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_RootTunLogEntry', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['cursor', 'at', 'level', 'code', 'message'],
      );
      final val = _RootTunLogEntry(
        cursor: $checkedConvert('cursor', (v) => v as String),
        at: $checkedConvert('at', (v) => _rootTunInt(v)),
        level: $checkedConvert(
          'level',
          (v) => $enumDecode(_$RootTunLogLevelEnumMap, v),
        ),
        code: $checkedConvert('code', (v) => v as String?),
        message: $checkedConvert('message', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$RootTunLogEntryToJson(_RootTunLogEntry instance) =>
    <String, dynamic>{
      'cursor': instance.cursor,
      'at': instance.at,
      'level': _$RootTunLogLevelEnumMap[instance.level]!,
      'code': instance.code,
      'message': instance.message,
    };

const _$RootTunLogLevelEnumMap = {
  RootTunLogLevel.debug: 'debug',
  RootTunLogLevel.info: 'info',
  RootTunLogLevel.warn: 'warn',
  RootTunLogLevel.error: 'error',
};

_RootTunLogPage _$RootTunLogPageFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_RootTunLogPage', json, ($checkedConvert) {
      $checkKeys(
        json,
        requiredKeys: const ['sourcePath', 'entries', 'nextCursor', 'eof'],
      );
      final val = _RootTunLogPage(
        sourcePath: $checkedConvert('sourcePath', (v) => v as String),
        entries: $checkedConvert(
          'entries',
          (v) => (v as List<dynamic>)
              .map((e) => RootTunLogEntry.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        nextCursor: $checkedConvert('nextCursor', (v) => v as String?),
        eof: $checkedConvert('eof', (v) => v as bool),
      );
      return val;
    });

Map<String, dynamic> _$RootTunLogPageToJson(_RootTunLogPage instance) =>
    <String, dynamic>{
      'sourcePath': instance.sourcePath,
      'entries': instance.entries.map((e) => e.toJson()).toList(),
      'nextCursor': instance.nextCursor,
      'eof': instance.eof,
    };

_RootTunDiagnostics _$RootTunDiagnosticsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_RootTunDiagnostics', json, ($checkedConvert) {
      $checkKeys(json, requiredKeys: const ['path', 'sizeBytes']);
      final val = _RootTunDiagnostics(
        path: $checkedConvert('path', (v) => v as String),
        sizeBytes: $checkedConvert('sizeBytes', (v) => _rootTunInt(v)),
      );
      return val;
    });

Map<String, dynamic> _$RootTunDiagnosticsToJson(_RootTunDiagnostics instance) =>
    <String, dynamic>{'path': instance.path, 'sizeBytes': instance.sizeBytes};
