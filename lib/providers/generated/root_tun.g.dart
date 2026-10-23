// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../root_tun.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(rootTunPlugin)
final rootTunPluginProvider = RootTunPluginProvider._();

final class RootTunPluginProvider
    extends $FunctionalProvider<RootTunPlugin, RootTunPlugin, RootTunPlugin>
    with $Provider<RootTunPlugin> {
  RootTunPluginProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'rootTunPluginProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$rootTunPluginHash();

  @$internal
  @override
  $ProviderElement<RootTunPlugin> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RootTunPlugin create(Ref ref) {
    return rootTunPlugin(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RootTunPlugin value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RootTunPlugin>(value),
    );
  }
}

String _$rootTunPluginHash() => r'8994a3fd2d562669028e77523e28aa379e18255b';

@ProviderFor(RootTunController)
final rootTunControllerProvider = RootTunControllerProvider._();

final class RootTunControllerProvider
    extends $NotifierProvider<RootTunController, RootTunViewState> {
  RootTunControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'rootTunControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$rootTunControllerHash();

  @$internal
  @override
  RootTunController create() => RootTunController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RootTunViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RootTunViewState>(value),
    );
  }
}

String _$rootTunControllerHash() => r'3f480f0535c4ff85f27d6428749f5fab937759dd';

abstract class _$RootTunController extends $Notifier<RootTunViewState> {
  RootTunViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RootTunViewState, RootTunViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RootTunViewState, RootTunViewState>,
              RootTunViewState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
