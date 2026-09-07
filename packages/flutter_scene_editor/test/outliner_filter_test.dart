// The outliner's name filter. Pure over name and children lookups, so the
// tree logic runs without a document or a GPU.
import 'package:flutter_scene_editor/src/panels/outliner_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scene/scene.dart';

/// A small scene:
///   world
///     lights
///       sun
///       lamp
///     props
///       crate
final _doc = SceneDocument();
final _ids = {
  for (final name in ['world', 'lights', 'sun', 'lamp', 'props', 'crate'])
    name: _doc.newId(),
};

const _tree = {
  'world': ['lights', 'props'],
  'lights': ['sun', 'lamp'],
  'props': ['crate'],
  'sun': <String>[],
  'lamp': <String>[],
  'crate': <String>[],
};

String _nameOf(LocalId id) => _ids.entries.firstWhere((e) => e.value == id).key;

List<LocalId> _childrenOf(LocalId id) => [
  for (final name in _tree[_nameOf(id)]!) _ids[name]!,
];

Set<String> filter(String query) => outlinerFilterMatches(
  roots: [_ids['world']!],
  childrenOf: _childrenOf,
  nameOf: _nameOf,
  query: query,
).map(_nameOf).toSet();

void main() {
  test('a blank query keeps the whole tree', () {
    expect(filter(''), _ids.keys.toSet());
    expect(filter('   '), _ids.keys.toSet());
  });

  test('a match keeps the branch above it', () {
    // A hit three levels down means nothing without the path to it.
    expect(filter('lamp'), {'world', 'lights', 'lamp'});
  });

  test('a match keeps everything below it', () {
    // Filtering to a container should show what is inside it.
    expect(filter('lights'), {'world', 'lights', 'sun', 'lamp'});
  });

  test('matching is case-insensitive and partial', () {
    expect(filter('LAM'), {'world', 'lights', 'lamp'});
    expect(filter('ra'), {'world', 'props', 'crate'});
  });

  test('several matches keep both branches', () {
    // "s" hits lights, sun and props.
    final kept = filter('s');
    expect(kept, contains('sun'));
    expect(kept, contains('props'));
    expect(kept, contains('world'));
  });

  test('no match keeps nothing at all', () {
    expect(filter('zzz'), isEmpty);
  });

  test('matching the root keeps the root and its subtree', () {
    expect(filter('world'), _ids.keys.toSet());
  });
}
