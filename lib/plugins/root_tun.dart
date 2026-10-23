import 'dart:async';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/snowflake.dart';
import 'package:fl_clash/models/root_tun.dart';
import 'package:flutter/services.dart';

class RootTunChannelException implements Exception {
  const RootTunChannelException(
    this.method,
    this.code,
    this.details, {
    this.requestId,
  });

  final String method;
  final String code;
  final Object? details;
  final String? requestId;

  bool get notImplemented =>
      code == 'notImplemented' || code == 'MissingPluginException';

  @override
  String toString() =>
      '$method: $code ($details)${requestId == null ? '' : ' requestId=$requestId'}';
}

class RootTunPlugin {
  RootTunPlugin({
    MethodChannel methodChannel = const MethodChannel('$packageName/root_tun'),
    EventChannel eventChannel = const EventChannel(
      '$packageName/root_tun/events',
    ),
    this.getterTimeout = const Duration(seconds: 3),
    this.commandTimeout = const Duration(seconds: 2),
  }) : _methods = methodChannel,
       _events = eventChannel;

  final MethodChannel _methods;
  final EventChannel _events;
  final Duration getterTimeout;
  final Duration commandTimeout;

  Future<RootTunResult<T>> _invoke<T>(
    String method,
    Map<String, dynamic> arguments,
    T Function(Map<String, dynamic>) decode, {
    bool command = false,
  }) async {
    try {
      final raw = await _methods
          .invokeMethod<Object?>(method, arguments)
          .timeout(command ? commandTimeout : getterTimeout);
      final result = RootTunResult.decode(raw, decode);
      final error = result.error;
      if (error != null && !RootTunCode.values.contains(error.code)) {
        throw RootTunChannelException(
          method,
          error.code,
          error.details,
          requestId: arguments['requestId'] as String?,
        );
      }
      return result;
    } on RootTunChannelException {
      rethrow;
    } catch (error) {
      throw _channelError(method, error, arguments['requestId'] as String?);
    }
  }

  RootTunChannelException _channelError(
    String method,
    Object error, [
    String? requestId,
  ]) => RootTunChannelException(
    method,
    switch (error) {
      MissingPluginException() => 'MissingPluginException',
      PlatformException(:final code) => code,
      TimeoutException() => 'timeout',
      _ => 'protocolError',
    },
    error is PlatformException ? error.details ?? error.message : '$error',
    requestId: requestId,
  );

  Future<RootTunResult<RootTunSnapshot>> getState() =>
      _invoke('getState', {}, RootTunSnapshot.fromJson);
  Future<RootTunResult<RootTunSnapshot>> detectRoot() =>
      _invoke('detectRoot', {}, RootTunSnapshot.fromJson);

  Future<RootTunResult<RootTunAck>> _command(
    String method,
    String? requestId, [
    Map<String, dynamic> arguments = const {},
  ]) {
    final id = requestId ?? uuidV4;
    return _invoke(method, {'requestId': id, ...arguments}, (json) {
      final ack = RootTunAck.fromJson(json);
      if (ack.requestId != id ||
          ack.intentRevision != ack.snapshot.intentRevision) {
        throw const FormatException('Mismatched Root TUN acknowledgement');
      }
      return ack;
    }, command: true);
  }

  Future<RootTunResult<RootTunAck>> recheckRoot({String? requestId}) =>
      _command('recheckRoot', requestId);
  Future<RootTunResult<RootTunAck>> requestAuth({String? requestId}) =>
      _command('requestAuth', requestId);
  Future<RootTunResult<RootTunAck>> start({String? requestId}) =>
      _command('start', requestId);
  Future<RootTunResult<RootTunAck>> stop(
    RootTunStopReason reason, {
    String? requestId,
  }) => _command('stop', requestId, {'reason': reason.name});
  Future<RootTunResult<RootTunAck>> setAutostart(
    bool enabled, {
    String? requestId,
  }) => _command('setAutostart', requestId, {'enabled': enabled});
  Future<RootTunResult<RootTunAck>> cleanupResidue({String? requestId}) =>
      _command('cleanupResidue', requestId);

  Future<RootTunResult<RootTunLogPage>> getLogs({
    String? cursor,
    int limit = 200,
  }) {
    if (limit < 1 || limit > 500) {
      throw RangeError.range(limit, 1, 500, 'limit');
    }
    return _invoke('getLogs', {
      'cursor': cursor,
      'limit': limit,
    }, RootTunLogPage.fromJson);
  }

  Future<RootTunResult<RootTunDiagnostics>> exportDiagnostics({
    String? requestId,
  }) =>
      _invoke('exportDiagnostics', {'requestId': requestId ?? uuidV4}, (json) {
        final file = RootTunDiagnostics.fromJson(json);
        if (file.path.isEmpty || file.sizeBytes < 0) {
          throw const FormatException('Invalid diagnostics file');
        }
        return file;
      }, command: true);

  Stream<RootTunEvent> events(RootTunSnapshot snapshot) {
    late final StreamController<RootTunEvent> controller;
    final messenger = _events.binaryMessenger;
    final control = MethodChannel(_events.name, _events.codec, messenger);
    // EventChannel reports a missing listen implementation to FlutterError instead
    // of its stream; handle the same wire protocol here so the UI can diagnose it.
    controller = StreamController<RootTunEvent>(
      onListen: () async {
        messenger.setMessageHandler(_events.name, (message) async {
          if (controller.isClosed) return null;
          if (message == null) {
            await controller.close();
            return null;
          }
          try {
            controller.add(
              RootTunEvent.fromMessage(_events.codec.decodeEnvelope(message)),
            );
          } catch (error) {
            controller.addError(_channelError('events', error));
          }
          return null;
        });
        try {
          await control
              .invokeMethod<void>('listen', {
                'schemaVersion': 1,
                'epoch': snapshot.epoch,
                'afterSeq': snapshot.seq,
              })
              .timeout(getterTimeout);
        } catch (error) {
          if (!controller.isClosed) {
            controller.addError(_channelError('events.listen', error));
          }
        }
      },
      onCancel: () async {
        messenger.setMessageHandler(_events.name, null);
        try {
          await control.invokeMethod<void>('cancel').timeout(commandTimeout);
        } catch (_) {
          // Detaching never stops the native/root session.
        }
      },
    );
    return controller.stream;
  }
}
