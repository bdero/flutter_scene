/// Turning a surface into water.
///
/// Water was an object you added: a forty-unit square that arrived wherever
/// the last thing was and had to be moved and resized onto the ground you
/// actually meant. But a body of water is an *area* -- this bay, that lake
/// bed -- and the area is already in the scene as a plane or a terrain. So
/// the gesture is to point at one and say it is water, and the surface takes
/// that plane's footprint and its place in the world.
library;

import 'package:scene/scene.dart';

import '../controller/editor_controller.dart';

/// The document component water is.
const String waterComponentType = 'water';

/// The footprint of the geometry [nodeId]'s mesh draws, or null when the node
/// has no mesh, or one whose shape has no footprint to take.
///
/// Only the two flat-ish procedural shapes qualify. A cube is not an area of
/// water, and reading a footprint off an imported mesh would mean reading its
/// vertices back off the GPU to guess at something the author never said.
({double width, double depth})? surfaceFootprint(
  EditorController ctrl,
  LocalId nodeId,
) {
  final node = ctrl.displayNode(nodeId);
  if (node == null) return null;
  for (final component in node.components) {
    if (component.type != 'mesh') continue;
    final reference = component.properties['geometry'];
    if (reference is! ResourceRefValue) continue;
    return footprintOf(ctrl.document.resource(reference.id));
  }
  return null;
}

/// The footprint [resource] describes, or null when its shape has none.
///
/// Split out from [surfaceFootprint] because this is the whole decision, and
/// it is a decision about a shape rather than about a scene.
({double width, double depth})? footprintOf(ResourceSpec? resource) {
  if (resource is! GeometryResource) return null;
  return switch (resource.procedural) {
    PlaneGeometrySpec(:final width, :final depth) => (
      width: width,
      depth: depth,
    ),
    TerrainGeometrySpec(:final width, :final depth) => (
      width: width,
      depth: depth,
    ),
    _ => null,
  };
}

/// Whether [nodeId] is a surface that could become water.
bool canBecomeWater(EditorController ctrl, LocalId nodeId) =>
    surfaceFootprint(ctrl, nodeId) != null && !hasWater(ctrl, nodeId);

/// Whether [nodeId] already carries water.
bool hasWater(EditorController ctrl, LocalId nodeId) =>
    ctrl
        .displayNode(nodeId)
        ?.components
        .any((component) => component.type == waterComponentType) ??
    false;

/// Makes [nodeId]'s surface water, sized to the ground it replaces.
///
/// The mesh goes: water builds its own displaced surface, and leaving the
/// plane underneath would leave a flat sheet showing through the waves. The
/// node keeps its name and its place in the world, so a lake bed sculpted
/// where you wanted it becomes a lake exactly there.
Future<void> makeSurfaceWater(EditorController ctrl, LocalId nodeId) async {
  final footprint = surfaceFootprint(ctrl, nodeId);
  if (footprint == null) return;
  // The larger side: the surface is square, and a water sheet that stopped
  // short of the ground it was made from would show a seam.
  final size = footprint.width > footprint.depth
      ? footprint.width
      : footprint.depth;
  await ctrl.run('addComponent', {
    'nodeId': nodeId.toToken(),
    'componentType': waterComponentType,
    'properties': {'size': size},
  });
  await ctrl.run('removeComponent', {
    'nodeId': nodeId.toToken(),
    'componentType': 'mesh',
  });
}
