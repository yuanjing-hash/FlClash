import 'package:fl_clash/common/common.dart';

import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:material_ui/material_ui.dart';

import 'card.dart';
import 'connection_mode.dart';

typedef _RowMetrics = ({
  EdgeInsets padding,
  double titleStart,
  double radius,
  double icon,
  bool subtitle,
});

const _RowMetrics _cardRowMetrics = (
  padding: EdgeInsets.fromLTRB(10, 10, 12, 10),
  titleStart: 14,
  radius: 20,
  icon: 38,
  subtitle: true,
);

/// A tile's icon and switch sit as far in from its ends as from its edges, so
/// a full pill keeps both concentric with its corners. Without the icon, the
/// title lines up with the content of the cards above and below.
_RowMetrics _tileMetricsOf(DashboardDensity density) => density.isCompact
    ? (
        padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
        titleStart: dashboardCardPadding(density).left,
        radius: dashboardCardRadius(density),
        icon: 36,
        subtitle: false,
      )
    : (
        padding: const EdgeInsets.fromLTRB(12, 0, 16, 0),
        titleStart: dashboardCardPadding(density).left,
        radius: dashboardCardRadius(density),
        icon: 40,
        subtitle: true,
      );

enum TakeoverSwitch { systemProxy, tun }

class _TakeoverRow extends ConsumerWidget {
  const _TakeoverRow({
    required this.kind,
    required this.metrics,
    required this.showIcon,
    this.color,
  });

  final TakeoverSwitch kind;
  final _RowMetrics metrics;
  final bool showIcon;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final systemProxy = kind == TakeoverSwitch.systemProxy;
    final title = _titleOf(context, kind);
    final value = systemProxy
        ? ref.watch(networkSettingProvider.select((state) => state.systemProxy))
        : ref.watch(
            patchClashConfigProvider.select((state) => state.tun.enable),
          );
    final on = systemProxy
        ? appLocalizations.portValue(
            ref.watch(
              patchClashConfigProvider.select((state) => state.mixedPort),
            ),
          )
        : appLocalizations.enabled;
    void change(bool value) => systemProxy
        ? ref
              .read(networkSettingProvider.notifier)
              .update((state) => state.copyWith(systemProxy: value))
        : ref
              .read(patchClashConfigProvider.notifier)
              .update((state) => state.copyWith.tun(enable: value));
    return DashboardSwitchRow(
      glyph: systemProxy ? AppGlyphs.shuffle : AppGlyphs.vpn,
      title: title,
      subtitle: metrics.subtitle
          ? value
                ? on
                : appLocalizations.disabled
          : null,
      value: value,
      iconSize: metrics.icon,
      padding: showIcon
          ? metrics.padding
          : metrics.padding.copyWith(left: metrics.titleStart),
      radius: metrics.radius,
      color: color,
      showIcon: showIcon,
      onTap: () => change(!value),
      onChanged: change,
    );
  }
}

String _titleOf(BuildContext context, TakeoverSwitch kind) => switch (kind) {
  TakeoverSwitch.systemProxy => context.appLocalizations.systemProxy,
  TakeoverSwitch.tun => context.appLocalizations.tun,
};

/// Both switches in one card, for the card list of a narrow window.
class NetworkTakeoverCard extends StatelessWidget {
  const NetworkTakeoverCard({super.key});

  @override
  Widget build(BuildContext context) {
    const metrics = _cardRowMetrics;
    final appLocalizations = context.appLocalizations;
    return DashboardCard(
      semanticLabel: appLocalizations.networkTakeover,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.shuffle,
            title: appLocalizations.networkTakeover,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final showIcon = DashboardSwitchRow.iconFits(
                context,
                width: constraints.maxWidth,
                iconSize: metrics.icon,
                padding: metrics.padding,
                titles: [
                  for (final kind in TakeoverSwitch.values)
                    _titleOf(context, kind),
                ],
              );
              return Column(
                spacing: 8,
                children: [
                  for (final kind in TakeoverSwitch.values)
                    _TakeoverRow(
                      kind: kind,
                      metrics: metrics,
                      showIcon: showIcon,
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One switch as a card of its own, in the desktop's control row.
class NetworkTakeoverTile extends StatelessWidget {
  const NetworkTakeoverTile(this.kind, {super.key});

  final TakeoverSwitch kind;

  @override
  Widget build(BuildContext context) {
    final metrics = _tileMetricsOf(DashboardDensityScope.of(context));
    return DashboardCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) => _TakeoverRow(
          kind: kind,
          metrics: metrics,
          color: Colors.transparent,
          showIcon: DashboardSwitchRow.iconFits(
            context,
            width: constraints.maxWidth,
            iconSize: metrics.icon,
            padding: metrics.padding,
            titles: [
              for (final kind in TakeoverSwitch.values) _titleOf(context, kind),
            ],
          ),
        ),
      ),
    );
  }
}

class VpnTile extends StatelessWidget {
  const VpnTile({super.key});

  @override
  Widget build(BuildContext context) => const ConnectionModeCard(compact: true);
}

class VpnCard extends StatelessWidget {
  const VpnCard({super.key});

  @override
  Widget build(BuildContext context) => const ConnectionModeCard();
}
