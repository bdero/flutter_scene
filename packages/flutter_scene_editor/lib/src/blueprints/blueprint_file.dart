/// A blueprint kept as a file, rather than as a component on one node.
///
/// The difference is what makes a blueprint an *asset*. A graph on a node
/// belongs to that node and dies with it; a blueprint in the project is a
/// class — you make one, you make many of it, and editing the file changes
/// every instance. That is what the Project panel is for, and it is why
/// blueprints are created there rather than by selecting something first.
library;

import 'dart:convert';
import 'dart:io';

import 'package:scene/visual_script.dart';

/// The extension a blueprint asset uses.
const String blueprintExtension = '.blueprint';

/// A blueprint file on disk.
class BlueprintFile {
  const BlueprintFile(this.path);

  /// Absolute path to the `.blueprint` file.
  final String path;

  /// The blueprint's name, from the file name.
  String get name {
    final separator = Platform.pathSeparator;
    final base = path.contains(separator)
        ? path.substring(path.lastIndexOf(separator) + 1)
        : path;
    return base.toLowerCase().endsWith(blueprintExtension)
        ? base.substring(0, base.length - blueprintExtension.length)
        : base;
  }

  /// Reads the blueprint, or null when the file is missing or unreadable.
  ///
  /// Null rather than an empty blueprint: opening a file that failed to parse
  /// and being shown a blank canvas is how you save over your own work.
  Blueprint? read() {
    try {
      return readBlueprint(File(path).readAsStringSync());
    } on Object {
      return null;
    }
  }

  /// Writes [blueprint] out, pretty-printed.
  ///
  /// Indented because these are files people diff and merge — a graph is a
  /// thing two people edit, and a single-line JSON blob makes every change
  /// look like every other change.
  Future<void> write(Blueprint blueprint) => File(path).writeAsString(
    const JsonEncoder.withIndent('  ').convert(encodeBlueprint(blueprint)),
  );
}

/// A new blueprint of [kind] extending [parentClass], named [name].
///
/// Comes with the graphs its kind can actually hold, so a new blueprint opens
/// on something you can draw in rather than on an empty list with an Add
/// button. An interface gets no event graph because it cannot have one.
Blueprint newBlueprint({
  required String name,
  required BlueprintKind kind,
  required String parentClass,
}) {
  final blueprint = Blueprint(name: name, kind: kind, parentClass: parentClass);
  final allowed = kind.allowedGraphKinds;
  if (allowed.contains(VisualScriptGraphKind.eventGraph)) {
    blueprint.addGraph(
      VisualScriptGraph(),
      kind: VisualScriptGraphKind.eventGraph,
      name: defaultEventGraphName,
    );
  } else if (allowed.contains(VisualScriptGraphKind.function)) {
    blueprint.addGraph(
      VisualScriptGraph(),
      kind: VisualScriptGraphKind.function,
      name: 'New Function',
    );
  } else {
    blueprint.addGraph(
      VisualScriptGraph(),
      kind: VisualScriptGraphKind.macro,
      name: 'New Macro',
    );
  }
  return blueprint;
}

/// A path under [root] for a blueprint called [name] that nothing else uses.
///
/// Numbered rather than overwritten, the way every other new asset here is:
/// making a second Door should give you a second Door, not replace the first.
String freeBlueprintPath(String root, String name) {
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9_\- ]'), '').trim();
  final base = safe.isEmpty ? 'Blueprint' : safe;
  final separator = Platform.pathSeparator;
  for (var i = 0; ; i++) {
    final candidate = i == 0
        ? '$root$separator$base$blueprintExtension'
        : '$root$separator$base $i$blueprintExtension';
    if (!File(candidate).existsSync()) return candidate;
  }
}

/// The default name for a new blueprint of [kind].
String defaultBlueprintName(BlueprintKind kind) => switch (kind) {
  BlueprintKind.blueprintClass => 'NewBlueprint',
  BlueprintKind.widgetBlueprint => 'NewWidgetBlueprint',
  BlueprintKind.blueprintInterface => 'NewBlueprintInterface',
  BlueprintKind.macroLibrary => 'NewMacroLibrary',
};
