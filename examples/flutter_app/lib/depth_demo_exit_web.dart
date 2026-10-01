/// A browser tab has no process to end, so a recorded act just stops.
void quitDepthDemo() {}

/// The web has no process environment to read an act from.
String depthDemoActFromEnvironment() => '';

/// The web has no process environment to read the probe switch from.
bool depthDemoProbeFromEnvironment() => false;

/// The web has no process environment to read the overlay switch from.
bool depthDemoOverlayFromEnvironment() => false;
