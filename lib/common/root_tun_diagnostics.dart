import 'dart:io';

import 'package:fl_clash/models/root_tun.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class RootTunDiagnosticsExporter {
  RootTunDiagnosticsExporter({
    required bool isAndroid,
    Future<ShareResult> Function(ShareParams)? share,
    File Function(String path) openFile = File.new,
  }) : _isAndroid = isAndroid,
       _share = share,
       _openFile = openFile;

  final bool _isAndroid;
  final Future<ShareResult> Function(ShareParams)? _share;
  final File Function(String path) _openFile;

  Future<bool> export(
    RootTunDiagnostics diagnostics, {
    required String homeDirectory,
  }) async {
    if (!_isAndroid) {
      throw UnsupportedError('Root TUN diagnostics export is Android only');
    }
    if (!p.isAbsolute(diagnostics.path) || diagnostics.sizeBytes < 0) {
      throw const FormatException('Invalid diagnostics file');
    }
    final localPath = await _openFile(diagnostics.path).resolveSymbolicLinks();
    final privatePath = await Directory(
      p.dirname(homeDirectory),
    ).resolveSymbolicLinks();
    if (!p.isWithin(privatePath, localPath)) {
      throw const FormatException(
        'Diagnostics must be in the app private directory',
      );
    }
    final file = _openFile(localPath);
    if (await file.length() != diagnostics.sizeBytes) {
      throw const FormatException('Diagnostics size mismatch');
    }
    final result = await (_share ?? SharePlus.instance.share)(
      ShareParams(files: [XFile(localPath, mimeType: diagnostics.mimeType)]),
    );
    return result.status == ShareResultStatus.success;
  }
}
