import 'dart:io';

/// Ends the process once a recorded act has played.
void quitDepthDemo() => exit(0);

/// The act a recording run asks for through the `DEPTH_DEMO` environment
/// variable, so one build can record every act.
String depthDemoActFromEnvironment() =>
    Platform.environment['DEPTH_DEMO'] ?? '';

/// Whether a recording run should log depth conflict probes of both halves,
/// from the `DEPTH_DEMO_PROBE` environment variable.
bool depthDemoProbeFromEnvironment() =>
    Platform.environment['DEPTH_DEMO_PROBE'] == '1';

/// Whether a recording run should draw the depth conflict overlay over both
/// halves, from the `DEPTH_DEMO_OVERLAY` environment variable.
bool depthDemoOverlayFromEnvironment() =>
    Platform.environment['DEPTH_DEMO_OVERLAY'] == '1';
