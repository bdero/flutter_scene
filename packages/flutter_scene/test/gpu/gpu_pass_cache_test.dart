// ignore_for_file: implementation_imports
import 'dart:typed_data';

import 'package:flutter_scene/src/gpu/shared/gpu_pass_cache.dart';
import 'package:test/test.dart';

void main() {
  group('PassBindingTable', () {
    test('explicit bindings win over cross-stage implicit bindings per epoch', () {
      final table = PassBindingTable<String, String, String>();

      // Implicit mirror fills an unbound stage slot and updates if still implicit.
      table.bindUniform(0, 'u_implicit_1', 0, 64, explicit: false);
      expect(table.hasUniform(0), isTrue);
      expect(table.uniformBuffer(0), 'u_implicit_1');

      table.bindUniform(0, 'u_implicit_2', 256, 64, explicit: false);
      expect(table.uniformBuffer(0), 'u_implicit_2');
      expect(table.uniformOffset(0), 256);

      // Explicit bind overrides implicit bind and blocks later implicit writes.
      table.bindUniform(0, 'u_explicit', 512, 32, explicit: true);
      table.bindUniform(0, 'u_ignored', 768, 32, explicit: false);
      expect(table.uniformBuffer(0), 'u_explicit');
      expect(table.uniformOffset(0), 512);
      expect(table.uniformLength(0), 32);

      // Next epoch starts clean and accepts implicit mirrors again.
      table.clear();
      expect(table.hasUniform(0), isFalse);
      table.bindUniform(0, 'u_next_epoch', 0, 16, explicit: false);
      expect(table.hasUniform(0), isTrue);
      expect(table.uniformBuffer(0), 'u_next_epoch');
    });

    test(
      'texture and sampler bindings follow explicit precedence and clear',
      () {
        final table = PassBindingTable<String, String, String>();

        table.bindTexture(65, 'tex_a', 'linear', explicit: false);
        expect(table.hasTexture(65), isTrue);
        expect(table.texture(65), 'tex_a');
        expect(table.sampler(65), 'linear');

        table.bindTexture(65, 'tex_explicit', null, explicit: true);
        table.bindTexture(65, 'tex_ignored', 'nearest', explicit: false);
        expect(table.texture(65), 'tex_explicit');
        expect(table.sampler(65), isNull);

        table.clear();
        expect(table.hasTexture(65), isFalse);
      },
    );

    test(
      'grows uniform, texture, and vertex capacities while keeping bindings',
      () {
        final table = PassBindingTable<String, String, String>(
          initialBindingCapacity: 4,
          initialVertexSlots: 2,
        );

        table.bindUniform(2, 'u2', 0, 16, explicit: true);
        table.bindUniform(300, 'u300', 1024, 64, explicit: true);
        expect(table.hasUniform(2), isTrue);
        expect(table.uniformBuffer(2), 'u2');
        expect(table.hasUniform(300), isTrue);
        expect(table.uniformBuffer(300), 'u300');
        expect(table.uniformOffset(300), 1024);

        table.bindTexture(1, 't1', 's1', explicit: true);
        table.bindTexture(260, 't260', 's260', explicit: false);
        expect(table.hasTexture(1), isTrue);
        expect(table.texture(260), 't260');
        expect(table.sampler(260), 's260');

        table.bindVertexBuffer(0, 'vb0', 0);
        table.bindVertexBuffer(9, 'vb9', 128);
        expect(table.hasVertexBuffer(0), isTrue);
        expect(table.hasVertexBuffer(1), isFalse);
        expect(table.hasVertexBuffer(9), isTrue);
        expect(table.vertexBuffer(9), 'vb9');
        expect(table.vertexOffset(9), 128);

        expect(table.hasUniform(-1), isFalse);
        expect(table.hasUniform(9999), isFalse);
        expect(table.hasTexture(-1), isFalse);
        expect(table.hasTexture(9999), isFalse);
        expect(table.hasVertexBuffer(-1), isFalse);
        expect(table.hasVertexBuffer(99), isFalse);

        table.clear();
        expect(table.hasUniform(300), isFalse);
        expect(table.hasTexture(260), isFalse);
        expect(table.hasVertexBuffer(9), isFalse);
      },
    );
  });

  group('IntTupleCache', () {
    test('hits MRU and map entries without aliasing caller scratch', () {
      final cache = IntTupleCache<String>(maxEntries: 8);
      final scratch = Uint32List(8);

      scratch[0] = 10;
      scratch[1] = 64;
      scratch[2] = 0xffffffff;
      expect(cache.lookup(scratch, 3), isNull);
      cache.put(scratch, 3, 'group_a');

      // Mutating scratch after put must not corrupt MRU or stored key.
      scratch[0] = 20;
      scratch[1] = 128;
      scratch[2] = 0x80000000;
      expect(cache.lookup(scratch, 3), isNull);
      cache.put(scratch, 3, 'group_b');

      // Consecutive MRU hit on group_b.
      expect(cache.lookup(scratch, 3), 'group_b');

      // Alternating A -> B -> A -> B exercises hash-table hit + MRU promotion.
      scratch[0] = 10;
      scratch[1] = 64;
      scratch[2] = 0xffffffff;
      expect(cache.lookup(scratch, 3), 'group_a');
      expect(cache.lookup(scratch, 3), 'group_a');

      // Prefix / length differences do not collide.
      scratch[3] = 0;
      expect(cache.lookup(scratch, 4), isNull);
      expect(cache.lookup(scratch, 2), isNull);
    });

    test('clears when maxEntries is reached', () {
      final cache = IntTupleCache<String>(maxEntries: 3);
      final scratch = Uint32List(2);

      for (var i = 0; i < 3; i++) {
        scratch[0] = i;
        scratch[1] = i * 16;
        cache.put(scratch, 2, 'g$i');
      }
      expect(cache.length, 3);

      scratch[0] = 99;
      scratch[1] = 32;
      cache.put(scratch, 2, 'g99');
      expect(cache.length, 1);
      expect(cache.lookup(scratch, 2), 'g99');

      scratch[0] = 0;
      scratch[1] = 0;
      expect(cache.lookup(scratch, 2), isNull);
    });
  });
}
