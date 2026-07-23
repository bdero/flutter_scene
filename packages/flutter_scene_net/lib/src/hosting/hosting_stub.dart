import 'package:dashwire/dashwire.dart';
import 'package:dashwire_replication/dashwire_replication.dart';

/// Web stub; hosting requires dart:io. See hosting_io.dart for the API.
final class SceneHost {
  SceneHost._();

  static bool get isSupported => false;

  static Future<SceneHost> start({required Room room, int port = 0}) =>
      throw UnsupportedError('in-app hosting requires dart:io');

  Room get room => throw UnsupportedError('in-app hosting requires dart:io');
  int get port => throw UnsupportedError('in-app hosting requires dart:io');
  List<String> get addresses =>
      throw UnsupportedError('in-app hosting requires dart:io');

  Future<WireConnection> connectLocal() =>
      throw UnsupportedError('in-app hosting requires dart:io');

  Future<void> stop() =>
      throw UnsupportedError('in-app hosting requires dart:io');
}
