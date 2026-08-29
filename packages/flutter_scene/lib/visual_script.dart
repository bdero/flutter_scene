/// Visual scripting for flutter_scene: a graph of nodes wired together,
/// running on a scene node.
///
/// The graph, the runtime, and the node types that need no renderer live in
/// `package:scene/visual_script.dart`, which this re-exports alongside the pieces that
/// do: the node types that read and write a scene, the host that gives them
/// somewhere to land, and the component that ticks a graph.
///
/// ```dart
/// final graph = readVisualScript(await rootBundle.loadString('assets/door.flow'));
/// door.addComponent(VisualScriptComponent(graph: graph));
/// ```
///
/// Import this only when a build needs scripting; the core
/// `package:flutter_scene/scene.dart` does not carry it.
library;

export 'package:scene/visual_script.dart';

export 'src/visual_script/visual_script_component.dart'
    show VisualScriptComponent;
export 'src/visual_script/scene_visual_script_host.dart'
    show SceneVisualScriptHost;
export 'src/visual_script/scene_visual_script_nodes.dart'
    show
        animatorState,
        animatorTrigger,
        callAction,
        destroyNode,
        getPosition,
        getScale,
        lookAtPoint,
        playAnimation,
        sceneVisualScriptNodes,
        sceneVisualScriptRegistry,
        setAnimatorFlag,
        setAnimatorNumber,
        setPosition,
        setScale,
        setTimeOfDay,
        setVisible,
        setWeather,
        stopAnimation,
        translateNode;
