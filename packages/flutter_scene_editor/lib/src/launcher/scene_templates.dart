/// What a new scene starts as.
///
/// An empty 3D scene is the worst first thing anyone sees: a sky, no ground,
/// no light you can point at, nothing to judge scale against. The first
/// minutes go into building the same floor and the same key light that every
/// scene needs, before any of the work that is actually this scene's.
///
/// A template is a whole document rather than a file on disk: it is built
/// from the same specs a save writes, so a template cannot drift from the
/// format, cannot reference an asset that moved, and costs nothing to ship.
library;

import 'package:flutter/material.dart';
import 'package:scene/scene.dart';

import '../shell/editor_dialog.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

/// One starting point, and what it builds.
class SceneTemplate {
  const SceneTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.build,
  });

  /// A stable id, for a setting that remembers the last one used.
  final String id;

  /// The name on the card.
  final String name;

  /// What the scene has in it, in a line.
  final String description;

  /// The glyph on the card.
  final IconData icon;

  /// Builds a fresh document. Called per use, so two new scenes from one
  /// template share no ids and no objects.
  final SceneDocument Function() build;
}

/// The shipped templates, emptiest first.
///
/// Deliberately few. A gallery of thirty starting points is a decision to
/// make before any work can begin; four is a choice.
final List<SceneTemplate> sceneTemplates = [
  SceneTemplate(
    id: 'empty',
    name: 'Empty',
    description: 'A sky and nothing else. The blank page.',
    icon: Icons.crop_free,
    build: buildEmptyScene,
  ),
  SceneTemplate(
    id: 'studio',
    name: 'Lit studio',
    description:
        'A floor, a key light and a fill, and a cube on the floor to judge '
        'the light against. What you want for looking at one object.',
    icon: Icons.lightbulb_outline,
    build: buildStudioScene,
  ),
  SceneTemplate(
    id: 'outdoor',
    name: 'Outdoor',
    description:
        'Rolling terrain under a sun that casts. What you want before '
        'dropping a character in.',
    icon: Icons.terrain_outlined,
    build: buildOutdoorScene,
  ),
  SceneTemplate(
    id: 'playground',
    name: 'Physics playground',
    description:
        'A ground plane with a body on it and a world to simulate them. '
        'Press play and things fall.',
    icon: Icons.sports_baseball_outlined,
    build: buildPlaygroundScene,
  ),
];

/// The template with [id], or the empty one when nothing matches.
SceneTemplate sceneTemplateById(String id) => sceneTemplates.firstWhere(
  (template) => template.id == id,
  orElse: () => sceneTemplates.first,
);

/// A sky and nothing else, which is what a new scene was before templates.
SceneDocument buildEmptyScene() {
  final document = SceneDocument();
  _addSky(document);
  _addSun(document);
  _addCamera(document);
  return document;
}

/// One object, a floor, and light that shows both.
SceneDocument buildStudioScene() {
  final document = SceneDocument();
  _addSky(document);

  final floorMaterial = _material(document, 'Floor', 0.62, 0.63, 0.66);
  final objectMaterial = _material(document, 'Object', 0.80, 0.42, 0.24);

  final floorGeometry = document.addResource(
    GeometryResource(
      document.newId(),
      procedural: PlaneGeometrySpec(width: 24, depth: 24),
    ),
  );
  final cubeGeometry = document.addResource(
    GeometryResource(
      document.newId(),
      procedural: CuboidGeometrySpec(extents: Vector3(1, 1, 1)),
    ),
  );

  _addNode(
    document,
    name: 'Floor',
    components: [_mesh(floorGeometry.id, floorMaterial.id)],
  );
  _addNode(
    document,
    name: 'Cube',
    translation: Vector3(0, 0.5, 0),
    components: [_mesh(cubeGeometry.id, objectMaterial.id)],
  );

  // A key from the front-left and a dimmer fill from behind: one light gives
  // a shape a black side, and a black side reads as a hole rather than as
  // form.
  _addNode(
    document,
    name: 'Key light',
    rotation: _lookDown(-0.9, -0.55),
    components: [
      ComponentSpec(
        'directionalLight',
        properties: {
          'intensity': const DoubleValue(3.2),
          'castsShadows': const BoolValue(true),
        },
      ),
    ],
  );
  _addNode(
    document,
    name: 'Fill light',
    rotation: _lookDown(2.4, -0.35),
    components: [
      ComponentSpec(
        'directionalLight',
        properties: {
          'intensity': const DoubleValue(0.9),
          'color': const ColorValue(0.72, 0.80, 1.0, 1.0),
        },
      ),
    ],
  );
  _addCamera(document);
  return document;
}

/// Ground with shape to it, and a sun that casts across it.
SceneDocument buildOutdoorScene() {
  final document = SceneDocument();
  _addSky(document);

  final groundMaterial = _material(document, 'Ground', 0.34, 0.42, 0.24);
  final terrain = document.addResource(
    GeometryResource(
      document.newId(),
      procedural: TerrainGeometrySpec(
        width: 120,
        depth: 120,
        columns: 129,
        rows: 129,
      ),
    ),
  );

  _addNode(
    document,
    name: 'Terrain',
    components: [_mesh(terrain.id, groundMaterial.id)],
  );
  _addNode(
    document,
    name: 'Sun',
    rotation: _lookDown(-0.7, -0.62),
    components: [
      ComponentSpec(
        'directionalLight',
        properties: {
          'intensity': const DoubleValue(4.0),
          'castsShadows': const BoolValue(true),
        },
      ),
    ],
  );
  _addCamera(document);
  return document;
}

/// Somewhere to drop things and watch them fall.
SceneDocument buildPlaygroundScene() {
  final document = SceneDocument();
  _addSky(document);

  final groundMaterial = _material(document, 'Ground', 0.55, 0.56, 0.60);
  final bodyMaterial = _material(document, 'Body', 0.85, 0.62, 0.20);

  final floor = document.addResource(
    GeometryResource(
      document.newId(),
      procedural: PlaneGeometrySpec(width: 40, depth: 40),
    ),
  );
  final box = document.addResource(
    GeometryResource(
      document.newId(),
      procedural: CuboidGeometrySpec(extents: Vector3(1, 1, 1)),
    ),
  );

  // The world goes on its own node, so deleting the ground does not delete
  // the simulation with it.
  _addNode(
    document,
    name: 'Physics',
    components: [ComponentSpec('physicsWorld')],
  );
  _addNode(
    document,
    name: 'Ground',
    components: [
      _mesh(floor.id, groundMaterial.id),
      ComponentSpec(
        'rigidBody',
        properties: {'type': const StringValue('fixed')},
      ),
      ComponentSpec(
        'collider',
        properties: {
          'shape': MapValue({
            'kind': const StringValue('box'),
            'halfExtents': Vec3Value(Vector3(20, 0.05, 20)),
          }),
        },
      ),
    ],
  );
  _addNode(
    document,
    name: 'Box',
    translation: Vector3(0, 6, 0),
    components: [
      _mesh(box.id, bodyMaterial.id),
      ComponentSpec(
        'rigidBody',
        properties: {'type': const StringValue('dynamic')},
      ),
      ComponentSpec(
        'collider',
        properties: {
          'shape': MapValue({
            'kind': const StringValue('box'),
            'halfExtents': Vec3Value(Vector3(0.5, 0.5, 0.5)),
          }),
        },
      ),
    ],
  );
  _addNode(
    document,
    name: 'Sun',
    rotation: _lookDown(-0.8, -0.6),
    components: [
      ComponentSpec(
        'directionalLight',
        properties: {
          'intensity': const DoubleValue(3.4),
          'castsShadows': const BoolValue(true),
        },
      ),
    ],
  );
  _addCamera(document);
  return document;
}

/// The environment every template starts from: the same sky a new empty
/// scene has always had, so no template is a different kind of document.
void _addSky(SceneDocument document) {
  final environment = document.addResource(
    EnvironmentResource(
      document.newId(),
      name: 'Environment',
      skybox: SkyboxSpec(PhysicalSkySpec()),
      skyEnvironment: SkyEnvironmentSpec(
        PhysicalSkySpec(),
        sunLight: SunLightSpec(),
      ),
    ),
  );
  document.stage.environmentRef = environment.id;
}

/// The sun and the camera every scene starts with.
///
/// A scene with neither is a scene you cannot light and cannot shoot, and
/// adding them back is the same two gestures every time. The sun is the one
/// a template overrides when it wants its own key light; the camera is the
/// shot the scene is framed for, which the editor's own viewport camera is
/// not -- that one is where you happen to be looking.
void _addSun(SceneDocument document, {String name = 'Directional Light'}) {
  _addNode(
    document,
    name: name,
    rotation: _lookDown(-0.7, -0.62),
    components: [
      ComponentSpec(
        'directionalLight',
        properties: {
          'intensity': const DoubleValue(3.4),
          'castsShadows': const BoolValue(true),
        },
      ),
    ],
  );
}

/// A camera set back and above the origin, tilted down at it.
///
/// Roughly where you stand to look at something on the floor, so the first
/// thing rendered through it is the scene rather than the sky.
void _addCamera(SceneDocument document) {
  _addNode(
    document,
    name: 'Camera',
    translation: Vector3(0, 2.4, 7.5),
    rotation: _lookDown(0, -0.18),
    components: [ComponentSpec('camera')],
  );
}

MaterialResource _material(
  SceneDocument document,
  String name,
  double r,
  double g,
  double b, {
  double roughness = 0.85,
}) => document.addResource(
  MaterialResource(
    document.newId(),
    type: 'physicallyBased',
    name: name,
    properties: {
      'baseColor': ColorValue(r, g, b, 1),
      'roughness': DoubleValue(roughness),
      'metallic': const DoubleValue(0),
    },
  ),
);

ComponentSpec _mesh(LocalId geometry, LocalId material) => ComponentSpec(
  'mesh',
  properties: {
    'geometry': ResourceRefValue(geometry),
    'material': ResourceRefValue(material),
  },
);

NodeSpec _addNode(
  SceneDocument document, {
  required String name,
  Vector3? translation,
  Quaternion? rotation,
  List<ComponentSpec> components = const [],
}) {
  final node = NodeSpec(
    id: document.newId(),
    name: name,
    transform: TrsTransform(translation: translation, rotation: rotation),
    components: [...components],
  );
  document.addNode(node, root: true);
  return node;
}

/// A rotation aiming a light's forward axis down and around by [yaw] and
/// [pitch] radians.
///
/// Lights are authored by where they point rather than where they are, and a
/// quaternion typed by hand is nobody's idea of a light direction.
Quaternion _lookDown(double yaw, double pitch) =>
    Quaternion.axisAngle(Vector3(0, 1, 0), yaw) *
    Quaternion.axisAngle(Vector3(1, 0, 0), pitch);

/// Asks which template a new scene starts from.
///
/// Returns the chosen template, or null when the dialog is dismissed -- which
/// means the new scene was not wanted, not that the empty one was.
Future<SceneTemplate?> pickSceneTemplate(BuildContext context) =>
    showEditorDialog<SceneTemplate>(
      context,
      builder: (context) => const _TemplatePickerDialog(),
    );

class _TemplatePickerDialog extends StatelessWidget {
  const _TemplatePickerDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New scene'),
    contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
    content: SizedBox(
      width: 460,
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final template in sceneTemplates)
            ListTile(
              leading: Icon(template.icon, size: 22),
              title: Text(template.name),
              subtitle: Text(template.description),
              onTap: () => Navigator.of(context).pop(template),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
    ],
  );
}
