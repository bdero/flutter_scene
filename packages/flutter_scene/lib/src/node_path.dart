import 'package:flutter/foundation.dart' show internal;

import 'package:flutter_scene/src/node.dart';

/// [node]'s path from its root for a diagnostic, by name, with an unnamed
/// node shown as its index among its parent's children (`root/#3`).
@internal
String debugNodePath(Node node) {
  final parts = <String>[];
  Node? current = node;
  while (current != null) {
    final parent = current.parent;
    if (current.name.isNotEmpty) {
      parts.add(current.name);
    } else if (parent != null) {
      parts.add('#${parent.children.indexOf(current)}');
    }
    current = parent;
  }
  return parts.isEmpty ? '(unnamed)' : parts.reversed.join('/');
}
