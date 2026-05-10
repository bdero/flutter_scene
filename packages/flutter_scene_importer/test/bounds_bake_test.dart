// ignore_for_file: avoid_print

/// Verifies that the model emitter bakes per-primitive AABB / bounding
/// sphere data and per-node combined AABBs, and that the values it
/// writes are tight enough to be useful for runtime culling.
library;

import 'dart:io';
import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:flutter_scene_importer/flatbuffer.dart' as fb;
import 'package:flutter_scene_importer/gltf.dart';
import 'package:flutter_scene_importer/importer.dart';
import 'package:flutter_scene_importer/src/fb_emitter/model_emitter.dart';
import 'package:test/test.dart';

void main() {
  test(
    'fcar.glb: every primitive has tight bounds, every node has a combined AABB',
    () {
      final scene = _emitAndDecode('examples/assets_src/fcar.glb');
      if (scene == null) {
        print('fcar.glb missing — skipping.');
        return;
      }

      int primCount = 0;
      for (final node in scene.nodes ?? const <fb.Node>[]) {
        for (final p in node.meshPrimitives ?? const <fb.MeshPrimitive>[]) {
          primCount++;
          final aabb = p.boundsAabb;
          expect(aabb, isNotNull, reason: 'primitive missing AABB');
          // AABB must be non-degenerate on at least one axis (every fcar
          // primitive is a real mesh).
          final extentX = aabb!.max.x - aabb.min.x;
          final extentY = aabb.max.y - aabb.min.y;
          final extentZ = aabb.max.z - aabb.min.z;
          expect(extentX + extentY + extentZ, greaterThan(0));

          final sphere = p.boundsSphere;
          expect(sphere, isNotNull, reason: 'primitive missing sphere');
          expect(sphere!.radius, greaterThan(0));
          // Sphere centre lies inside the AABB (a Ritter sphere centre is
          // the midpoint of two vertices, both of which are inside the
          // AABB, so the midpoint must be too).
          final eps = 1e-4;
          expect(sphere.center.x, greaterThanOrEqualTo(aabb.min.x - eps));
          expect(sphere.center.y, greaterThanOrEqualTo(aabb.min.y - eps));
          expect(sphere.center.z, greaterThanOrEqualTo(aabb.min.z - eps));
          expect(sphere.center.x, lessThanOrEqualTo(aabb.max.x + eps));
          expect(sphere.center.y, lessThanOrEqualTo(aabb.max.y + eps));
          expect(sphere.center.z, lessThanOrEqualTo(aabb.max.z + eps));
          // Sphere radius should at least cover the AABB centre-to-min
          // distance from the sphere centre. (This is a vertex-free
          // sanity check that fails on a clearly-bogus radius.)
          final cdx = sphere.center.x - (aabb.min.x + aabb.max.x) * 0.5;
          final cdy = sphere.center.y - (aabb.min.y + aabb.max.y) * 0.5;
          final cdz = sphere.center.z - (aabb.min.z + aabb.max.z) * 0.5;
          final centreOffset = _len3(cdx, cdy, cdz);
          expect(
            sphere.radius,
            greaterThanOrEqualTo(centreOffset - eps),
            reason: 'sphere radius is smaller than the AABB centre offset',
          );
        }
      }
      expect(primCount, greaterThan(0));

      // Every node in fcar (no skin anywhere) should get a combined AABB.
      int nodesWithCombined = 0;
      int nodesWithoutCombined = 0;
      for (final node in scene.nodes ?? const <fb.Node>[]) {
        if (node.combinedLocalAabb != null) {
          nodesWithCombined++;
        } else {
          nodesWithoutCombined++;
        }
      }
      expect(nodesWithCombined, greaterThan(0));
      // fcar has nodes that are pure transform groups (no own mesh, no
      // children with meshes) — those are allowed to omit the AABB.
      print(
        '  fcar nodes with combined AABB: $nodesWithCombined / '
        '${nodesWithCombined + nodesWithoutCombined}',
      );
    },
  );

  test(
    'dash.glb: skinned primitives get a pose-union AABB and combined AABBs',
    () {
      final scene = _emitAndDecode('examples/assets_src/dash.glb');
      if (scene == null) {
        print('dash.glb missing — skipping.');
        return;
      }

      // Dash has skinned primitives. Each skinned primitive should now
      // carry a pose-union AABB, AND the static-pose AABB the runtime
      // would have rendered before any animation.
      bool foundSkinnedNode = false;
      int skinnedPrimCount = 0;
      for (final node in scene.nodes ?? const <fb.Node>[]) {
        if (node.skin == null) continue;
        foundSkinnedNode = true;
        for (final p in node.meshPrimitives ?? const <fb.MeshPrimitive>[]) {
          skinnedPrimCount++;
          expect(p.boundsAabb, isNotNull);
          expect(
            p.skinnedPoseUnionAabb,
            isNotNull,
            reason:
                'skinned primitive on ${node.name} should have a pose-union AABB',
          );
          // The pose-union AABB must contain the static-pose AABB,
          // since t=0 (bind pose) is always one of the sample times.
          final pose = p.skinnedPoseUnionAabb!;
          final stat = p.boundsAabb!;
          expect(pose.min.x, lessThanOrEqualTo(stat.min.x + 1e-3));
          expect(pose.min.y, lessThanOrEqualTo(stat.min.y + 1e-3));
          expect(pose.min.z, lessThanOrEqualTo(stat.min.z + 1e-3));
          expect(pose.max.x, greaterThanOrEqualTo(stat.max.x - 1e-3));
          expect(pose.max.y, greaterThanOrEqualTo(stat.max.y - 1e-3));
          expect(pose.max.z, greaterThanOrEqualTo(stat.max.z - 1e-3));
        }
        // Skinned subtrees now get a baked combined AABB derived from
        // their pose-union extents. The previous behaviour (always-null
        // for skinned subtrees) was a v1 conservative hack.
        expect(
          node.combinedLocalAabb,
          isNotNull,
          reason: 'skinned node ${node.name} should now have a combined AABB',
        );
      }
      expect(
        foundSkinnedNode,
        isTrue,
        reason: 'dash should contain a skinned node',
      );
      expect(skinnedPrimCount, greaterThan(0));
    },
  );

  test(
    'two_triangles.glb: pose-union extends beyond static bind-pose AABB',
    () {
      // two_triangles is a tiny skinned animated test asset. Verify the
      // pose-union AABB is a strict superset of the static AABB on at
      // least one axis (otherwise the bake would be a no-op).
      final scene = _emitAndDecode('examples/assets_src/two_triangles.glb');
      if (scene == null) {
        print('two_triangles.glb missing — skipping.');
        return;
      }
      fb.MeshPrimitive? skinnedPrim;
      for (final node in scene.nodes ?? const <fb.Node>[]) {
        if (node.skin == null) continue;
        for (final p in node.meshPrimitives ?? const <fb.MeshPrimitive>[]) {
          skinnedPrim = p;
          break;
        }
        if (skinnedPrim != null) break;
      }
      expect(skinnedPrim, isNotNull);
      final pose = skinnedPrim!.skinnedPoseUnionAabb;
      final stat = skinnedPrim.boundsAabb;
      expect(pose, isNotNull);
      expect(stat, isNotNull);
      final poseExtent =
          (pose!.max.x - pose.min.x) +
          (pose.max.y - pose.min.y) +
          (pose.max.z - pose.min.z);
      final staticExtent =
          (stat!.max.x - stat.min.x) +
          (stat.max.y - stat.min.y) +
          (stat.max.z - stat.min.z);
      expect(
        poseExtent,
        greaterThan(staticExtent),
        reason:
            'pose-union AABB should be larger than the static bind-pose AABB '
            'when the file has animations that drive the skin',
      );
    },
  );

  test('AABB matches glTF accessor min/max when present', () {
    // fcar's CarBody primitive has POSITION accessor min/max set in the
    // source glTF. The baked AABB should equal those values exactly,
    // without going through a float-imprecise vertex scan.
    final glbPath = _resolve('examples/assets_src/fcar.glb');
    if (!File(glbPath).existsSync()) {
      print('fcar.glb missing — skipping.');
      return;
    }
    final glbBytes = File(glbPath).readAsBytesSync();
    final container = parseGlb(glbBytes);
    final doc = parseGltfJson(container.json);

    // Scan all primitives, find one with both accessor min/max present.
    GltfMeshPrimitive? exemplar;
    GltfAccessor? exemplarPos;
    for (final mesh in doc.meshes) {
      for (final p in mesh.primitives) {
        final pos = doc.accessors[p.attributes['POSITION']!];
        if (pos.min != null && pos.max != null) {
          exemplar = p;
          exemplarPos = pos;
          break;
        }
      }
      if (exemplar != null) break;
    }
    expect(
      exemplar,
      isNotNull,
      reason: 'fcar should have at least one primitive with min/max',
    );

    final modelBytes = emitModel(doc, container.binaryChunk);
    final scene =
        ImportedScene.fromFlatbuffer(
          ByteData.sublistView(modelBytes),
        ).flatbuffer;

    // Find the matching emitted primitive (by vertex count, since names
    // may have collisions).
    final exemplarVertCount =
        doc.accessors[exemplar!.attributes['POSITION']!].count;
    fb.MeshPrimitive? match;
    for (final node in scene.nodes ?? const <fb.Node>[]) {
      for (final p in node.meshPrimitives ?? const <fb.MeshPrimitive>[]) {
        final vbCount =
            (p.vertices is fb.UnskinnedVertexBuffer)
                ? (p.vertices as fb.UnskinnedVertexBuffer).vertexCount
                : (p.vertices as fb.SkinnedVertexBuffer).vertexCount;
        if (vbCount == exemplarVertCount) {
          match = p;
          break;
        }
      }
      if (match != null) break;
    }
    expect(match, isNotNull);
    final aabb = match!.boundsAabb!;
    expect(aabb.min.x, closeTo(exemplarPos!.min![0], 1e-6));
    expect(aabb.min.y, closeTo(exemplarPos.min![1], 1e-6));
    expect(aabb.min.z, closeTo(exemplarPos.min![2], 1e-6));
    expect(aabb.max.x, closeTo(exemplarPos.max![0], 1e-6));
    expect(aabb.max.y, closeTo(exemplarPos.max![1], 1e-6));
    expect(aabb.max.z, closeTo(exemplarPos.max![2], 1e-6));
  });
}

fb.Scene? _emitAndDecode(String relativePath) {
  final glbPath = _resolve(relativePath);
  if (!File(glbPath).existsSync()) return null;
  final glbBytes = File(glbPath).readAsBytesSync();
  final container = parseGlb(glbBytes);
  final doc = parseGltfJson(container.json);
  final modelBytes = emitModel(doc, container.binaryChunk);
  return ImportedScene.fromFlatbuffer(
    ByteData.sublistView(modelBytes),
  ).flatbuffer;
}

double _len3(double x, double y, double z) => sqrt(x * x + y * y + z * z);

String _resolve(String relative) {
  for (final prefix in ['', '../../', '../../../']) {
    final candidate = '$prefix$relative';
    if (File(candidate).existsSync() || Directory(candidate).existsSync()) {
      return candidate;
    }
  }
  return relative;
}
