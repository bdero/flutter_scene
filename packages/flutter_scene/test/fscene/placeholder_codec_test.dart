// Covers foreign-component placeholders: a schema-only type realizes into an
// inert data bag, serializes back losslessly (including undeclared keys),
// and the process-wide default registry memoizes.

import 'package:flutter_scene/src/fscene/realize/component_codec.dart';
import 'package:flutter_scene/src/fscene/realize/placeholder_codec.dart';
import 'package:flutter_scene/src/fscene/realize/realize.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';
import 'package:scene/schema.dart';

void main() {
  const schema = ComponentSchema(
    'spin',
    doc: 'Spins the node.',
    properties: [
      ComponentPropertyDef(
        'speed',
        ComponentPropertyKind.number,
        defaultValue: DoubleValue(1),
        constraints: [SoftRange(0, 10)],
      ),
    ],
  );

  test('a placeholder realizes and serializes losslessly', () {
    final registry = FsceneComponentRegistry()
      ..register(PlaceholderComponentCodec(schema));
    final document = SceneDocument();
    final spec = ComponentSpec(
      'spin',
      properties: {
        'speed': const DoubleValue(4),
        'extraUndeclared': const StringValue('kept'),
      },
    );

    final realized = registry.realize(spec, RealizeContext(document));
    expect(realized, isA<ForeignComponent>());

    final reserialized = registry.serialize(
      realized!,
      SerializeContext(document),
    )!;
    expect(reserialized.type, 'spin');
    expect(
      propertyValuesEqual(
        reserialized.properties['speed'],
        const DoubleValue(4),
      ),
      isTrue,
    );
    expect(
      propertyValuesEqual(
        reserialized.properties['extraUndeclared'],
        const StringValue('kept'),
      ),
      isTrue,
      reason: 'undeclared keys are never dropped',
    );
    expect(registry.codecFor('spin')!.propertySchema.single.name, 'speed');
  });

  test('the default registry is a memoized process-wide singleton', () {
    debugResetDefaultComponentRegistry();
    final first = defaultComponentRegistry();
    expect(identical(first, defaultComponentRegistry()), isTrue);
    first.register(PlaceholderComponentCodec(schema));
    expect(
      defaultComponentRegistry().codecFor('spin'),
      isNotNull,
      reason: 'a registration reaches every later default use',
    );
    debugResetDefaultComponentRegistry();
    expect(defaultComponentRegistry().codecFor('spin'), isNull);
  });
}
