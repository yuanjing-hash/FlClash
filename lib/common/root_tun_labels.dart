import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/root_tun.dart';

String rootTunStateLabel(RootTunState value, AppLocalizations l) =>
    switch (value) {
      RootTunState.disabled => l.rootTunStateDisabled,
      RootTunState.awaitingAuth => l.rootTunStateAwaitingAuth,
      RootTunState.starting => l.rootTunStateStarting,
      RootTunState.running => l.rootTunStateRunning,
      RootTunState.recovering => l.rootTunStateRecovering,
      RootTunState.stopping => l.rootTunStateStopping,
      RootTunState.failed => l.rootTunStateFailed,
      RootTunState.degraded => l.rootTunStateDegraded,
    };

String rootTunManagerLabel(RootManager value, AppLocalizations l) =>
    switch (value) {
      RootManager.magisk => 'Magisk',
      RootManager.kernelSu => 'KernelSU',
      RootManager.apatch => 'APatch',
      RootManager.none => l.rootTunManagerNone,
      RootManager.unknown => l.rootTunManagerUnknown,
    };

String rootTunAuthLabel(AuthStatus value, AppLocalizations l) =>
    switch (value) {
      AuthStatus.unknown => l.rootTunAuthUnknown,
      AuthStatus.notGranted => l.rootTunAuthNotGranted,
      AuthStatus.granted => l.rootTunAuthGranted,
      AuthStatus.denied => l.rootTunAuthDenied,
      AuthStatus.revoked => l.rootTunAuthRevoked,
    };

String rootTunModeLabel(RootTunMode value, AppLocalizations l) =>
    switch (value) {
      RootTunMode.rootTun => l.rootTun,
      RootTunMode.vpn => 'VPN',
      RootTunMode.off => l.rootTunOff,
    };

String rootTunErrorLabel(
  String code,
  AppLocalizations l, {
  String manager = 'KernelSU/APatch',
}) => switch (code) {
  RootTunCode.rootNotFound => l.rootTunErrorRootNotFound,
  RootTunCode.rootManagerUnsupported => l.rootTunErrorRootManagerUnsupported,
  RootTunCode.androidVersionUnsupported =>
    l.rootTunErrorAndroidVersionUnsupported,
  RootTunCode.rootPermissionDenied => l.rootTunErrorRootPermissionDenied,
  RootTunCode.rootGrantRequiredInManager =>
    l.rootTunErrorRootGrantRequiredInManager(manager),
  RootTunCode.rootGrantNotDetected => l.rootTunErrorRootGrantNotDetected(
    manager,
  ),
  RootTunCode.rootPermissionTimeout => l.rootTunErrorRootPermissionTimeout,
  RootTunCode.rootPermissionRevoked => l.rootTunErrorRootPermissionRevoked,
  RootTunCode.autostartRootRevoked => l.rootTunErrorAutostartRootRevoked,
  RootTunCode.tunDeviceUnsupported => l.rootTunErrorTunDeviceUnsupported,
  RootTunCode.tunCreateFailed => l.rootTunErrorTunCreateFailed,
  RootTunCode.networkRulesApplyFailed => l.rootTunErrorNetworkRulesApplyFailed,
  RootTunCode.dnsTakeoverFailed => l.rootTunErrorDnsTakeoverFailed,
  RootTunCode.coreStartFailed => l.rootTunErrorCoreStartFailed,
  RootTunCode.startTimeout => l.rootTunErrorStartTimeout,
  RootTunCode.coreCrashedRecovering => l.rootTunErrorCoreCrashedRecovering,
  RootTunCode.coreRecovered => l.rootTunErrorCoreRecovered,
  RootTunCode.coreRecoveryFailed => l.rootTunErrorCoreRecoveryFailed,
  RootTunCode.coreCrashLoop => l.rootTunErrorCoreCrashLoop,
  RootTunCode.lastSessionAbnormalExit => l.rootTunErrorLastSessionAbnormalExit,
  RootTunCode.modeSwitching => l.rootTunErrorModeSwitching,
  RootTunCode.modeSwitchFailed => l.rootTunErrorModeSwitchFailed,
  RootTunCode.alwaysOnVpnConflict => l.rootTunErrorAlwaysOnVpnConflict,
  RootTunCode.privateDnsAutoTakenOver => l.rootTunErrorPrivateDnsAutoTakenOver,
  RootTunCode.privateDnsStrict => l.rootTunErrorPrivateDnsStrict,
  RootTunCode.autostartFailed => l.rootTunErrorAutostartFailed,
  RootTunCode.cleanupFailed => l.rootTunErrorCleanupFailed,
  _ => code,
};
