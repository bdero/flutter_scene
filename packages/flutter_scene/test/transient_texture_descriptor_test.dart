// The pool keys its rings by descriptor equality, so a color target rendered
// with more than one depth setup must split on attachmentKey (the GLES
// backend caches one framebuffer per color texture and never re-attaches
// depth), while everything else stays shared.

import 'package:flutter_scene/src/gpu/gpu.dart' as gpu;
import 'package:flutter_scene/src/render/render_graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const base = TransientTextureDescriptor.color(
    width: 64,
    height: 32,
    format: gpu.PixelFormat.r16g16b16a16Float,
    debugName: 'scene_color',
  );

  test('descriptors that differ only in attachmentKey are distinct', () {
    const stored = TransientTextureDescriptor.color(
      width: 64,
      height: 32,
      format: gpu.PixelFormat.r16g16b16a16Float,
      debugName: 'scene_color',
      attachmentKey: 'depth_stored',
    );
    const resolve = TransientTextureDescriptor.color(
      width: 64,
      height: 32,
      format: gpu.PixelFormat.r16g16b16a16Float,
      debugName: 'scene_color',
      attachmentKey: 'resolve',
    );
    expect(stored, isNot(equals(base)));
    expect(stored, isNot(equals(resolve)));
    expect({base, stored, resolve}, hasLength(3));
  });

  test('the same attachmentKey shares a slot', () {
    const a = TransientTextureDescriptor(
      width: 8,
      height: 8,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
      attachmentKey: 'depth_transient',
    );
    const b = TransientTextureDescriptor(
      width: 8,
      height: 8,
      format: gpu.PixelFormat.r8g8b8a8UNormInt,
      attachmentKey: 'depth_transient',
    );
    expect(a, equals(b));
    expect(a.hashCode, b.hashCode);
  });
}
