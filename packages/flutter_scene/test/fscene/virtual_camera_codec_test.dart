// The virtual-camera codec. A shot is two polymorphic parts, so what these
// cover is the tagged-union round trip: that the kind and its own fields
// survive, that an unknown or half-written variant lands somewhere usable
// rather than throwing, and that an untouched camera stays out of the document.

import 'package:flutter_scene/src/camera_controllers/virtual_camera.dart';
import 'package:flutter_scene/src/components/component.dart';
import 'package:flutter_scene/src/math_extensions.dart';
import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_scene/src/fscene/realize/virtual_camera_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:vector_math/vector_math.dart';

void main() {
  final registry = defaultComponentRegistry();
  final doc = SceneDocument();

  VirtualCamera realize([Map<String, PropertyValue> properties = const {}]) =>
      registry
              .codecFor('virtualCamera')!
              .realize(
                ComponentSpec('virtualCamera', properties: properties),
                RealizeContext(doc),
              )!
          as VirtualCamera;

  Map<String, PropertyValue> serialize(Component component) => registry
      .codecFor('virtualCamera')!
      .serialize(component, SerializeContext(doc))!
      .properties;

  /// A camera through a save and a load.
  VirtualCamera roundTrip(VirtualCamera camera) => realize(serialize(camera));

  test('the codec is registered and discoverable under Cameras', () {
    final codec = registry.codecFor('virtualCamera');
    expect(codec, isNotNull);
    expect(codec!.schema.category, 'Cameras');
  });

  test('an untouched camera writes nothing', () {
    // Every component in this engine serializes as a delta from its schema
    // defaults, and a union is not exempt: a camera nobody edited should not
    // put a body and an aim in the file.
    expect(serialize(VirtualCamera()), isEmpty);
  });

  group('body', () {
    test('a transposer keeps its offset, binding and damping', () {
      final before = VirtualCamera(
        body: TransposerBody(
          offset: Vector3(1, 3, -7),
          binding: CameraBinding.worldSpace,
          damping: Vector3(0.1, 0.6, 0.9),
        ),
      );
      final body = roundTrip(before).body as TransposerBody;
      expect(body.offset, Vector3(1, 3, -7));
      expect(body.binding, CameraBinding.worldSpace);
      expect(body.damping, Vector3(0.1, 0.6, 0.9));
    });

    test('a framing transposer keeps its dead zone', () {
      final before = VirtualCamera(
        body: FramingTransposerBody(distance: 5, height: 1.8, deadZone: 1.25),
      );
      final body = roundTrip(before).body as FramingTransposerBody;
      expect(body.distance, 5);
      expect(body.height, 1.8);
      expect(body.deadZone, 1.25);
    });

    test('an orbital keeps its radius and heading', () {
      final before = VirtualCamera(
        body: OrbitalBody(radius: 12, height: 4, heading: 1.1),
      );
      final body = roundTrip(before).body as OrbitalBody;
      expect(body.radius, 12);
      expect(body.heading, closeTo(1.1, 1e-9));
    });

    test('the kind is what picks the variant, not the fields present', () {
      final camera = realize({
        'body': MapValue({
          'kind': const StringValue('orbital'),
          'radius': const DoubleValue(3),
          // A leftover from a transposer the document used to hold.
          'offset': Vec3Value(Vector3(9, 9, 9)),
        }),
      });
      expect(camera.body, isA<OrbitalBody>());
      expect((camera.body as OrbitalBody).radius, 3);
    });

    test('an unknown kind lands on a transposer rather than throwing', () {
      // A document from a newer build, or one hand-edited. A camera that
      // cannot be loaded takes the whole scene with it.
      final camera = realize({
        'body': MapValue({'kind': const StringValue('dolly')}),
      });
      expect(camera.body, isA<TransposerBody>());
    });

    test('a variant missing its fields falls back per field', () {
      final camera = realize({
        'body': MapValue({'kind': const StringValue('framingTransposer')}),
      });
      final body = camera.body as FramingTransposerBody;
      expect(body.distance, 8);
      expect(body.deadZone, 0.6);
    });

    test('an unknown binding is the third-person default', () {
      final camera = realize({
        'body': MapValue({
          'kind': const StringValue('transposer'),
          'binding': const StringValue('lockToRig'),
        }),
      });
      expect(
        (camera.body as TransposerBody).binding,
        CameraBinding.lockToTargetWithWorldUp,
      );
    });

    test('a body written in code saves as something loadable', () {
      // A CameraBody subclass from a game has no document form. Writing a kind
      // nothing can read back would make the scene fail to load next time.
      final encoded = encodeCameraBody(_CustomBody());
      expect(decodeCameraBody(encoded), isA<TransposerBody>());
    });

    test('the declared variants are the ones the encoder emits', () {
      // The inspector builds its kind picker from the schema, so a variant the
      // encoder can produce but the schema does not declare would be a shot
      // that saves and then cannot be edited.
      final body = registry
          .codecFor('virtualCamera')!
          .schema
          .properties
          .firstWhere((p) => p.name == 'body');
      expect(body.unionVariants!.keys.toSet(), {
        'transposer',
        'framingTransposer',
        'orbital',
      });
      for (final made in [
        TransposerBody(),
        FramingTransposerBody(),
        OrbitalBody(),
      ]) {
        final kind =
            (encodeCameraBody(made).values['kind']! as StringValue).value;
        expect(body.unionVariants!.containsKey(kind), isTrue, reason: kind);
      }
    });

    test('every declared body field is one the decoder reads', () {
      // A field in the schema the decoder ignores is a control that silently
      // does nothing.
      final body = registry
          .codecFor('virtualCamera')!
          .schema
          .properties
          .firstWhere((p) => p.name == 'body');
      for (final entry in body.unionVariants!.entries) {
        for (final field in entry.value) {
          final encoded = encodeCameraBody(
            decodeCameraBody(MapValue({'kind': StringValue(entry.key), ...{}})),
          );
          expect(
            encoded.values.containsKey(field.name),
            isTrue,
            reason: '${entry.key}.${field.name} is declared but not written',
          );
        }
      }
    });
  });

  group('aim', () {
    test('a composer keeps its dead zone and damping', () {
      final before = VirtualCamera(
        aim: ComposerAim(deadZoneDegrees: 12, damping: 0.8),
      );
      final aim = roundTrip(before).aim as ComposerAim;
      expect(aim.deadZoneDegrees, 12);
      expect(aim.damping, 0.8);
    });

    test('a fixed aim keeps its rotation', () {
      final held = Quaternion.axisAngle(Vector3(0, 1, 0), 1.2);
      final aim = roundTrip(VirtualCamera(aim: FixedAim(rotation: held))).aim;
      expect(aim, isA<FixedAim>());
      expect((aim as FixedAim).rotation.dot(held).abs(), closeTo(1, 1e-6));
    });

    test('a zero quaternion does not load as a broken rotation', () {
      // An absent or hand-zeroed vec4 cannot be normalized; identity is the
      // only sane reading of it.
      final camera = realize({
        'aim': MapValue({
          'kind': const StringValue('fixed'),
          'rotation': Vec4Value(Vector4.zero()),
        }),
      });
      expect((camera.aim as FixedAim).rotation.length, closeTo(1, 1e-9));
    });

    test('hard look at survives having no fields at all', () {
      final aim = roundTrip(VirtualCamera(aim: HardLookAtAim())).aim;
      expect(aim, isA<HardLookAtAim>());
    });

    test('an unknown kind lands on a hard look at', () {
      final camera = realize({
        'aim': MapValue({'kind': const StringValue('groupComposer')}),
      });
      expect(camera.aim, isA<HardLookAtAim>());
    });
  });

  group('the rest of the shot', () {
    test('priority round trips, negatives included', () {
      // A shot parked below the others until gameplay raises it.
      expect(roundTrip(VirtualCamera(priority: -5)).priority, -5);
      expect(roundTrip(VirtualCamera(priority: 30)).priority, 30);
    });

    test('follow and lookAt are absent when unset', () {
      final written = serialize(VirtualCamera());
      expect(written, isNot(contains('follow')));
      expect(written, isNot(contains('lookAt')));
    });

    test('a camera loaded from an empty spec is usable as it stands', () {
      // What Add > Camera > Virtual Camera produces before anything is set.
      final camera = realize();
      expect(camera.body, isA<TransposerBody>());
      expect(camera.aim, isA<HardLookAtAim>());
      camera.advance(1 / 60);
      expect(camera.pose.position.x.isFinite, isTrue);
      expect(camera.pose.rotation.length, closeTo(1, 1e-6));
    });

    test('a full shot survives two round trips unchanged', () {
      // Once catches a decode that drops a field; twice catches an encode that
      // writes something the decoder reads back differently.
      final before = VirtualCamera(
        body: FramingTransposerBody(
          distance: 4.5,
          height: 1.6,
          deadZone: 0.9,
          damping: Vector3(0.2, 0.5, 0.2),
        ),
        aim: ComposerAim(deadZoneDegrees: 7, damping: 0.5),
        priority: 15,
        smoothing: 0.1,
      );
      final once = serialize(roundTrip(before));
      final twice = serialize(roundTrip(roundTrip(before)));
      expect(twice.toString(), once.toString());
    });
  });
}

/// A body a game might write, with no document form.
class _CustomBody extends CameraBody {
  @override
  void solve(CameraSolveContext context, Vector3 out) => out.setZero();
}
