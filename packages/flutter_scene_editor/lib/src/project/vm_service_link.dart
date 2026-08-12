/// A minimal JSON-RPC 2.0 client over the VM Service websocket, just enough
/// to discover isolates and invoke flutter_scene's debug service extensions.
/// Protocol per the Dart VM Service spec (JSON-RPC 2.0 over a websocket).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Injectable websocket opener, so tests drive the protocol with a fake.
typedef VmSocketConnector = Future<VmServiceSocket> Function(String wsUri);

/// The duplex text channel a [VmServiceLink] speaks JSON-RPC over.
abstract interface class VmServiceSocket {
  Stream<dynamic> get messages;
  void send(String text);
  Future<void> close();
}

class _WebSocketVmSocket implements VmServiceSocket {
  _WebSocketVmSocket(this._socket);
  final WebSocket _socket;

  @override
  Stream<dynamic> get messages => _socket;
  @override
  void send(String text) => _socket.add(text);
  @override
  Future<void> close() => _socket.close();
}

Future<VmServiceSocket> _connectWebSocket(String wsUri) async =>
    _WebSocketVmSocket(await WebSocket.connect(wsUri));

/// One live VM Service connection. Create with [connect]; [dispose] when the
/// app session ends. Extension calls re-discover isolates each time, so the
/// link survives hot restarts (which replace isolate ids).
class VmServiceLink {
  VmServiceLink._(this._socket) {
    _subscription = _socket.messages.listen(
      _onMessage,
      onError: (Object _) => _failAll('the VM service connection errored'),
      onDone: () => _failAll('the VM service connection closed'),
    );
  }

  static Future<VmServiceLink> connect(
    String wsUri, {
    VmSocketConnector? connector,
  }) async => VmServiceLink._(await (connector ?? _connectWebSocket)(wsUri));

  final VmServiceSocket _socket;
  late final StreamSubscription<dynamic> _subscription;
  int _requestId = 0;
  final Map<int, Completer<Map<String, Object?>>> _pending = {};
  bool _disposed = false;

  void _onMessage(dynamic message) {
    if (message is! String) return;
    final Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    final id = decoded['id'];
    final key = id is int ? id : (id is String ? int.tryParse(id) : null);
    if (key == null) return;
    _pending.remove(key)?.complete(decoded.cast<String, Object?>());
  }

  void _failAll(String reason) {
    for (final pending in _pending.values) {
      if (!pending.isCompleted) {
        pending.complete({
          'error': {'message': reason},
        });
      }
    }
    _pending.clear();
  }

  /// Sends one JSON-RPC request; the response map carries `result` or
  /// `error`.
  Future<Map<String, Object?>> request(
    String method, [
    Map<String, Object?> params = const {},
  ]) {
    if (_disposed) {
      return Future.value({
        'error': {'message': 'the VM service link is disposed'},
      });
    }
    final id = ++_requestId;
    final completer = Completer<Map<String, Object?>>();
    _pending[id] = completer;
    _socket.send(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return completer.future;
  }

  /// Invokes service extension [method] on the first isolate that registered
  /// it, passing [args]. Returns the extension's result map, or null with
  /// [onError] told why (no isolate has it, or the call failed).
  Future<Map<String, Object?>?> callExtension(
    String method, {
    Map<String, Object?> args = const {},
    void Function(String message)? onError,
  }) async {
    final vm = await request('getVM');
    final isolates = ((vm['result'] as Map?)?['isolates'] as List?) ?? const [];
    for (final ref in isolates) {
      if (ref is! Map) continue;
      final isolateId = ref['id'];
      if (isolateId is! String) continue;
      final isolate = await request('getIsolate', {'isolateId': isolateId});
      final rpcs =
          ((isolate['result'] as Map?)?['extensionRPCs'] as List?) ?? const [];
      if (!rpcs.contains(method)) continue;
      final response = await request(method, {'isolateId': isolateId, ...args});
      final error = response['error'];
      if (error != null) {
        onError?.call(error is Map ? '${error['message'] ?? error}' : '$error');
        return null;
      }
      return (response['result'] as Map?)?.cast<String, Object?>();
    }
    onError?.call('no isolate registered $method');
    return null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _failAll('the VM service link is disposed');
    await _subscription.cancel();
    await _socket.close();
  }
}
