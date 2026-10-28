import 'dart:async';
import 'dart:convert';

import 'package:android_intent_plus/android_intent.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/root_tun_diagnostics.dart';
import 'package:fl_clash/common/root_tun_labels.dart';
import 'package:fl_clash/models/root_tun.dart';
import 'package:fl_clash/plugins/root_tun.dart';
import 'package:fl_clash/providers/root_tun.dart';
import 'package:fl_clash/views/root_tun_logs.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class RootTunSection extends ConsumerStatefulWidget {
  const RootTunSection({super.key});

  @override
  ConsumerState<RootTunSection> createState() => _RootTunSectionState();
}

class _RootTunSectionState extends ConsumerState<RootTunSection>
    with WidgetsBindingObserver {
  bool _expanded = false;
  bool _exporting = false;
  String? _exportError;

  RootTunController get _controller =>
      ref.read(rootTunControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      Future<void>.microtask(() async {
        if (mounted) await _controller.detectRoot();
      }),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_controller.detectRoot());
  }

  Future<void> _explain(String message, {RootTunSnapshot? failure}) async {
    final confirmed = await dialogs.showMessage(
      context: context,
      title: context.appLocalizations.rootTun,
      message: TextSpan(text: message),
      cancelable: failure != null,
    );
    if (!mounted || confirmed != true || failure == null) return;
    final current = ref.read(rootTunControllerProvider).snapshot;
    if (current?.state == RootTunState.failed &&
        current?.epoch == failure.epoch &&
        current?.lastErrorAt == failure.lastErrorAt) {
      await _controller.stop(RootTunStopReason.acknowledgeFailure);
    }
  }

  Future<void> _feedback(RootTunViewState value) async {
    final snapshot = value.snapshot;
    if (snapshot == null) return;
    final code =
        value.commandError?.code ??
        value.event?.code ??
        snapshot.lastErrorCode ??
        (snapshot.state == RootTunState.awaitingAuth &&
                snapshot.rootManager != RootManager.magisk
            ? RootTunCode.rootGrantRequiredInManager
            : null);
    final managerAuth =
        snapshot.state == RootTunState.awaitingAuth &&
        (snapshot.rootManager == RootManager.kernelSu ||
            snapshot.rootManager == RootManager.apatch);
    final show =
        snapshot.state == RootTunState.failed ||
        managerAuth ||
        code == RootTunCode.cleanupFailed ||
        code == RootTunCode.rootPermissionRevoked ||
        code == RootTunCode.modeSwitchFailed;
    if (!show || code == null) return;
    if (!await _controller.markPromptShown(snapshot, code) || !mounted) return;
    final l = context.appLocalizations;
    final text = rootTunErrorLabel(
      code,
      l,
      manager: rootTunManagerLabel(snapshot.rootManager, l),
    );
    unawaited(
      _explain(
        '$code\n$text${snapshot.state == RootTunState.failed ? '\n${l.rootTunFailureAdvice}' : ''}',
        failure: snapshot.state == RootTunState.failed ? snapshot : null,
      ),
    );
  }

  Future<void> _openManager(RootManager manager) async {
    try {
      await AndroidIntent(
        action: 'android.intent.action.MAIN',
        category: 'android.intent.category.LAUNCHER',
        package: manager == RootManager.kernelSu
            ? 'me.weishu.kernelsu'
            : 'me.bmax.apatch',
      ).launch();
    } catch (_) {
      if (mounted) {
        await _explain(context.appLocalizations.rootTunManagerOpenFailed);
      }
    }
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _exportError = null;
    });
    final l = context.appLocalizations;
    try {
      final result = await ref.read(rootTunPluginProvider).exportDiagnostics();
      final file = result.data;
      if (file == null) {
        throw MessageException(rootTunErrorLabel(result.error!.code, l));
      }
      final saved = await RootTunDiagnosticsExporter(
        isAndroid: system.isAndroid,
      ).export(file, homeDirectory: await appPath.homeDirPath);
      if (mounted && saved) await _explain(l.exportSuccess);
    } catch (error) {
      if (!mounted) return;
      if (error is RootTunChannelException) {
        _controller.recordChannelError(error);
      }
      final text = error is RootTunChannelException && error.notImplemented
          ? l.rootTunExportUnsupported
          : l.rootTunExportFailed('$error');
      setState(() => _exportError = text);
      await _explain(text);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final value = ref.watch(rootTunControllerProvider);
    ref.listen(
      rootTunControllerProvider,
      (_, next) => unawaited(_feedback(next)),
    );
    final snapshot = value.snapshot;
    final busy = value.pendingCommands > 0;
    final unavailable = value.channelAvailable != true;
    final degraded = snapshot?.state == RootTunState.degraded;
    final stale = snapshot?.stale != false;
    final active =
        snapshot != null &&
        snapshot.rootTunEnabled &&
        snapshot.state != RootTunState.failed &&
        snapshot.state != RootTunState.degraded;
    final eventCode = value.event?.code;
    final code =
        value.commandError?.code ??
        (eventCode == RootTunCode.rootGrantNotDetected ? eventCode : null) ??
        snapshot?.lastErrorCode;
    final manager = snapshot == null
        ? 'KernelSU/APatch'
        : rootTunManagerLabel(snapshot.rootManager, l);
    final errorText = code == null
        ? null
        : '$code\n${rootTunErrorLabel(code, l, manager: manager)}';
    final message = [
      if (unavailable)
        value.channelAvailable == null
            ? l.rootTunLoading
            : l.rootTunNativeUnavailable,
      if (snapshot != null && stale) l.rootTunStale,
      ?errorText,
    ].join('\n');
    final enabled = !unavailable && !stale && !degraded && !busy;
    final canToggle = !busy && (active || enabled);
    final awaiting = snapshot?.state == RootTunState.awaitingAuth;
    final managerAuth =
        awaiting &&
        (snapshot?.rootManager == RootManager.kernelSu ||
            snapshot?.rootManager == RootManager.apatch);
    return generateSection(
      title: l.rootTun,
      items: [
        ListItem(
          title: Text(l.rootTun),
          subtitle: message.isEmpty ? null : Text(message),
          trailing: Switch(
            value: active,
            onChanged: canToggle
                ? (on) => on
                      ? _controller.start()
                      : _controller.stop(
                          awaiting
                              ? RootTunStopReason.cancelAuth
                              : RootTunStopReason.disable,
                        )
                : null,
          ),
          onTap: canToggle
              ? () => active
                    ? _controller.stop(
                        awaiting
                            ? RootTunStopReason.cancelAuth
                            : RootTunStopReason.disable,
                      )
                    : _controller.start()
              : () => _explain(message),
        ),
        if (value.autostartSupported)
          ListItem.toggle(
            title: Text(l.rootTunAutostart),
            value: active && snapshot.autostartEnabled,
            onChanged:
                enabled && active && snapshot.authStatus == AuthStatus.granted
                ? _controller.setAutostart
                : null,
          ),
        ListItem(
          title: Text(l.rootTunMode),
          subtitle: Text(
            snapshot == null
                ? l.rootTunNoSnapshot
                : rootTunModeLabel(snapshot.mode, l),
          ),
        ),
        ListItem(
          title: Text(l.status),
          subtitle: Text(
            snapshot == null
                ? l.rootTunNoSnapshot
                : rootTunStateLabel(snapshot.state, l),
          ),
        ),
        ListItem(title: Text(l.rootTunManager), subtitle: Text(manager)),
        ListItem(
          title: Text(l.rootTunAuth),
          subtitle: Text(
            snapshot == null
                ? l.rootTunAuthUnknown
                : rootTunAuthLabel(snapshot.authStatus, l),
          ),
        ),
        if (awaiting && snapshot?.rootManager == RootManager.magisk)
          _AuthCountdown(deadline: snapshot?.authDeadlineAt),
        if (managerAuth) ...[
          ListItem(
            title: Text(l.rootTunManagerGuide),
            subtitle: Text(
              rootTunErrorLabel(
                RootTunCode.rootGrantRequiredInManager,
                l,
                manager: manager,
              ),
            ),
          ),
          ListItem(
            title: Text(l.rootTunOpenManager),
            onTap: () => _openManager(snapshot!.rootManager),
          ),
        ],
        if (awaiting)
          ListItem(
            title: Text(l.cancel),
            onTap: busy
                ? null
                : () => _controller.stop(RootTunStopReason.cancelAuth),
          ),
        ListItem(
          title: Text(
            managerAuth ? l.rootTunAuthorizedRecheck : l.rootTunRecheck,
          ),
          onTap: busy ? null : () => _controller.recheckRoot(),
        ),
        if (snapshot?.state == RootTunState.failed)
          ListItem(
            title: Text(l.confirm),
            onTap: busy
                ? null
                : () => _controller.stop(RootTunStopReason.acknowledgeFailure),
          ),
        for (final warning in snapshot?.warnings ?? <String>[])
          ListItem(
            title: Text(warning),
            subtitle: Text(rootTunErrorLabel(warning, l, manager: manager)),
          ),
        if (value.cleanupSupported && code == RootTunCode.cleanupFailed)
          ListItem(
            title: Text(l.rootTunCleanup),
            onTap: busy || stale ? null : () => _controller.cleanupResidue(),
          ),
        ListItem(
          title: Text(l.rootTunExport),
          subtitle: _exportError == null ? null : Text(_exportError!),
          onTap: _exporting ? null : _export,
        ),
        ListItem.open(
          title: Text(l.rootTunLogs),
          widget: const RootTunLogsView(),
        ),
        ListItem(
          title: Text(l.rootTunDiagnostics),
          onTap: () => setState(() => _expanded = !_expanded),
          subtitle: Text(_expanded ? '−' : '+'),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              [
                '${l.rootTunChannel}: ${value.channelAvailable == true
                    ? l.rootTunChannelAvailable
                    : value.channelAvailable == null
                    ? l.rootTunLoading
                    : l.rootTunNativeUnavailable}',
                '${l.rootTunLastChannelError}: ${value.lastChannelError ?? '—'}',
                if (value.commandError case final error?)
                  'commandError: ${jsonEncode(error.toJson())}',
                if (value.event case final event?)
                  'event: epoch=${event.epoch} seq=${event.seq} code=${event.code} at=${event.at}',
                snapshot == null
                    ? l.rootTunNoSnapshot
                    : const JsonEncoder.withIndent(
                        '  ',
                      ).convert(snapshot.toJson()),
              ].join('\n\n'),
              style: AppTextStyle.caption1.of(context),
            ),
          ),
      ],
    );
  }
}

class _AuthCountdown extends StatefulWidget {
  const _AuthCountdown({required this.deadline});
  final int? deadline;

  @override
  State<_AuthCountdown> createState() => _AuthCountdownState();
}

class _AuthCountdownState extends State<_AuthCountdown> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.deadline == null
        ? null
        : ((widget.deadline! - DateTime.now().millisecondsSinceEpoch) / 1000)
              .ceil()
              .clamp(0, 30);
    return ListItem(
      title: Text(
        remaining == null
            ? context.appLocalizations.rootTunStateAwaitingAuth
            : context.appLocalizations.rootTunAuthCountdown(remaining),
      ),
    );
  }
}
