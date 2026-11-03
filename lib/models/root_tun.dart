import 'package:freezed_annotation/freezed_annotation.dart';

part 'generated/root_tun.freezed.dart';
part 'generated/root_tun.g.dart';

enum RootTunState {
  disabled,
  awaitingAuth,
  starting,
  running,
  recovering,
  stopping,
  failed,
  degraded,
}

enum RootManager {
  magisk,
  @JsonValue('kernelsu')
  kernelSu,
  apatch,
  none,
  unknown,
}

enum AuthStatus { unknown, notGranted, granted, denied, revoked }

enum RootTunMode { rootTun, vpn, off }

enum RootTunStopReason {
  proxyStop,
  disable,
  switchToVpn,
  cancelAuth,
  acknowledgeFailure,
}

enum RootTunDisposition { accepted, coalesced }

enum RootTunLogLevel { debug, info, warn, error }

@freezed
abstract class RootTunSnapshot with _$RootTunSnapshot {
  @JsonSerializable(checked: true, explicitToJson: true)
  const factory RootTunSnapshot({
    @JsonKey(required: true, fromJson: _rootTunInt) required int schemaVersion,
    @JsonKey(required: true) required String epoch,
    @JsonKey(required: true, fromJson: _rootTunInt) required int seq,
    @JsonKey(required: true, fromJson: _rootTunInt) required int intentRevision,
    @JsonKey(required: true) required RootTunState state,
    @JsonKey(required: true) required RootManager rootManager,
    @JsonKey(required: true) required AuthStatus authStatus,
    @JsonKey(required: true) required RootTunMode mode,
    @JsonKey(required: true) required bool rootTunEnabled,
    @JsonKey(required: true) required bool autostartEnabled,
    @JsonKey(required: true) required String? lastErrorCode,
    @JsonKey(required: true, fromJson: _rootTunNullableInt)
    required int? lastErrorAt,
    @JsonKey(required: true) required List<String> warnings,
    @JsonKey(required: true, fromJson: _rootTunNullableInt)
    required int? authDeadlineAt,
    @JsonKey(required: true, fromJson: _rootTunNullableInt)
    required int? startedAt,
    @JsonKey(required: true, fromJson: _rootTunInt) required int updatedAt,
    @JsonKey(required: true) required bool stale,
  }) = _RootTunSnapshot;

  factory RootTunSnapshot.fromJson(Map<String, dynamic> json) =>
      _validateSnapshot(json, _$RootTunSnapshotFromJson(json));
}

@freezed
abstract class RootTunError with _$RootTunError {
  @JsonSerializable(checked: true, explicitToJson: true)
  const factory RootTunError({
    @JsonKey(required: true) required String code,
    @JsonKey(required: true) required Map<String, dynamic> details,
    @JsonKey(required: true) required bool retryable,
  }) = _RootTunError;

  factory RootTunError.fromJson(Map<String, dynamic> json) =>
      _$RootTunErrorFromJson(json);
}

@freezed
abstract class RootTunAck with _$RootTunAck {
  @JsonSerializable(checked: true, explicitToJson: true)
  const factory RootTunAck({
    @JsonKey(required: true) required String requestId,
    @JsonKey(required: true, fromJson: _rootTunInt) required int intentRevision,
    @JsonKey(required: true) required RootTunDisposition disposition,
    @JsonKey(required: true) required RootTunSnapshot snapshot,
  }) = _RootTunAck;

  factory RootTunAck.fromJson(Map<String, dynamic> json) =>
      _$RootTunAckFromJson(json);
}

@freezed
abstract class RootTunLogEntry with _$RootTunLogEntry {
  @JsonSerializable(checked: true, explicitToJson: true)
  const factory RootTunLogEntry({
    @JsonKey(required: true) required String cursor,
    @JsonKey(required: true, fromJson: _rootTunInt) required int at,
    @JsonKey(required: true) required RootTunLogLevel level,
    @JsonKey(required: true) required String? code,
    @JsonKey(required: true) required String message,
  }) = _RootTunLogEntry;

  factory RootTunLogEntry.fromJson(Map<String, dynamic> json) =>
      _$RootTunLogEntryFromJson(json);
}

@freezed
abstract class RootTunLogPage with _$RootTunLogPage {
  @JsonSerializable(checked: true, explicitToJson: true)
  const factory RootTunLogPage({
    @JsonKey(required: true) required String sourcePath,
    @JsonKey(required: true) required List<RootTunLogEntry> entries,
    @JsonKey(required: true) required String? nextCursor,
    @JsonKey(required: true) required bool eof,
  }) = _RootTunLogPage;

  factory RootTunLogPage.fromJson(Map<String, dynamic> json) =>
      _$RootTunLogPageFromJson(json);
}

@freezed
abstract class RootTunDiagnostics with _$RootTunDiagnostics {
  @JsonSerializable(checked: true, explicitToJson: true)
  const factory RootTunDiagnostics({
    @JsonKey(required: true) required String path,
    @JsonKey(required: true, fromJson: _rootTunInt) required int sizeBytes,
    @Default('application/zip') String mimeType,
  }) = _RootTunDiagnostics;

  factory RootTunDiagnostics.fromJson(Map<String, dynamic> json) =>
      _$RootTunDiagnosticsFromJson(json);
}

abstract final class RootTunCode {
  static const rootNotFound = 'ROOT_NOT_FOUND';
  static const rootManagerUnsupported = 'ROOT_MANAGER_UNSUPPORTED';
  static const androidVersionUnsupported = 'ANDROID_VERSION_UNSUPPORTED';
  static const rootPermissionDenied = 'ROOT_PERMISSION_DENIED';
  static const rootGrantRequiredInManager = 'ROOT_GRANT_REQUIRED_IN_MANAGER';
  static const rootGrantNotDetected = 'ROOT_GRANT_NOT_DETECTED';
  static const rootPermissionTimeout = 'ROOT_PERMISSION_TIMEOUT';
  static const rootPermissionRevoked = 'ROOT_PERMISSION_REVOKED';
  static const autostartRootRevoked = 'AUTOSTART_ROOT_REVOKED';
  static const tunDeviceUnsupported = 'TUN_DEVICE_UNSUPPORTED';
  static const tunCreateFailed = 'TUN_CREATE_FAILED';
  static const networkRulesApplyFailed = 'NETWORK_RULES_APPLY_FAILED';
  static const dnsTakeoverFailed = 'DNS_TAKEOVER_FAILED';
  static const coreStartFailed = 'CORE_START_FAILED';
  static const startTimeout = 'START_TIMEOUT';
  static const coreCrashedRecovering = 'CORE_CRASHED_RECOVERING';
  static const coreRecovered = 'CORE_RECOVERED';
  static const coreRecoveryFailed = 'CORE_RECOVERY_FAILED';
  static const coreCrashLoop = 'CORE_CRASH_LOOP';
  static const lastSessionAbnormalExit = 'LAST_SESSION_ABNORMAL_EXIT';
  static const modeSwitching = 'MODE_SWITCHING';
  static const modeSwitchFailed = 'MODE_SWITCH_FAILED';
  static const alwaysOnVpnConflict = 'ALWAYS_ON_VPN_CONFLICT';
  static const privateDnsAutoTakenOver = 'PRIVATE_DNS_AUTO_TAKEN_OVER';
  static const privateDnsStrict = 'PRIVATE_DNS_STRICT';
  static const autostartFailed = 'AUTOSTART_FAILED';
  static const cleanupFailed = 'CLEANUP_FAILED';

  static const values = {
    rootNotFound,
    rootManagerUnsupported,
    androidVersionUnsupported,
    rootPermissionDenied,
    rootGrantRequiredInManager,
    rootGrantNotDetected,
    rootPermissionTimeout,
    rootPermissionRevoked,
    autostartRootRevoked,
    tunDeviceUnsupported,
    tunCreateFailed,
    networkRulesApplyFailed,
    dnsTakeoverFailed,
    coreStartFailed,
    startTimeout,
    coreCrashedRecovering,
    coreRecovered,
    coreRecoveryFailed,
    coreCrashLoop,
    lastSessionAbnormalExit,
    modeSwitching,
    modeSwitchFailed,
    alwaysOnVpnConflict,
    privateDnsAutoTakenOver,
    privateDnsStrict,
    autostartFailed,
    cleanupFailed,
  };
}

Map<String, dynamic> rootTunMap(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Expected a Root TUN map');
  }
  return {
    for (final entry in value.entries)
      entry.key as String: _rootTunValue(entry.value),
  };
}

Object? _rootTunValue(Object? value) => switch (value) {
  Map() => rootTunMap(value),
  List() => value.map(_rootTunValue).toList(),
  _ => value,
};

class RootTunResult<T> {
  const RootTunResult.success(T value) : data = value, error = null;
  const RootTunResult.failure(RootTunError value) : data = null, error = value;

  final T? data;
  final RootTunError? error;

  static RootTunResult<T> decode<T>(
    Object? value,
    T Function(Map<String, dynamic>) decode,
  ) {
    final json = rootTunMap(value);
    if (!json.containsKey('data') || !json.containsKey('error')) {
      throw const FormatException('Incomplete Root TUN result');
    }
    if (json['ok'] == true && json['error'] == null && json['data'] != null) {
      return RootTunResult.success(decode(rootTunMap(json['data'])));
    }
    if (json['ok'] == false && json['data'] == null && json['error'] != null) {
      return RootTunResult.failure(
        RootTunError.fromJson(rootTunMap(json['error'])),
      );
    }
    throw const FormatException('Invalid Root TUN result');
  }
}

class RootTunEvent {
  RootTunEvent._({
    required this.epoch,
    required this.seq,
    required this.at,
    required this.requestId,
    required this.code,
    this.snapshot,
    this.baseSeq,
    this.changes,
  });

  factory RootTunEvent.fromMessage(Object? message) {
    final json = rootTunMap(message);
    final epoch = json['epoch'];
    final seq = json['seq'];
    if (json['schemaVersion'] != 1 ||
        epoch is! String ||
        epoch.isEmpty ||
        seq is! int ||
        seq < 0 ||
        json['at'] is! int ||
        !json.containsKey('requestId') ||
        !json.containsKey('code') ||
        (json['requestId'] != null && json['requestId'] is! String) ||
        (json['code'] != null && !RootTunCode.values.contains(json['code']))) {
      throw const FormatException('Invalid Root TUN event');
    }
    final kind = json['kind'];
    final snapshot = kind == 'snapshot'
        ? RootTunSnapshot.fromJson(rootTunMap(json['snapshot']))
        : null;
    if (kind != 'snapshot' && kind != 'delta' ||
        snapshot != null && (snapshot.epoch != epoch || snapshot.seq != seq) ||
        kind == 'delta' &&
            (json['baseSeq'] is! int || (json['baseSeq'] as int) < 0)) {
      throw const FormatException('Invalid Root TUN event sequence');
    }
    return RootTunEvent._(
      epoch: epoch,
      seq: seq,
      at: json['at'] as int,
      requestId: json['requestId'] as String?,
      code: json['code'] as String?,
      snapshot: snapshot,
      baseSeq: json['baseSeq'] as int?,
      changes: kind == 'delta' ? rootTunMap(json['changes']) : null,
    );
  }

  final String epoch;
  final int seq;
  final int at;
  final String? requestId;
  final String? code;
  final RootTunSnapshot? snapshot;
  final int? baseSeq;
  final Map<String, dynamic>? changes;

  // A null merge requests getState and a new subscription; old events are ignored.
  RootTunSnapshot? merge(RootTunSnapshot current) {
    if (epoch == current.epoch && seq <= current.seq) return current;
    if (snapshot != null) {
      if (epoch == current.epoch &&
          snapshot!.intentRevision < current.intentRevision) {
        return null;
      }
      return snapshot;
    }
    if (epoch != current.epoch ||
        baseSeq != current.seq ||
        seq != current.seq + 1) {
      return null;
    }
    final merged = RootTunSnapshot.fromJson({
      ...current.toJson(),
      ...?changes,
      'epoch': epoch,
      'seq': seq,
    });
    return merged.intentRevision < current.intentRevision ? null : merged;
  }
}

@freezed
abstract class RootTunViewState with _$RootTunViewState {
  const factory RootTunViewState({
    RootTunSnapshot? snapshot,
    bool? channelAvailable,
    String? lastChannelError,
    RootTunError? commandError,
    RootTunEvent? event,
    @Default(0) int pendingCommands,
    @Default(true) bool cleanupSupported,
    @Default(true) bool autostartSupported,
  }) = _RootTunViewState;
}

RootTunSnapshot _validateSnapshot(
  Map<String, dynamic> json,
  RootTunSnapshot snapshot,
) {
  const integers = ['schemaVersion', 'seq', 'intentRevision', 'updatedAt'];
  const nullableIntegers = ['lastErrorAt', 'authDeadlineAt', 'startedAt'];
  if (integers.any((key) => json[key] is! int) ||
      nullableIntegers.any((key) => json[key] != null && json[key] is! int) ||
      snapshot.schemaVersion != 1 ||
      snapshot.epoch.isEmpty ||
      snapshot.seq < 0 ||
      snapshot.intentRevision < 0 ||
      (!snapshot.rootTunEnabled && snapshot.autostartEnabled) ||
      (snapshot.lastErrorCode != null &&
          !RootTunCode.values.contains(snapshot.lastErrorCode)) ||
      snapshot.warnings.any((code) => !RootTunCode.values.contains(code))) {
    throw const FormatException('Invalid Root TUN snapshot');
  }
  return snapshot;
}

int _rootTunInt(Object? value) {
  if (value is! int) throw const FormatException('Expected a Root TUN integer');
  return value;
}

int? _rootTunNullableInt(Object? value) =>
    value == null ? null : _rootTunInt(value);
