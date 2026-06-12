import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'package:flutter_scene/src/components/camera_component.dart';
import 'package:flutter_scene/src/fscene/id.dart';
import 'package:flutter_scene/src/fscene/json/fscene_json.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/node_identity.dart';
import 'package:flutter_scene/src/fscene/realize/resource_origin.dart';
import 'package:flutter_scene/src/fscene/scene_document.dart';
import 'package:flutter_scene/src/fscene/specs.dart';
import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/node.dart';
import 'package:flutter_scene/src/render_texture.dart';
import 'package:flutter_scene/src/render_view.dart';
import 'package:flutter_scene/src/scene.dart';

// Live render textures realized per document instance, so the producing
// view and every material sampling the same resource id share one handle.
final Expando<Map<LocalId, RenderTexture>> _liveRenderTextures = Expando(
  'fscene live render textures',
);

/// Returns the live [RenderTexture] for resource [id] of [document],
/// creating (and memoizing) it on first use.
///
/// The same document instance always yields the same handle for an id, so
/// the view targeting it and the materials sampling it stay wired to one
/// target.
@internal
RenderTexture realizeRenderTexture(SceneDocument document, LocalId id) {
  final cache = _liveRenderTextures[document] ??= {};
  return cache.putIfAbsent(id, () {
    final res = document.resource(id);
    if (res is! RenderTextureResource) {
      throw FsceneFormatException('Resource $id is not a render texture');
    }
    final renderTexture = RenderTexture(
      width: res.width,
      height: res.height,
      update: switch (res.update) {
        'interval' => RenderTextureUpdate.interval(
          Duration(milliseconds: res.intervalMilliseconds ?? 1000),
        ),
        'manual' => RenderTextureUpdate.manual,
        _ => RenderTextureUpdate.everyFrame,
      },
      sampling: RenderTextureSampling(
        filter: res.filter == 'nearest'
            ? gpu.MinMagFilter.nearest
            : gpu.MinMagFilter.linear,
        wrap: switch (res.wrap) {
          'repeat' => gpu.SamplerAddressMode.repeat,
          'mirror' => gpu.SamplerAddressMode.mirror,
          _ => gpu.SamplerAddressMode.clampToEdge,
        },
      ),
    );
    return tagResourceOrigin(renderTexture, document, id);
  });
}

/// Serializes [renderTexture] into [context]'s document (from its live
/// state) and returns the resource id, reusing the id it originally
/// realized from when present so references stay stable across saves.
@internal
LocalId serializeRenderTexture(
  RenderTexture renderTexture,
  SerializeContext context,
) {
  final cached = context.serializedResources[renderTexture];
  if (cached != null) return cached;

  final id =
      resourceOrigin(renderTexture)?.resourceId ?? context.document.newId();
  if (context.document.resource(id) == null) {
    context.document.addResource(
      RenderTextureResource(
        id,
        width: renderTexture.width,
        height: renderTexture.height,
        update: renderTexture.update.kindName,
        intervalMilliseconds:
            renderTexture.update.intervalDuration?.inMilliseconds,
        filter: renderTexture.sampling.filter == gpu.MinMagFilter.nearest
            ? 'nearest'
            : 'linear',
        wrap: switch (renderTexture.sampling.wrap) {
          gpu.SamplerAddressMode.repeat => 'repeat',
          gpu.SamplerAddressMode.mirror => 'mirror',
          _ => 'clampToEdge',
        },
      ),
    );
  }
  context.serializedResources[renderTexture] = id;
  // Stamp the origin so later passes (and future saves) reuse this id.
  tagResourceOrigin(renderTexture, context.document, id);
  return id;
}

/// Realizes [document]'s serialized render views into [scene]'s view list.
///
/// Call after realizing the node graph (the views' cameras are
/// `CameraComponent` nodes in [root], matched by their document ids) and
/// adding [root] to [scene]. Views whose camera node or component is
/// missing are skipped with a debug warning.
void realizeViews(SceneDocument document, Scene scene, Node root) {
  for (final spec in document.views) {
    final node = _findNodeById(root, spec.cameraNode);
    if (node == null) {
      debugPrint(
        'fscene: skipping render view; camera node ${spec.cameraNode} '
        'was not found in the realized graph.',
      );
      continue;
    }
    final component = node.getComponents<CameraComponent>().firstOrNull;
    if (component == null) {
      debugPrint(
        'fscene: skipping render view; node ${spec.cameraNode} has no '
        'CameraComponent.',
      );
      continue;
    }
    scene.views.add(
      RenderView(
        camera: component.toCamera(),
        target: spec.target == null
            ? null
            : realizeRenderTexture(document, spec.target!),
        layerMask: spec.layerMask,
        order: spec.order,
        antiAliasingMode: spec.antiAliasingMode == null
            ? null
            : _enumByName(
                AntiAliasingMode.values,
                spec.antiAliasingMode!,
                AntiAliasingMode.auto,
              ),
        renderScale: spec.renderScale,
        filterQuality: spec.filterQuality == null
            ? null
            : _enumByName(
                ui.FilterQuality.values,
                spec.filterQuality!,
                ui.FilterQuality.medium,
              ),
      ),
    );
  }
}

/// Serializes [scene]'s view list into [document]'s `views` array,
/// replacing any existing entries.
///
/// Call after `serializeScene` (camera nodes are referenced by the ids
/// that pass assigned). Views whose camera is not a node-backed
/// `NodeCamera` within the serialized graph are skipped with a debug
/// warning; render-texture targets are serialized from their live state.
void serializeViews(Scene scene, SceneDocument document) {
  final context = SerializeContext(document);
  document.views.clear();
  for (final view in scene.views) {
    final camera = view.camera;
    if (camera is! NodeCamera) {
      debugPrint(
        'fscene: skipping render view; its camera is not node-backed '
        '(use a CameraComponent for serializable views).',
      );
      continue;
    }
    final cameraId = nodeFsceneId(camera.node);
    if (cameraId == null || document.node(cameraId) == null) {
      debugPrint(
        'fscene: skipping render view; its camera node is not part of '
        'the serialized graph.',
      );
      continue;
    }
    final target = view.target;
    document.views.add(
      RenderViewSpec(
        cameraNode: cameraId,
        target: target == null ? null : serializeRenderTexture(target, context),
        layerMask: view.layerMask,
        order: view.order,
        antiAliasingMode: view.antiAliasingMode?.name,
        renderScale: view.renderScale,
        filterQuality: view.filterQuality?.name,
      ),
    );
  }
  if (document.views.isNotEmpty) {
    document.featuresUsed.add('renderTextures');
  }
}

Node? _findNodeById(Node root, LocalId id) {
  if (nodeFsceneId(root) == id) return root;
  for (final child in root.children) {
    final found = _findNodeById(child, id);
    if (found != null) return found;
  }
  return null;
}

T _enumByName<T extends Enum>(List<T> values, String name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
