/// Tier-1 syntax-only component extraction: parses a Dart source string
/// (no resolution) and lowers `@SceneComponent`/`@SceneProperty` annotations
/// to portable `ComponentSchema` descriptors plus the per-field details the
/// generator needs.
// TODO(tier2-resolution): a resolved-AST tier would see enums, defaults, and
// component classes declared in other files; this tier only reads the one
// source string it is given.
library;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:scene/scene.dart';
import 'package:scene/schema.dart';
import 'package:vector_math/vector_math.dart';

/// How severe an [ExtractionDiagnostic] is. A warning degrades the schema
/// (a missing default, unresolved enum options); an error drops a declared
/// field or component from generation.
enum ExtractionSeverity { warning, error }

/// One extraction problem, tied to a source location.
class ExtractionDiagnostic {
  const ExtractionDiagnostic({
    this.path,
    required this.line,
    required this.message,
    required this.severity,
  });

  /// The source path, when one was passed to [extractComponents].
  final String? path;

  /// The 1-based source line.
  final int line;

  /// A human-readable description of the problem.
  final String message;

  /// See [ExtractionSeverity].
  final ExtractionSeverity severity;

  @override
  String toString() => '${severity.name}: ${path ?? '<source>'}:$line $message';
}

/// One extracted property: the portable descriptor plus the syntax facts
/// the generator needs to emit bindings against the real field.
class ExtractedProperty {
  const ExtractedProperty({
    required this.def,
    required this.declaredType,
    required this.nullable,
    this.enumTypeName,
    this.enumResolved = false,
    this.normalized = false,
  });

  /// The portable descriptor.
  final ComponentPropertyDef def;

  /// The declared field type name, without nullability (`double`, `Vector3`).
  final String declaredType;

  /// Whether the declared field type is nullable.
  final bool nullable;

  /// For enum-backed string properties, the enum type name.
  final String? enumTypeName;

  /// Whether [enumTypeName] was declared in the same source (so generated
  /// code may name it).
  final bool enumResolved;

  /// Whether a [Normalized] constraint applies (vec write normalizes).
  final bool normalized;
}

/// One extracted component class.
class ExtractedComponent {
  const ExtractedComponent({
    required this.schema,
    required this.className,
    required this.properties,
  });

  /// The portable schema.
  final ComponentSchema schema;

  /// The annotated Dart class name.
  final String className;

  /// Per-property extraction details, parallel to [ComponentSchema.properties].
  final List<ExtractedProperty> properties;
}

/// The result of extracting one source string.
class ExtractionResult {
  const ExtractionResult({
    required this.components,
    required this.diagnostics,
    this.parseFailed = false,
  });

  /// The extracted components, in declaration order.
  final List<ExtractedComponent> components;

  /// Problems encountered, in source order.
  final List<ExtractionDiagnostic> diagnostics;

  /// Whether the source failed to parse. An unparseable file (mid-edit) is
  /// indistinguishable from a component-free one by [components] alone, so
  /// sweeps must not treat it as "declares nothing" (deleting outputs or
  /// retiring schemas).
  final bool parseFailed;
}

const Set<String> _propertyAnnotationNames = {
  'SceneProperty',
  'BoolProperty',
  'IntProperty',
  'NumberProperty',
  'StringProperty',
  'EnumProperty',
  'Vec2Property',
  'Vec3Property',
  'Vec4Property',
  'QuaternionProperty',
  'ColorProperty',
  'AssetProperty',
  'ResourceProperty',
  'NodeProperty',
  'AngleProperty',
};

/// Extracts every `@SceneComponent` class in [source]. [path] is used only
/// for diagnostics.
ExtractionResult extractComponents(String source, {String? path}) {
  final parse = parseString(
    content: source,
    path: path,
    throwIfDiagnostics: false,
  );
  final extraction = _Extraction(path, parse.lineInfo);
  final parseFailed = parse.errors.isNotEmpty;
  for (final error in parse.errors) {
    extraction._error(error.offset, 'syntax error: ${error.message}');
  }
  final enums = <String, List<String>>{};
  for (final declaration in parse.unit.declarations) {
    if (declaration is EnumDeclaration) {
      enums[declaration.namePart.typeName.lexeme] = [
        for (final constant in declaration.body.constants) constant.name.lexeme,
      ];
    }
  }
  final components = <ExtractedComponent>[];
  for (final declaration in parse.unit.declarations) {
    if (declaration is! ClassDeclaration) continue;
    final component = extraction._extractClass(declaration, enums);
    if (component != null) components.add(component);
  }
  return ExtractionResult(
    components: components,
    diagnostics: extraction.diagnostics,
    parseFailed: parseFailed,
  );
}

class _Extraction {
  _Extraction(this.path, this.lineInfo);

  final String? path;
  final LineInfo lineInfo;
  final diagnostics = <ExtractionDiagnostic>[];

  void _report(int offset, String message, ExtractionSeverity severity) {
    diagnostics.add(
      ExtractionDiagnostic(
        path: path,
        line: lineInfo.getLocation(offset).lineNumber,
        message: message,
        severity: severity,
      ),
    );
  }

  void _warn(int offset, String message) =>
      _report(offset, message, ExtractionSeverity.warning);

  void _error(int offset, String message) =>
      _report(offset, message, ExtractionSeverity.error);

  ExtractedComponent? _extractClass(
    ClassDeclaration declaration,
    Map<String, List<String>> enums,
  ) {
    Annotation? componentAnnotation;
    Annotation? gizmoAnnotation;
    for (final annotation in declaration.metadata) {
      switch (_annotationName(annotation)) {
        case 'SceneComponent':
          componentAnnotation ??= annotation;
        case 'SceneGizmo':
          gizmoAnnotation ??= annotation;
      }
    }
    if (componentAnnotation == null) return null;
    final className = declaration.namePart.typeName.lexeme;
    final args = _Args(componentAnnotation.arguments);
    final type = _stringLit(
      args.positional.isEmpty ? null : args.positional.first,
    );
    if (type == null) {
      _error(
        componentAnnotation.offset,
        '@SceneComponent on $className needs a literal type string',
      );
      return null;
    }
    if (!_hasZeroArgConstructor(declaration)) {
      // TODO(ctor-args): support constructor parameters by routing
      // constructor-only properties through create(props).
      _error(
        declaration.offset,
        '$className has no zero-argument constructor; generated codecs '
        'construct components with $className()',
      );
      return null;
    }
    final properties = <ExtractedProperty>[];
    for (final member in declaration.body.members) {
      if (member is! FieldDeclaration || member.isStatic) continue;
      properties.addAll(_extractField(member, enums));
    }
    final schema = ComponentSchema(
      type,
      doc: _stringLit(args.named['doc']) ?? _docText(declaration),
      icon: _stringLit(args.named['icon']),
      category: _stringLit(args.named['category']),
      formerTypes: _stringListLit(args.named['formerTypes']) ?? const [],
      properties: [for (final property in properties) property.def],
      gizmo: gizmoAnnotation == null ? null : _lowerGizmo(gizmoAnnotation),
    );
    return ExtractedComponent(
      schema: schema,
      className: className,
      properties: properties,
    );
  }

  List<ExtractedProperty> _extractField(
    FieldDeclaration member,
    Map<String, List<String>> enums,
  ) {
    Annotation? propertyAnnotation;
    String? annotationName;
    for (final annotation in member.metadata) {
      final name = _annotationName(annotation);
      if (_propertyAnnotationNames.contains(name)) {
        propertyAnnotation = annotation;
        annotationName = name;
        break;
      }
    }
    if (propertyAnnotation == null || annotationName == null) return const [];

    final typeAnnotation = member.fields.type;
    var declaredType = '';
    var nullable = false;
    if (typeAnnotation is NamedType) {
      declaredType = typeAnnotation.name.lexeme;
      nullable = typeAnnotation.question != null;
    } else if (typeAnnotation != null) {
      declaredType = typeAnnotation.toSource();
    }

    final args = _Args(propertyAnnotation.arguments);
    final resolved = _resolveKind(
      annotationName,
      declaredType,
      enums,
      args,
      propertyAnnotation.offset,
    );
    if (resolved == null) return const [];

    final constraints = _lowerConstraints(
      annotationName,
      args,
      propertyAnnotation.offset,
    );
    final normalized = constraints.any(
      (constraint) => constraint is Normalized,
    );
    final doc = _docText(member);
    final group = _stringLit(args.named['group']);
    final formerNames = _stringListLit(args.named['formerNames']) ?? const [];
    final transient = _boolLit(args.named['transient']) ?? false;

    final extracted = <ExtractedProperty>[];
    for (final variable in member.fields.variables) {
      final name = variable.name.lexeme;
      PropertyValue? defaultValue;
      final initializer = variable.initializer;
      if (initializer != null) {
        defaultValue = _defaultFromInitializer(
          initializer,
          resolved.kind,
          resolved.enumTypeName,
        );
        if (defaultValue == null) {
          _warn(
            initializer.offset,
            'dynamic default for $name, no schema default recorded',
          );
        }
      }
      extracted.add(
        ExtractedProperty(
          def: ComponentPropertyDef(
            name,
            resolved.kind,
            defaultValue: defaultValue,
            doc: doc,
            group: group,
            resourceKind: resolved.resourceKind,
            options: resolved.options,
            constraints: constraints,
            formerNames: formerNames,
            transient: transient,
          ),
          declaredType: declaredType,
          nullable: nullable,
          enumTypeName: resolved.enumTypeName,
          enumResolved: resolved.enumResolved,
          normalized: normalized,
        ),
      );
    }
    return extracted;
  }

  /// Lowers an `@SceneGizmo([...])` annotation to a [GizmoSpec], skipping
  /// (with a warning) primitives the syntax evaluator cannot read.
  GizmoSpec? _lowerGizmo(Annotation annotation) {
    final args = _Args(annotation.arguments);
    final list = args.positional.isEmpty ? null : args.positional.first;
    if (list is! ListLiteral) {
      _error(
        annotation.offset,
        '@SceneGizmo needs a literal list of gizmo primitives',
      );
      return null;
    }
    final primitives = <GizmoPrimitive>[];
    for (final element in list.elements) {
      if (element is! Expression) continue;
      final primitive = _gizmoPrimitiveFromExpression(element);
      if (primitive == null) {
        _warn(
          element.offset,
          'unrecognized gizmo primitive ${element.toSource()}',
        );
        continue;
      }
      primitives.add(primitive);
    }
    return GizmoSpec(primitives);
  }

  _ResolvedKind? _resolveKind(
    String annotationName,
    String declaredType,
    Map<String, List<String>> enums,
    _Args args,
    int offset,
  ) {
    switch (annotationName) {
      case 'BoolProperty':
        return const _ResolvedKind(ComponentPropertyKind.boolean);
      case 'IntProperty':
        return const _ResolvedKind(ComponentPropertyKind.integer);
      case 'NumberProperty':
      case 'AngleProperty':
        return const _ResolvedKind(ComponentPropertyKind.number);
      case 'StringProperty':
        return const _ResolvedKind(ComponentPropertyKind.string);
      case 'EnumProperty':
        return _enumKind(declaredType, enums, offset);
      case 'Vec2Property':
        return const _ResolvedKind(ComponentPropertyKind.vec2);
      case 'Vec3Property':
        return const _ResolvedKind(ComponentPropertyKind.vec3);
      case 'Vec4Property':
        return const _ResolvedKind(ComponentPropertyKind.vec4);
      case 'QuaternionProperty':
        return const _ResolvedKind(ComponentPropertyKind.quaternion);
      case 'ColorProperty':
        return const _ResolvedKind(ComponentPropertyKind.color);
      case 'AssetProperty':
        return const _ResolvedKind(ComponentPropertyKind.assetRef);
      case 'ResourceProperty':
        final kind = _stringLit(args.named['resourceKind']);
        if (kind == null) {
          _error(offset, '@ResourceProperty needs a literal resourceKind');
          return null;
        }
        return _ResolvedKind(
          ComponentPropertyKind.resourceRef,
          resourceKind: kind,
        );
      case 'NodeProperty':
        return const _ResolvedKind(ComponentPropertyKind.nodeRef);
      case 'SceneProperty':
        return _kindFromType(declaredType, enums, offset);
    }
    return null;
  }

  _ResolvedKind _enumKind(
    String declaredType,
    Map<String, List<String>> enums,
    int offset,
  ) {
    final options = enums[declaredType];
    if (options == null) {
      _warn(
        offset,
        'enum options unresolved for $declaredType (declared in another '
        'file); options omitted',
      );
      return _ResolvedKind(
        ComponentPropertyKind.string,
        enumTypeName: declaredType.isEmpty ? null : declaredType,
      );
    }
    return _ResolvedKind(
      ComponentPropertyKind.string,
      options: options,
      enumTypeName: declaredType,
      enumResolved: true,
    );
  }

  _ResolvedKind? _kindFromType(
    String declaredType,
    Map<String, List<String>> enums,
    int offset,
  ) {
    switch (declaredType) {
      case 'double':
      case 'num':
        return const _ResolvedKind(ComponentPropertyKind.number);
      case 'int':
        return const _ResolvedKind(ComponentPropertyKind.integer);
      case 'bool':
        return const _ResolvedKind(ComponentPropertyKind.boolean);
      case 'String':
        return const _ResolvedKind(ComponentPropertyKind.string);
      case 'Vector2':
        return const _ResolvedKind(ComponentPropertyKind.vec2);
      case 'Vector3':
        return const _ResolvedKind(ComponentPropertyKind.vec3);
      case 'Vector4':
        return const _ResolvedKind(ComponentPropertyKind.vec4);
      case 'Quaternion':
        return const _ResolvedKind(ComponentPropertyKind.quaternion);
      case 'Color':
        return const _ResolvedKind(ComponentPropertyKind.color);
      case 'Matrix4':
        return const _ResolvedKind(ComponentPropertyKind.matrix4);
      case 'Node':
        return const _ResolvedKind(ComponentPropertyKind.nodeRef);
      case 'Geometry':
        return const _ResolvedKind(
          ComponentPropertyKind.resourceRef,
          resourceKind: 'geometry',
        );
      case 'Material':
        return const _ResolvedKind(
          ComponentPropertyKind.resourceRef,
          resourceKind: 'material',
        );
      case 'Texture':
        return const _ResolvedKind(
          ComponentPropertyKind.resourceRef,
          resourceKind: 'texture',
        );
    }
    if (enums.containsKey(declaredType)) {
      return _enumKind(declaredType, enums, offset);
    }
    _error(
      offset,
      'unknown property type ${declaredType.isEmpty ? '(untyped)' : declaredType}, '
      'field skipped; use a typed property annotation to pin the kind',
    );
    return null;
  }

  List<PropertyConstraint<Object?>> _lowerConstraints(
    String annotationName,
    _Args args,
    int offset,
  ) {
    final constraints = <PropertyConstraint<Object?>>[];
    switch (annotationName) {
      case 'IntProperty':
        final min = _numLit(args.named['min'])?.toInt();
        final max = _numLit(args.named['max'])?.toInt();
        if (min != null || max != null) constraints.add(IntRange(min, max));
      case 'NumberProperty':
        final min = _numLit(args.named['min'])?.toDouble();
        final max = _numLit(args.named['max'])?.toDouble();
        if (min != null || max != null) constraints.add(Range(min, max));
        final softMin = _numLit(args.named['softMin'])?.toDouble();
        final softMax = _numLit(args.named['softMax'])?.toDouble();
        if (softMax != null) {
          // softMax alone is the common authoring shape; the slider floor
          // falls back to the hard minimum, then zero.
          constraints.add(SoftRange(softMin ?? min ?? 0, softMax));
        } else if (softMin != null) {
          _warn(
            offset,
            'softMin without softMax lowers no slider range; add softMax',
          );
        }
        final step = _numLit(args.named['step'])?.toDouble();
        if (step != null) constraints.add(Step(step));
      case 'StringProperty':
        if (_boolLit(args.named['multiline']) ?? false) {
          constraints.add(const Multiline());
        }
        final pattern = _stringLit(args.named['pattern']);
        if (pattern != null) constraints.add(TextPattern(pattern));
      case 'Vec3Property':
        if (_boolLit(args.named['rgbColor']) ?? false) {
          constraints.add(const RgbColor());
        }
        if (_boolLit(args.named['normalized']) ?? false) {
          constraints.add(const Normalized());
        }
      case 'AssetProperty':
        final extensions = _stringListLit(args.named['extensions']);
        if (extensions != null && extensions.isNotEmpty) {
          constraints.add(AssetExtensions(extensions));
        }
      case 'AngleProperty':
        constraints.add(const AngleRadians());
        final min = _numLit(args.named['min'])?.toDouble();
        final max = _numLit(args.named['max'])?.toDouble();
        if (min != null || max != null) constraints.add(Range(min, max));
    }
    final extra = args.named['extra'];
    if (extra is ListLiteral) {
      for (final element in extra.elements) {
        if (element is! Expression) continue;
        final constraint = _constraintFromExpression(element);
        if (constraint == null) {
          _warn(
            element.offset,
            'unrecognized constraint expression ${element.toSource()}',
          );
          continue;
        }
        constraints.add(constraint);
      }
    }
    return constraints;
  }
}

class _ResolvedKind {
  const _ResolvedKind(
    this.kind, {
    this.resourceKind,
    this.options,
    this.enumTypeName,
    this.enumResolved = false,
  });

  final ComponentPropertyKind kind;
  final String? resourceKind;
  final List<String>? options;
  final String? enumTypeName;
  final bool enumResolved;
}

class _Args {
  _Args(ArgumentList? list) {
    if (list == null) return;
    for (final argument in list.arguments) {
      if (argument is NamedExpression) {
        named[argument.name.label.name] = argument.expression;
      } else {
        positional.add(argument);
      }
    }
  }

  final positional = <Expression>[];
  final named = <String, Expression>{};
}

String _annotationName(Annotation annotation) {
  final name = annotation.name;
  return name is PrefixedIdentifier ? name.identifier.name : name.name;
}

String? _docText(AnnotatedNode node) {
  final comment = node.documentationComment;
  if (comment == null) return null;
  final lines = <String>[];
  for (final token in comment.tokens) {
    var text = token.lexeme;
    if (text.startsWith('///')) text = text.substring(3);
    if (text.startsWith(' ')) text = text.substring(1);
    lines.add(text);
  }
  final joined = lines.join('\n').trim();
  return joined.isEmpty ? null : joined;
}

bool _hasZeroArgConstructor(ClassDeclaration declaration) {
  final namePart = declaration.namePart;
  if (namePart is PrimaryConstructorDeclaration) {
    return namePart.formalParameters.parameters.every(
      (parameter) => parameter.isOptional,
    );
  }
  final constructors = declaration.body.members
      .whereType<ConstructorDeclaration>()
      .toList();
  if (constructors.isEmpty) return true;
  for (final constructor in constructors) {
    if (constructor.name != null) continue;
    final parameters = constructor.parameters.parameters;
    if (parameters.every((parameter) => parameter.isOptional)) return true;
  }
  return false;
}

String? _stringLit(Expression? expression) =>
    expression is SimpleStringLiteral ? expression.value : null;

bool? _boolLit(Expression? expression) =>
    expression is BooleanLiteral ? expression.value : null;

num? _numLit(Expression? expression) {
  if (expression is IntegerLiteral) return expression.value;
  if (expression is DoubleLiteral) return expression.value;
  if (expression is PrefixExpression && expression.operator.lexeme == '-') {
    final inner = _numLit(expression.operand);
    return inner == null ? null : -inner;
  }
  return null;
}

List<String>? _stringListLit(Expression? expression) {
  if (expression is! ListLiteral) return null;
  final out = <String>[];
  for (final element in expression.elements) {
    if (element is! SimpleStringLiteral) return null;
    out.add(element.value);
  }
  return out;
}

/// An invocation split into type name, optional named constructor, and args,
/// covering both `Vector3(...)` (a [MethodInvocation] in unresolved ASTs)
/// and `const Vector3(...)` (an [InstanceCreationExpression]).
(String, String?, ArgumentList)? _splitInvocation(Expression expression) {
  if (expression is InstanceCreationExpression) {
    final type = expression.constructorName.type;
    return (
      type.name.lexeme,
      expression.constructorName.name?.name,
      expression.argumentList,
    );
  }
  if (expression is MethodInvocation) {
    final target = expression.target;
    if (target == null) {
      return (expression.methodName.name, null, expression.argumentList);
    }
    if (target is SimpleIdentifier) {
      return (target.name, expression.methodName.name, expression.argumentList);
    }
  }
  return null;
}

List<double>? _numArgs(ArgumentList args, int count) {
  if (args.arguments.length != count) return null;
  final out = <double>[];
  for (final argument in args.arguments) {
    final value = _numLit(argument);
    if (value == null) return null;
    out.add(value.toDouble());
  }
  return out;
}

PropertyConstraint<Object?>? _constraintFromExpression(Expression expression) {
  final split = _splitInvocation(expression);
  if (split == null) return null;
  final (typeName, constructorName, args) = split;
  final positional = [
    for (final argument in args.arguments)
      if (argument is! NamedExpression) argument,
  ];
  final named = <String, Expression>{
    for (final argument in args.arguments)
      if (argument is NamedExpression)
        argument.name.label.name: argument.expression,
  };
  double? positionalNum(int index) =>
      index < positional.length ? _numLit(positional[index])?.toDouble() : null;
  switch (typeName) {
    case 'Range':
      if (constructorName == 'nonNegative') return const Range.nonNegative();
      return Range(positionalNum(0), positionalNum(1));
    case 'SoftRange':
      final min = positionalNum(0);
      final max = positionalNum(1);
      if (min == null || max == null) return null;
      return SoftRange(min, max);
    case 'IntRange':
      return IntRange(positionalNum(0)?.toInt(), positionalNum(1)?.toInt());
    case 'Step':
      final step = positionalNum(0);
      return step == null ? null : Step(step);
    case 'PowerOfTwo':
      return PowerOfTwo(
        min: _numLit(named['min'])?.toInt() ?? 1,
        max: _numLit(named['max'])?.toInt(),
      );
    case 'AngleRadians':
      return const AngleRadians();
    case 'RgbColor':
      return const RgbColor();
    case 'Normalized':
      return const Normalized();
    case 'LayerMask32':
      return const LayerMask32();
    case 'Multiline':
      return const Multiline();
    case 'TextPattern':
      final pattern = positional.isEmpty ? null : _stringLit(positional[0]);
      return pattern == null ? null : TextPattern(pattern);
    case 'AssetExtensions':
      final extensions = positional.isEmpty
          ? null
          : _stringListLit(positional[0]);
      return extensions == null ? null : AssetExtensions(extensions);
    case 'MinCount':
      final count = positionalNum(0)?.toInt();
      return count == null ? null : MinCount(count);
    case 'SortedDescending':
      final field = positional.isEmpty ? null : _stringLit(positional[0]);
      return field == null ? null : SortedDescending(field);
  }
  return null;
}

List<double>? _numberListLit(Expression? expression) {
  if (expression is! ListLiteral) return null;
  final out = <double>[];
  for (final element in expression.elements) {
    if (element is! Expression) return null;
    final value = _numLit(element);
    if (value == null) return null;
    out.add(value.toDouble());
  }
  return out;
}

GizmoScalar? _gizmoScalarFromExpression(Expression? expression) {
  if (expression == null) return null;
  final literal = _numLit(expression);
  if (literal != null) return GizmoScalar(literal.toDouble());
  final split = _splitInvocation(expression);
  if (split == null) return null;
  final (typeName, constructorName, args) = split;
  if (typeName != 'GizmoScalar') return null;
  final parsed = _Args(args);
  if (constructorName == null) {
    final value = parsed.positional.isEmpty
        ? null
        : _numLit(parsed.positional.first);
    return value == null ? null : GizmoScalar(value.toDouble());
  }
  if (constructorName == 'bind') {
    final path = parsed.positional.isEmpty
        ? null
        : _stringLit(parsed.positional.first);
    if (path == null) return null;
    return GizmoScalar.bind(
      path,
      scale: _numLit(parsed.named['scale'])?.toDouble() ?? 1,
    );
  }
  return null;
}

GizmoColor? _gizmoColorFromExpression(Expression? expression) {
  if (expression == null) return null;
  final split = _splitInvocation(expression);
  if (split == null) return null;
  final (typeName, constructorName, args) = split;
  if (typeName != 'GizmoColor') return null;
  final parsed = _Args(args);
  if (constructorName == 'bind') {
    final path = parsed.positional.isEmpty
        ? null
        : _stringLit(parsed.positional.first);
    return path == null ? null : GizmoColor.bind(path);
  }
  if (constructorName != null) return null;
  final channels = <double>[];
  for (final argument in parsed.positional) {
    final value = _numLit(argument);
    if (value == null) return null;
    channels.add(value.toDouble());
  }
  if (channels.length < 3) return null;
  return GizmoColor(
    channels[0],
    channels[1],
    channels[2],
    channels.length > 3 ? channels[3] : 1,
  );
}

GizmoCondition? _gizmoConditionFromExpression(Expression? expression) {
  if (expression == null) return null;
  final split = _splitInvocation(expression);
  if (split == null) return null;
  final (typeName, constructorName, args) = split;
  if (typeName != 'GizmoCondition' || constructorName != null) return null;
  final parsed = _Args(args);
  if (parsed.positional.length != 2) return null;
  final path = _stringLit(parsed.positional[0]);
  final equals = _stringLit(parsed.positional[1]);
  if (path == null || equals == null) return null;
  return GizmoCondition(path, equals);
}

GizmoVisibility _gizmoVisibilityFromExpression(Expression? expression) {
  if (expression is PrefixedIdentifier &&
      expression.prefix.name == 'GizmoVisibility') {
    return GizmoVisibility.values.asNameMap()[expression.identifier.name] ??
        GizmoVisibility.always;
  }
  return GizmoVisibility.always;
}

GizmoPrimitive? _gizmoPrimitiveFromExpression(Expression expression) {
  final split = _splitInvocation(expression);
  if (split == null) return null;
  final (typeName, constructorName, args) = split;
  if (constructorName != null) return null;
  final parsed = _Args(args);
  final visibility = _gizmoVisibilityFromExpression(parsed.named['visibility']);
  final color = _gizmoColorFromExpression(parsed.named['color']);
  final xray = _boolLit(parsed.named['xray']) ?? true;
  final when = _gizmoConditionFromExpression(parsed.named['when']);
  GizmoScalar? scalar(String name) =>
      _gizmoScalarFromExpression(parsed.named[name]);
  List<double>? numbers(String name) => _numberListLit(parsed.named[name]);
  switch (typeName) {
    case 'GizmoIcon':
      return GizmoIcon(
        glyph: _stringLit(parsed.named['glyph']),
        size: _numLit(parsed.named['size'])?.toDouble() ?? 28,
        color: color,
        when: when,
      );
    case 'GizmoArrow':
      return GizmoArrow(
        axis: numbers('axis') ?? const [0, 0, 1],
        axisBind: _stringLit(parsed.named['axisBind']),
        length: scalar('length') ?? const GizmoScalar(1),
        visibility: visibility,
        color: color,
        xray: xray,
        when: when,
      );
    case 'GizmoLines':
      final points = parsed.positional.isEmpty
          ? null
          : _numberListLit(parsed.positional.first);
      if (points == null) return null;
      return GizmoLines(
        points,
        visibility: visibility,
        color: color,
        xray: xray,
        when: when,
      );
    case 'GizmoWireSphere':
      final radius = scalar('radius');
      if (radius == null) return null;
      return GizmoWireSphere(
        radius: radius,
        center: numbers('center') ?? const [0, 0, 0],
        inflate: scalar('inflate') ?? const GizmoScalar(0),
        visibility: visibility,
        color: color,
        xray: xray,
        when: when,
      );
    case 'GizmoWireBox':
      return GizmoWireBox(
        halfExtents: numbers('halfExtents'),
        halfExtentsBind: _stringLit(parsed.named['halfExtentsBind']),
        center: numbers('center') ?? const [0, 0, 0],
        inflate: scalar('inflate') ?? const GizmoScalar(0),
        visibility: visibility,
        color: color,
        xray: xray,
        when: when,
      );
    case 'GizmoWireRect':
      final width = scalar('width');
      final height = scalar('height');
      if (width == null || height == null) return null;
      return GizmoWireRect(
        width: width,
        height: height,
        axis: numbers('axis') ?? const [0, 0, 1],
        visibility: visibility,
        color: color,
        xray: xray,
        when: when,
      );
    case 'GizmoWireCircle':
      final radius = scalar('radius');
      if (radius == null) return null;
      return GizmoWireCircle(
        radius: radius,
        axis: numbers('axis') ?? const [0, 0, 1],
        visibility: visibility,
        color: color,
        xray: xray,
        when: when,
      );
    case 'GizmoWireCone':
      final angle = scalar('angle');
      final range = scalar('range');
      if (angle == null || range == null) return null;
      return GizmoWireCone(
        angle: angle,
        range: range,
        axis: numbers('axis') ?? const [0, 0, 1],
        axisBind: _stringLit(parsed.named['axisBind']),
        visibility: visibility,
        color: color,
        xray: xray,
        when: when,
      );
    case 'GizmoWireCapsule':
      final radius = scalar('radius');
      final halfHeight = scalar('halfHeight');
      if (radius == null || halfHeight == null) return null;
      return GizmoWireCapsule(
        radius: radius,
        halfHeight: halfHeight,
        axis: numbers('axis') ?? const [0, 1, 0],
        visibility: visibility,
        color: color,
        xray: xray,
        when: when,
      );
    case 'GizmoWireCylinder':
      final radius = scalar('radius');
      final halfHeight = scalar('halfHeight');
      if (radius == null || halfHeight == null) return null;
      return GizmoWireCylinder(
        radius: radius,
        halfHeight: halfHeight,
        axis: numbers('axis') ?? const [0, 1, 0],
        visibility: visibility,
        color: color,
        xray: xray,
        when: when,
      );
    case 'GizmoFrustum':
      final fovY = scalar('fovY');
      final near = scalar('near');
      final far = scalar('far');
      if (fovY == null || near == null || far == null) return null;
      return GizmoFrustum(
        fovY: fovY,
        near: near,
        far: far,
        aspect: scalar('aspect'),
        visibility: visibility,
        color: color,
        xray: xray,
        when: when,
      );
  }
  return null;
}

PropertyValue? _defaultFromInitializer(
  Expression initializer,
  ComponentPropertyKind kind,
  String? enumTypeName,
) {
  switch (kind) {
    case ComponentPropertyKind.boolean:
      final value = _boolLit(initializer);
      return value == null ? null : BoolValue(value);
    case ComponentPropertyKind.integer:
      final value = _numLit(initializer);
      return value is int ? IntValue(value) : null;
    case ComponentPropertyKind.number:
      final value = _numLit(initializer);
      return value == null ? null : DoubleValue(value.toDouble());
    case ComponentPropertyKind.string:
    case ComponentPropertyKind.assetRef:
      final text = _stringLit(initializer);
      if (text != null) return StringValue(text);
      // An enum default: `EnumName.value` parses as a prefixed identifier.
      if (initializer is PrefixedIdentifier &&
          initializer.prefix.name == enumTypeName) {
        return StringValue(initializer.identifier.name);
      }
      return null;
    case ComponentPropertyKind.vec2:
      final values = _vectorDefault(initializer, 'Vector2', 2);
      return values == null ? null : Vec2Value(Vector2(values[0], values[1]));
    case ComponentPropertyKind.vec3:
      final values = _vectorDefault(initializer, 'Vector3', 3);
      return values == null
          ? null
          : Vec3Value(Vector3(values[0], values[1], values[2]));
    case ComponentPropertyKind.vec4:
      final values = _vectorDefault(initializer, 'Vector4', 4);
      return values == null
          ? null
          : Vec4Value(Vector4(values[0], values[1], values[2], values[3]));
    case ComponentPropertyKind.quaternion:
      final split = _splitInvocation(initializer);
      if (split == null) return null;
      final (typeName, constructorName, args) = split;
      if (typeName != 'Quaternion' || constructorName != null) return null;
      final values = _numArgs(args, 4);
      return values == null
          ? null
          : QuaternionValue(
              Quaternion(values[0], values[1], values[2], values[3]),
            );
    case ComponentPropertyKind.color:
      return _colorDefault(initializer);
    default:
      return null;
  }
}

List<double>? _vectorDefault(
  Expression initializer,
  String typeName,
  int arity,
) {
  final split = _splitInvocation(initializer);
  if (split == null) return null;
  final (name, constructorName, args) = split;
  if (name != typeName) return null;
  if (constructorName == null) return _numArgs(args, arity);
  if (constructorName == 'zero' && args.arguments.isEmpty) {
    return List.filled(arity, 0.0);
  }
  if (constructorName == 'all') {
    final values = _numArgs(args, 1);
    return values == null ? null : List.filled(arity, values[0]);
  }
  return null;
}

PropertyValue? _colorDefault(Expression initializer) {
  final split = _splitInvocation(initializer);
  if (split == null) return null;
  final (typeName, constructorName, args) = split;
  if (typeName != 'Color' || constructorName != null) return null;
  if (args.arguments.length != 1) return null;
  final argument = args.arguments[0];
  if (argument is! IntegerLiteral) return null;
  final argb = argument.value;
  if (argb == null) return null;
  // TODO(color-space): the hex literal's channels are stored as-is divided
  // by 255; whether an ARGB literal is sRGB or linear is not yet modeled.
  final a = ((argb >> 24) & 0xff) / 255.0;
  final r = ((argb >> 16) & 0xff) / 255.0;
  final g = ((argb >> 8) & 0xff) / 255.0;
  final b = (argb & 0xff) / 255.0;
  return ColorValue(r, g, b, a);
}
