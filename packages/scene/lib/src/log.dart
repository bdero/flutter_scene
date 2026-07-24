/// Sink for scene's diagnostic warnings (bad override paths, cyclic prefab
/// references). Defaults to [print]; hosts may redirect it (a Flutter app
/// into debugPrint, a server into its logger).
// ignore: avoid_print
void Function(String message) sceneLog = print;
