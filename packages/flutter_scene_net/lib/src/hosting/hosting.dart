/// In-app hosting, a room plus a WebSocket server inside the game process,
/// so desktop and mobile builds can host without a separate server binary.
/// Unavailable on the web ([SceneHost.isSupported] is false there); browsers
/// cannot listen for connections.
library;

export 'hosting_stub.dart'
    if (dart.library.io) 'hosting_io.dart'
    show SceneHost;
