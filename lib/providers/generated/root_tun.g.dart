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

@ProviderFor(rootTunPreferences)
final rootTunPreferencesProvider = RootTunPreferencesProvider._();

final class RootTunPreferencesProvider
    extends $FunctionalProvider<Preferences, Preferences, Preferences>
    with $Provider<Preferences> {
  RootTunPreferencesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'rootTunPreferencesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$rootTunPreferencesHash();

  @$internal
  @override
  $ProviderElement<Preferences> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Preferences create(Ref ref) {
    return rootTunPreferences(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Preferences value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Preferences>(value),
    );
  }
}

String _$rootTunPreferencesHash() =>
    r'c4c43b963d85684b866391b7f46c864f56efbbaa';

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

String _$rootTunControllerHash() => r'050be43a55f900b64d73beae456ddc05d2a35a0a';

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
