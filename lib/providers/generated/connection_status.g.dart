// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../connection_status.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(connectionPhase)
final connectionPhaseProvider = ConnectionPhaseFamily._();

final class ConnectionPhaseProvider
    extends
        $FunctionalProvider<ConnectionPhase, ConnectionPhase, ConnectionPhase>
    with $Provider<ConnectionPhase> {
  ConnectionPhaseProvider._({
    required ConnectionPhaseFamily super.from,
    required SupportPlatform? super.argument,
  }) : super(
         retry: null,
         name: r'connectionPhaseProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$connectionPhaseHash();

  @override
  String toString() {
    return r'connectionPhaseProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ConnectionPhase> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ConnectionPhase create(Ref ref) {
    final argument = this.argument as SupportPlatform?;
    return connectionPhase(ref, platform: argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectionPhase value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectionPhase>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ConnectionPhaseProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$connectionPhaseHash() => r'940334841b1f8184a13d2ffffe1971602423b52b';

final class ConnectionPhaseFamily extends $Family
    with $FunctionalFamilyOverride<ConnectionPhase, SupportPlatform?> {
  ConnectionPhaseFamily._()
    : super(
        retry: null,
        name: r'connectionPhaseProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ConnectionPhaseProvider call({SupportPlatform? platform}) =>
      ConnectionPhaseProvider._(argument: platform, from: this);

  @override
  String toString() => r'connectionPhaseProvider';
}
