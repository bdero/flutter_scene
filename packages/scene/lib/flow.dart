/// Visual scripting: a graph of nodes wired together, and the runtime that
/// walks it.
///
/// Two kinds of wire. An **exec** wire says what happens next, pushing forward
/// from an event; a **data** wire says where a value comes from, pulled
/// backward by whoever needs it. Every node type is written against that and
/// nothing else.
///
/// ```dart
/// final registry = standardFlowRegistry();
/// final graph = readFlowGraph(source);
/// final context = FlowContext(graph: graph, host: myHost);
/// FlowInterpreter(registry).fire(context, onTick.id);
/// ```
///
/// The graph and the standard node types are engine agnostic and pure Dart:
/// they reach the world only through a [FlowHost], which is what lets the
/// same graph run in a test with a stub and in a scene with a renderer. The
/// scene-facing node types are registered by `package:flutter_scene/flow.dart`.
///
/// Import this only when a build needs scripting; the core
/// `package:scene/scene.dart` does not carry it.
library;

export 'src/flow/blueprint_source.dart'
    show
        BlueprintDiagnostic,
        BlueprintParseResult,
        blueprintEquivalent,
        blueprintSourceVersion,
        parseBlueprint,
        printBlueprint;
export 'src/flow/flow_graph.dart'
    show FlowGraph, FlowLink, FlowNodeSpec, FlowPin, FlowType, FlowVariable;
export 'src/flow/flow_json.dart'
    show
        decodeFlowGraph,
        encodeFlowGraph,
        flowGraphVersion,
        readFlowGraph,
        writeFlowGraph;
export 'src/flow/flow_library.dart'
    show
        addNumbers,
        addVectors,
        andGate,
        branch,
        breakVector,
        clampNumber,
        delay,
        divideNumbers,
        doOnce,
        gate,
        getVariable,
        lerpNumber,
        makeVector,
        multiplyNumbers,
        notGate,
        numberGreaterThan,
        numberLessThan,
        numberNearlyEqual,
        onSignal,
        onStart,
        onTick,
        orGate,
        printValue,
        randomNumber,
        scaleVector,
        sequence,
        setVariable,
        sineWave,
        standardFlowNodes,
        standardFlowRegistry,
        subtractNumbers;
export 'src/flow/flow_trace.dart' show FlowPinRef, FlowTrace, FlowTraceStep;
export 'src/flow/flow_runtime.dart'
    show
        FlowContext,
        FlowHost,
        FlowInterpreter,
        FlowNodeType,
        FlowRegistry,
        FlowResult,
        NullFlowHost,
        flowBool,
        flowInteger,
        flowNumber,
        flowString,
        flowVector;
