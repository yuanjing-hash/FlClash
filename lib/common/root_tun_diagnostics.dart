import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fl_clash/models/root_tun.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class RootTunDiagnosticsExporter {
  RootTunDiagnosticsExporter({
    required bool isAndroid,
    Future<ShareResult> Function(ShareParams)? share,
    Future<String?> Function(String name, String mimeType)? selectSavePath,
    File Function(String path) openFile = File.new,
  }) : _isAndroid = isAndroid,
       _share = share,
       _selectSavePath = selectSavePath ?? _desktopSavePath,
       _openFile = openFile;

  final bool _isAndroid;
  final Future<ShareResult> Function(ShareParams)? _share;
  final Future<String?> Function(String name, String mimeType) _selectSavePath;
  final File Function(String path) _openFile;

  Future<bool> export(
    RootTunDiagnostics diagnostics, {
    required String homeDirectory,
  }) async {
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
    if (_isAndroid) {
      final result = await (_share ?? SharePlus.instance.share)(
        ShareParams(files: [XFile(localPath, mimeType: diagnostics.mimeType)]),
      );
      return result.status == ShareResultStatus.success;
    }
    final destination = await _selectSavePath(
      p.basename(localPath),
      diagnostics.mimeType,
    );
    if (destination == null) return false;
    final target = _openFile(destination);
    if (await target.exists() &&
        await target.resolveSymbolicLinks() == localPath) {
      return true;
    }
    await file.openRead().pipe(target.openWrite());
    return true;
  }

  static Future<String?> _desktopSavePath(String name, String mimeType) async {
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [
        XTypeGroup(
          label: mimeType,
          extensions: const ['zip'],
          mimeTypes: [mimeType],
        ),
      ],
    );
    return location?.path;
  }
}
