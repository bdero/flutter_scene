/// Visual scripting for flutter_scene: a graph of nodes wired together,
/// running on a scene node.
///
/// The graph, the runtime, and the node types that need no renderer live in
/// `package:scene/flow.dart`, which this re-exports alongside the pieces that
/// do: the node types that read and write a scene, the host that gives them
/// somewhere to land, and the component that ticks a graph.
///
/// ```dart
/// final graph = readFlowGraph(await rootBundle.loadString('assets/door.flow'));
/// door.addComponent(FlowComponent(graph: graph));
/// ```
///
/// Import this only when a build needs scripting; the core
/// `package:flutter_scene/scene.dart` does not carry it.
library;

export 'package:scene/flow.dart';

export 'src/flow/flow_component.dart' show FlowComponent;
export 'src/flow/scene_flow_host.dart' show SceneFlowHost;
export 'src/flow/scene_flow_nodes.dart'
    show
        animatorState,
        animatorTrigger,
        callAction,
        destroyNode,
        getPosition,
        getScale,
        lookAtPoint,
        playAnimation,
        sceneFlowNodes,
        sceneFlowRegistry,
        setAnimatorFlag,
        setAnimatorNumber,
        setPosition,
        setScale,
        setVisible,
        stopAnimation,
        translateNode;
