import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/root_tun_labels.dart';
import 'package:fl_clash/models/root_tun.dart';
import 'package:fl_clash/providers/root_tun.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';

class ConnectionModeCard extends ConsumerWidget {
  const ConnectionModeCard({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(rootTunControllerProvider);
    final snapshot = value.snapshot;
    final selected = snapshot?.mode == RootTunMode.rootTun
        ? RootTunMode.rootTun
        : RootTunMode.vpn;
    final enabled =
        value.channelAvailable == true &&
        snapshot?.stale == false &&
        value.pendingCommands == 0 &&
        snapshot?.state != RootTunState.stopping;
    final l = context.appLocalizations;
    final error = value.commandError?.code ?? snapshot?.lastErrorCode;
    final tone = DashboardColors.of(context).tone;
    final density = DashboardDensityScope.of(context);
    final outer = compact ? AppCorner.md : AppCorner.xl;
    return DashboardCard(
      semanticLabel: l.networkTakeover,
      padding: compact
          ? const EdgeInsets.all(8)
          : dashboardCardPadding(density),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            DashboardCardHeader(
              glyph: AppGlyphs.shuffle,
              title: l.networkTakeover,
            ),
            const SizedBox(height: 12),
          ],
          DashboardConnectedGroup(
            children: [
              for (final (index, mode) in [
                RootTunMode.vpn,
                RootTunMode.rootTun,
              ].indexed)
                Expanded(
                  child: DashboardConnectedButton(
                    selected: selected == mode,
                    first: index == 0,
                    last: index == 1,
                    outer: outer,
                    inner: AppCorner.sm,
                    background: tone,
                    semanticLabel: rootTunModeLabel(mode, l),
                    onTap: enabled && selected != mode
                        ? () => unawaited(
                            ref
                                .read(rootTunControllerProvider.notifier)
                                .selectMode(mode),
                          )
                        : null,
                    builder: (foreground) => SizedBox(
                      height: compact ? 40 : 52,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 8,
                        children: [
                          GlyphIcon(
                            mode == RootTunMode.vpn
                                ? AppGlyphs.vpn
                                : AppGlyphs.shuffle,
                            size: 18,
                            color: foreground,
                          ),
                          Flexible(
                            child: Text(
                              rootTunModeLabel(mode, l),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.footnote
                                  .of(context, emphasized: true)
                                  .copyWith(color: foreground),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (!compact && error != null) ...[
            const SizedBox(height: 8),
            Text(
              rootTunErrorLabel(error, l),
              style: AppTextStyle.footnote.of(context),
            ),
          ],
        ],
      ),
    );
  }
}
