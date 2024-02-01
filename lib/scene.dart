import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import 'camera.dart';

/// Responsible for rendering a given SceneNode using a camera transform.
class SceneRenderBox extends RenderBox {
  SceneRenderBox(
      {ui.SceneNode? node, Camera? camera, bool alwaysRepaint = false})
      : camera_ = camera {
    this.node = node;
    this.alwaysRepaint = alwaysRepaint;
  }

  ui.SceneShader? _shader;
  ui.SceneNode? _node;

  set node(ui.SceneNode? node) {
    _shader = node?.sceneShader();
    _node = node;

    markNeedsPaint();
  }

  Camera? camera_;
  set camera(Camera? camera) {
    camera_ = camera;

    markNeedsPaint();
  }

  Ticker? _ticker;
  Size _size = Size.zero;

  set alwaysRepaint(bool alwaysRepaint) {
    if (alwaysRepaint) {
      _ticker = Ticker((_) {
        if (debugDisposed != null && !(debugDisposed!)) markNeedsPaint();
      });
      markNeedsPaint();
    } else {
      _ticker = null;
    }
  }

  @override
  void attach(covariant PipelineOwner owner) {
    super.attach(owner);
    _ticker?.start();
  }

  @override
  void detach() {
    super.detach();
    _ticker?.stop();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    // Expand to take up as much space as allowed.
    _size = constraints.biggest;
    return constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_shader == null) {
      return;
    }

    Camera camera = camera_ ?? Camera();
    _shader!
        .setCameraTransform(camera.computeTransform(size.aspectRatio).storage);

    context.canvas.drawRect(
        Rect.fromLTWH(offset.dx, offset.dy, _size.width, _size.height),
        Paint()..shader = _shader);
  }

  @override
  void dispose() {
    _ticker?.stop();
    super.dispose();
  }
}

/// Draws a given ui.SceneNode using a given camera.
/// This is the lowest level widget for drawing an 3D scene.
class SceneBoxUI extends LeafRenderObjectWidget {
  const SceneBoxUI(
      {Key? key, this.root, this.camera, this.alwaysRepaint = false})
      : super(key: key);
  final ui.SceneNode? root;
  final Camera? camera;
  final bool alwaysRepaint;

  @override
  RenderBox createRenderObject(BuildContext context) {
    return SceneRenderBox(
        node: root, camera: camera, alwaysRepaint: alwaysRepaint);
  }

  @override
  void updateRenderObject(BuildContext context, SceneRenderBox renderObject) {
    renderObject.node = root;
    renderObject.camera = camera;
    renderObject.alwaysRepaint = alwaysRepaint;
    super.updateRenderObject(context, renderObject);
  }
}

/// An immutable Scene node for conveniently building during widget tree construction.
class Node {
  static Node asset(String assetUri, {List<String>? animations}) {
    ui.SceneNodeValue node = ui.SceneNode.fromAsset(assetUri);

    Node result = Node._(node);

    if (animations != null) {
      for (var animation in animations) {
        result.playAnimation(animation);
      }
    }
    return result;
  }

  static Node transform({Matrix4? transform, List<Node>? children}) {
    Matrix4 t = transform ?? Matrix4.identity();
    ui.SceneNodeValue node = ui.SceneNode.fromTransform(t.storage);
    return Node._(node, children: children);
  }

  factory Node({Vector3? position, List<Node>? children}) {
    Matrix4 transform = Matrix4.identity();
    if (position != null) {
      transform *= Matrix4.translation(position);
    }
    return Node.transform(transform: transform, children: children);
  }

  Node._(node, {List<Node>? children})
      : _node = node,
        _children = children ?? [];

  late final ui.SceneNodeValue _node;
  final List<Node> _children;

  bool _connected = false;

  /// Walk the immutable tree and form the internal scene graph by parenting the
  /// ui.SceneNodes to each other.
  void connectChildren() {
    if (!_node.isComplete || _connected) return;
    _connected = true;

    for (var child in _children) {
      child._node.whenComplete((ui.SceneNode childNode) {
        _node.value!.addChild(childNode);
        child.connectChildren();
      });
    }
  }

  void onLoadingComplete(Function(ui.SceneNode node) callback) {
    _node.whenComplete((ui.SceneNode result) {
      callback(result);
    });
  }

  void playAnimation(String name) {
    setAnimationState(name, true, true, 1.0, 1.0);
  }

  void setAnimationState(
      String name, bool playing, bool loop, double weight, double timescale) {
    onLoadingComplete((node) =>
        {node.setAnimationState(name, playing, loop, weight, timescale)});
  }
}

Node AssetNode(String assetUri) {
  return Node.asset(assetUri);
}

class SceneBox extends StatefulWidget {
  const SceneBox(
      {super.key, required this.root, this.camera, this.alwaysRepaint = true});

  final Node root;
  final Camera? camera;
  final bool alwaysRepaint;

  @override
  State<StatefulWidget> createState() => _SceneBox();
}

class _SceneBox extends State<SceneBox> {
  @override
  Widget build(BuildContext context) {
    if (!widget.root._node.isComplete) {
      widget.root.onLoadingComplete((node) {
        // Kick the state to trigger a rebuild of the widget tree as soon as the
        // node is ready.
        if (mounted) setState(() {});
      });
      return const SizedBox.expand();
    }

    widget.root.connectChildren();

    return SceneBoxUI(
        root: widget.root._node.value,
        camera: widget.camera,
        alwaysRepaint: widget.alwaysRepaint);
  }
}

class Scene extends StatefulWidget {
  const Scene({super.key, required this.node});

  final Node node;

  @override
  State<Scene> createState() => _SceneState();
}

class _SceneState extends State<Scene> {
  Vector3 _direction = Vector3(0, 0, -1);
  double _distance = 7.5;

  double _startScaleDistance = 1;

  @override
  Widget build(BuildContext context) {
    Vector3 cameraPosition = Vector3(0, 1.65, 0) + _direction * _distance;

    return GestureDetector(
      onScaleStart: (details) {
        _startScaleDistance = _distance;
      },
      onScaleEnd: (details) {},
      onScaleUpdate: (details) {
        setState(() {
          _distance = _startScaleDistance / details.scale;

          double panDistance = details.focalPointDelta.distance;
          if (panDistance < 1e-3) {
            return;
          }

          // TODO(bdero): Compute this transform more efficiently.
          Matrix4 viewToWorldTransform = Matrix4.inverted(
              matrix4LookAt(Vector3.zero(), -_direction, Vector3(0, 1, 0)));

          Vector3 screenSpacePanDirection = Vector3(
                  details.focalPointDelta.dx, -details.focalPointDelta.dy, 0)
              .normalized();
          Vector3 screenSpacePanAxis =
              screenSpacePanDirection.cross(Vector3(0, 0, 1)).normalized();
          Vector3 panAxis = viewToWorldTransform * screenSpacePanAxis;
          Vector3 newDirection =
              Quaternion.axisAngle(panAxis, panDistance / 100)
                  .rotate(_direction)
                  .normalized();
          if (newDirection.length > 1e-1) {
            _direction = newDirection;
          }
        });
      },
      behavior: HitTestBehavior.translucent,
      child: SceneBox(
        root: Node(children: [
          widget.node,
          Node(
              position: cameraPosition,
              children: [Node.asset("models/sky_sphere.glb")])
        ]),
        camera: Camera(position: cameraPosition, target: Vector3(0, 1.75, 0)),
      ),
    );
  }
}
