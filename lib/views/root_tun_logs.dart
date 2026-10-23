import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/root_tun_labels.dart';
import 'package:fl_clash/models/root_tun.dart';
import 'package:fl_clash/plugins/root_tun.dart';
import 'package:fl_clash/providers/root_tun.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

class RootTunLogsView extends ConsumerStatefulWidget {
  const RootTunLogsView({super.key});

  @override
  ConsumerState<RootTunLogsView> createState() => _RootTunLogsViewState();
}

class _RootTunLogsViewState extends ConsumerState<RootTunLogsView> {
  final _entries = <RootTunLogEntry>[];
  String? _cursor;
  String? _error;
  String? _sourcePath;
  bool _loading = false;
  bool _eof = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(rootTunPluginProvider)
          .getLogs(cursor: reset ? null : _cursor);
      if (!mounted) return;
      final page = result.data;
      if (page == null) {
        throw MessageException(
          rootTunErrorLabel(result.error!.code, context.appLocalizations),
        );
      }
      setState(() {
        if (reset) _entries.clear();
        final known = _entries.map((entry) => entry.cursor).toSet();
        _entries.addAll(page.entries.where((entry) => known.add(entry.cursor)));
        _sourcePath = page.sourcePath;
        _cursor = page.nextCursor;
        _eof = page.eof || page.nextCursor == null;
      });
    } catch (error) {
      if (mounted && error is RootTunChannelException) {
        ref.read(rootTunControllerProvider.notifier).recordChannelError(error);
      }
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return CommonScaffold(
      title: l.rootTunLogs,
      isLoading: _loading,
      primaryAction: IconButtonData(
        glyph: AppGlyphs.refresh,
        tooltip: l.rootTunRecheck,
        onPressed: () => _load(reset: true),
      ),
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(16, context.contentTopPadding, 16, 16),
        itemCount: _entries.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return SelectableText(
              [
                ?_sourcePath,
                if (_entries.isEmpty && !_loading && _error == null)
                  l.rootTunLogsEmpty,
                if (_error != null) '${l.rootTunNativeUnavailable}\n$_error',
              ].join('\n'),
            );
          }
          if (index > _entries.length) {
            return TextButton(
              onPressed: _loading || _eof ? null : _load,
              child: Text(l.rootTunLoadMore),
            );
          }
          final entry = _entries[index - 1];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SelectableText(
              '${DateTime.fromMillisecondsSinceEpoch(entry.at).toLocal().toIso8601String()} [${entry.level.name}] ${entry.code ?? ''}\n${entry.message}',
              style: AppTextStyle.caption1.of(context),
            ),
          );
        },
      ),
    );
  }
}
