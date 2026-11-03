import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.userDefines['build_assets'] == false) {
      stdout.writeln('Skipping the Rust build: user-define build_assets=false');
      return;
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      extraCargoEnvironmentVariables: _bindgenEnvironment(input),
    ).run(input: input, output: output);
  });
}

Map<String, String> _bindgenEnvironment(BuildInput input) {
  if (!input.config.buildCodeAssets ||
      input.config.code.targetOS != OS.android) {
    return const {};
  }
  final compiler = input.config.code.cCompiler?.compiler;
  if (compiler == null) {
    return const {};
  }
  final llvmRoot = File.fromUri(compiler).parent.parent;
  String? libclangPath;
  for (final name in const ['lib', 'lib64', 'bin']) {
    final directory = Directory(
      '${llvmRoot.path}${Platform.pathSeparator}$name',
    );
    if (directory.existsSync() && directory.listSync().any(_isLibclang)) {
      libclangPath = directory.path;
      break;
    }
  }
  libclangPath ??= Platform.environment['LIBCLANG_PATH'];
  if (libclangPath == null || libclangPath.isEmpty) {
    throw StateError(
      'No libclang under ${llvmRoot.path} (lib, lib64 or bin); the NDK Flutter '
      'passed cannot run bindgen for rquickjs. Set LIBCLANG_PATH to a host '
      'LLVM libclang directory.',
    );
  }
  final target = switch (input.config.code.targetArchitecture) {
    Architecture.arm64 => 'aarch64-linux-android',
    Architecture.arm => 'armv7-linux-androideabi',
    Architecture.x64 => 'x86_64-linux-android',
    final architecture => throw UnsupportedError(
      'Unsupported Android architecture: $architecture',
    ),
  };
  final includeTarget = target == 'armv7-linux-androideabi'
      ? 'arm-linux-androideabi'
      : target;
  final sysroot = '${llvmRoot.path}/sysroot'.replaceAll(r'\', '/');
  final resources = Directory('${llvmRoot.path}/lib/clang')
      .listSync()
      .whereType<Directory>()
      .where((directory) => Directory('${directory.path}/include').existsSync())
      .single;
  final resourcePath = resources.path.replaceAll(r'\', '/');
  return {
    'LIBCLANG_PATH': libclangPath,
    // native_toolchain_rust 1.0.6 leaves SDK paths unquoted for bindgen's shlex.
    'BINDGEN_EXTRA_CLANG_ARGS_${target.replaceAll('-', '_')}':
        '--sysroot="$sysroot" -I"$sysroot/usr/include/$includeTarget" '
        '-resource-dir="$resourcePath"',
  };
}

bool _isLibclang(FileSystemEntity entity) {
  return entity.path.split(Platform.pathSeparator).last.startsWith('libclang.');
}
