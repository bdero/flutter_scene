/// Identifies the engine a compiled shader bundle is being built for.
///
/// A shader bundle is only valid for the exact engine whose `impellerc`
/// produced it, so every compiled output records this alongside its source
/// hashes and is rebuilt when it changes. That is what makes flutter_scene's
/// own package directory a safe place to build into: two projects on different
/// Flutter versions sharing one pub cache each rebuild on switch.
///
/// Hook-only: uses `dart:io`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_gpu_shaders/environment.dart';

/// The engine identity for this hook run, cached for the process.
///
/// Two signals, because neither covers every setup. The SDK's
/// `bin/cache/engine_stamp.json` carries the engine content hash, which is the
/// identity the engine itself checks a bundle against. `impellerc`'s size and
/// timestamp are what a local engine build or an `IMPELLERC` override moves,
/// where the SDK stamp keeps naming the cached engine. Both are stats and a
/// short read, so this costs nothing per build.
Future<String> engineIdentity() async => _cached ??= await _resolve();

String? _cached;

/// Overrides the identity, for tests that need a stamp change without an SDK.
void debugSetEngineIdentity(String? identity) => _cached = identity;

Future<String> _resolve() async {
  Uri? impellerc;
  try {
    impellerc = await findImpellerC();
  } catch (_) {
    // No SDK layout to read; the parts below fall back to "unknown".
  }
  final parts = <String>[];
  if (impellerc != null) {
    final file = File.fromUri(impellerc);
    if (file.existsSync()) {
      final stat = file.statSync();
      parts.add(
        'impellerc=${stat.size}@${stat.modified.microsecondsSinceEpoch}',
      );
    }
    final stamp = _sdkEngineStamp(impellerc);
    if (stamp != null) parts.add('engine=$stamp');
  }
  return parts.isEmpty ? 'engine=unknown' : parts.join(' ');
}

/// The engine content hash recorded by the SDK cache holding [impellerc], or
/// null when this is not an SDK cache layout.
///
/// `impellerc` lives at `<cache>/artifacts/engine/<host>/impellerc`, so the
/// stamps are a few levels up.
String? _sdkEngineStamp(Uri impellerc) {
  var directory = impellerc.resolve('./');
  for (var depth = 0; depth < 5; depth++) {
    directory = directory.resolve('../');
    final json = File.fromUri(directory.resolve('engine_stamp.json'));
    if (json.existsSync()) {
      try {
        final decoded = (jsonDecode(json.readAsStringSync()) as Map)
            .cast<String, Object?>();
        final hash = decoded['content_hash'] ?? decoded['git_revision'];
        if (hash is String && hash.isNotEmpty) return hash;
      } catch (_) {
        // Fall through to the plain stamp file.
      }
    }
    final plain = File.fromUri(directory.resolve('engine.stamp'));
    if (plain.existsSync()) {
      final contents = plain.readAsStringSync().trim();
      if (contents.isNotEmpty) return contents;
    }
  }
  return null;
}
