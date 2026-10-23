import 'dart:io';

import 'package:fl_clash/common/root_tun_diagnostics.dart';
import 'package:fl_clash/models/root_tun.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class _TrackedFile extends Fake implements File {
  _TrackedFile(this.file);

  final File file;
  int streamReads = 0;
  int wholeReads = 0;

  @override
  Future<String> resolveSymbolicLinks() => file.resolveSymbolicLinks();

  @override
  Future<int> length() => file.length();

  @override
  Future<bool> exists() => file.exists();

  @override
  Stream<List<int>> openRead([int? start, int? end]) {
    streamReads++;
    return file.openRead(start, end);
  }

  @override
  Future<Uint8List> readAsBytes() async {
    wholeReads++;
    throw StateError('Whole-file reads are forbidden');
  }

  @override
  Uint8List readAsBytesSync() {
    wholeReads++;
    throw StateError('Whole-file reads are forbidden');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String homeDirectory;
  late File source;
  late _TrackedFile tracked;
  late RootTunDiagnostics diagnostics;
  late int shares;
  late int selections;
  late ShareParams? shared;
  late String? selectedName;
  late String? selectedMimeType;
  late String? destination;
  late ShareResultStatus shareStatus;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('root_tun_export_');
    homeDirectory = p.join(directory.path, 'private', 'files');
    await Directory(homeDirectory).create(recursive: true);
    source = File(
      p.join(directory.path, 'private', 'cache', 'diagnostics.zip'),
    );
    await source.parent.create();
    await source.writeAsBytes(
      List.generate(256 * 1024, (index) => index % 256),
    );
    tracked = _TrackedFile(source);
    diagnostics = RootTunDiagnostics(
      path: source.path,
      sizeBytes: await source.length(),
      mimeType: 'application/x-zip-compressed',
    );
    shares = 0;
    selections = 0;
    shared = null;
    selectedName = null;
    selectedMimeType = null;
    destination = p.join(directory.path, 'export.zip');
    shareStatus = ShareResultStatus.success;
  });

  tearDown(() async {
    expect(tracked.wholeReads, 0);
    await directory.delete(recursive: true);
  });

  RootTunDiagnosticsExporter exporter({bool isAndroid = true}) {
    return RootTunDiagnosticsExporter(
      isAndroid: isAndroid,
      openFile: (path) => path == source.path ? tracked : File(path),
      share: (params) async {
        shares++;
        shared = params;
        return ShareResult('test', shareStatus);
      },
      selectSavePath: (name, mimeType) async {
        selections++;
        selectedName = name;
        selectedMimeType = mimeType;
        return destination;
      },
    );
  }

  Future<bool> export(RootTunDiagnostics file) {
    return exporter().export(file, homeDirectory: homeDirectory);
  }

  for (final path in ['', 'cache/diagnostics.zip']) {
    test(
      'rejects non-absolute path "$path" before opening an export UI',
      () async {
        await expectLater(
          export(diagnostics.copyWith(path: path)),
          throwsFormatException,
        );
        expect(shares + selections, 0);
      },
    );
  }

  test(
    'rejects a sibling whose name shares the private directory prefix',
    () async {
      final outside = File(
        p.join(directory.path, 'private-other', 'outside.zip'),
      );
      await outside.parent.create();
      await outside.writeAsString('outside');
      await expectLater(
        export(diagnostics.copyWith(path: outside.path)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('private directory'),
          ),
        ),
      );
      expect(shares + selections, 0);
    },
  );

  test(
    'rejects a private symlink that resolves outside the directory',
    () async {
      final outside = File(p.join(directory.path, 'outside.zip'));
      await outside.writeAsString('outside');
      final link = await Link(
        p.join(source.parent.path, 'link.zip'),
      ).create(outside.path);
      await expectLater(
        export(diagnostics.copyWith(path: link.path)),
        throwsFormatException,
      );
      expect(shares + selections, 0);
    },
  );

  test('propagates a missing source without opening an export UI', () async {
    await source.delete();
    await expectLater(export(diagnostics), throwsA(isA<FileSystemException>()));
    expect(shares + selections, 0);
  });

  test('rejects negative sizes', () async {
    await expectLater(
      export(diagnostics.copyWith(sizeBytes: -1)),
      throwsFormatException,
    );
    expect(shares + selections, 0);
  });

  test('rejects a size mismatch before reading or exporting', () async {
    await expectLater(
      export(diagnostics.copyWith(sizeBytes: diagnostics.sizeBytes + 1)),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'Diagnostics size mismatch',
        ),
      ),
    );
    expect(tracked.streamReads, 0);
    expect(shares + selections, 0);
  });

  test(
    'Android shares the validated path and native MIME type without reading',
    () async {
      expect(await export(diagnostics), true);
      expect(shares, 1);
      expect(selections, 0);
      expect(shared!.files!.single.path, await source.resolveSymbolicLinks());
      expect(shared!.files!.single.mimeType, diagnostics.mimeType);
      expect(tracked.streamReads, 0);
      expect(await source.exists(), true);
    },
  );

  test(
    'share_plus sends paths and MIME types over the channel without bytes',
    () async {
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      MethodCall? sent;
      messenger.setMockMethodCallHandler(channel, (call) async {
        sent = call;
        return 'test.target';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final actual = RootTunDiagnosticsExporter(
        isAndroid: true,
        openFile: (path) => path == source.path ? tracked : File(path),
      );
      expect(
        await actual.export(diagnostics, homeDirectory: homeDirectory),
        true,
      );
      expect(sent!.method, 'share');
      expect(sent!.arguments, {
        'paths': [await source.resolveSymbolicLinks()],
        'mimeTypes': [diagnostics.mimeType],
      });
      expect(tracked.streamReads, 0);
    },
  );

  for (final status in [
    ShareResultStatus.dismissed,
    ShareResultStatus.unavailable,
  ]) {
    test(
      'Android $status does not report success or delete the source',
      () async {
        shareStatus = status;
        expect(await export(diagnostics), false);
        expect(await source.length(), diagnostics.sizeBytes);
      },
    );
  }

  test('share failures propagate to the caller', () async {
    final failure = StateError('share failed');
    final failing = RootTunDiagnosticsExporter(
      isAndroid: true,
      share: (_) async => throw failure,
    );
    await expectLater(
      failing.export(diagnostics, homeDirectory: homeDirectory),
      throwsA(same(failure)),
    );
    expect(await source.exists(), true);
  });

  test('desktop copies the source stream to the selected path', () async {
    expect(
      await exporter(
        isAndroid: false,
      ).export(diagnostics, homeDirectory: homeDirectory),
      true,
    );
    expect(selectedName, 'diagnostics.zip');
    expect(selectedMimeType, diagnostics.mimeType);
    expect(shares, 0);
    expect(selections, 1);
    expect(tracked.streamReads, 1);
    expect(await File(destination!).readAsBytes(), await source.readAsBytes());
    expect(await source.exists(), true);
  });

  test('desktop cancellation does not read or delete the source', () async {
    destination = null;
    expect(
      await exporter(
        isAndroid: false,
      ).export(diagnostics, homeDirectory: homeDirectory),
      false,
    );
    expect(tracked.streamReads, 0);
    expect(await source.length(), diagnostics.sizeBytes);
  });

  test('selecting the source on desktop does not truncate it', () async {
    destination = source.path;
    expect(
      await exporter(
        isAndroid: false,
      ).export(diagnostics, homeDirectory: homeDirectory),
      true,
    );
    expect(tracked.streamReads, 0);
    expect(await source.length(), diagnostics.sizeBytes);
  });

  test('desktop write failures propagate and keep the source', () async {
    destination = p.join(directory.path, 'missing', 'export.zip');
    await expectLater(
      exporter(
        isAndroid: false,
      ).export(diagnostics, homeDirectory: homeDirectory),
      throwsA(isA<FileSystemException>()),
    );
    expect(await source.length(), diagnostics.sizeBytes);
  });
}
