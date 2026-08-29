/// Baking nav mesh tiles across isolates.
///
/// Tiles are independent by construction: each one's geometry is clipped to
/// its own square plus a border, and nothing it computes depends on another
/// tile's result. That is what makes a world's bake divisible at all, and it
/// is where the wall-clock win is -- tiling on one thread is roughly time
/// neutral against a single-shot bake, because the borders are extra work
/// that pays for the divisibility.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:scene/navigation.dart';
import 'package:vector_math/vector_math.dart';

/// How many tiles to have in flight at once, by default.
///
/// One per core, less one for the isolate asking: saturating every core with
/// bakes leaves nothing for the editor to draw with, and a bake that freezes
/// the UI it is reporting progress to is worse than a slower one.
int defaultNavBakeConcurrency() {
  if (kIsWeb) return 1;
  final cores = Platform.numberOfProcessors;
  return cores <= 2 ? 1 : cores - 1;
}

/// Bakes [geometry] tile by tile, several tiles at a time, and links the
/// results.
///
/// On the web there are no isolates and [compute] runs inline, so this still
/// answers the same but does not spare the frame; the tiling is still worth
/// it there for the bounded memory and the incremental rebake.
///
/// [onProgress] is called on the calling isolate as each tile lands, so a UI
/// can show a bar without any cross-isolate plumbing of its own.
Future<NavTiledBakeResult> bakeNavMeshTiledAsync(
  NavGeometry geometry,
  NavMeshConfig config, {
  NavTileConfig tiling = const NavTileConfig(),
  List<NavVolume> volumes = const [],
  Vector3? origin,
  int? concurrency,
  void Function(int done, int total)? onProgress,
}) async {
  final watch = Stopwatch()..start();
  // Planning stays here: it reads the whole world's triangles once, and
  // shipping that to another isolate would cost more than it saves.
  final jobs = planNavTileBake(
    geometry,
    config,
    tiling: tiling,
    volumes: volumes,
    origin: origin,
  );
  final set = NavTileSet(config: config, tiling: tiling, origin: origin);
  if (jobs.isEmpty) {
    watch.stop();
    return NavTiledBakeResult(
      tiles: set,
      duration: watch.elapsed,
      emptyTiles: 0,
    );
  }

  final lanes = (concurrency ?? defaultNavBakeConcurrency()).clamp(
    1,
    jobs.length,
  );
  var next = 0;
  var done = 0;
  var empty = 0;

  // A fixed pool pulling from a shared cursor, rather than one future per
  // tile: a world is thousands of tiles, and thousands of simultaneous
  // isolate spawns is its own kind of slow.
  Future<void> lane() async {
    while (true) {
      final index = next++;
      if (index >= jobs.length) return;
      final job = jobs[index];
      final mesh = await compute(bakeNavTile, job);
      if (mesh == null || mesh.polygonCount == 0) {
        empty++;
      } else {
        set.setTile(job.key, mesh);
      }
      onProgress?.call(++done, jobs.length);
    }
  }

  await Future.wait([for (var i = 0; i < lanes; i++) lane()]);
  watch.stop();
  return NavTiledBakeResult(
    tiles: set,
    duration: watch.elapsed,
    emptyTiles: empty,
  );
}
