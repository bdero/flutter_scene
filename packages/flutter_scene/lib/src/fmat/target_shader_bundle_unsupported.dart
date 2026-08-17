enum TargetShaderBundleAssetMode {
  generatedTree,
  dataAssetsRequired,

  @Deprecated(
    'Removed in 0.21.0. Use generatedTree, then run `dart run flutter_scene:init`.',
  )
  legacyOnly,
  @Deprecated(
    'Removed in 0.21.0. Use generatedTree, then run `dart run flutter_scene:init`.',
  )
  dataAssetsIfAvailable,
}

Never buildTargetShaderBundleJson({
  required Object buildInput,
  required Object buildOutput,
  required String manifestFileName,
  List<Uri> includeDirectories = const [],
  TargetShaderBundleAssetMode assetMode =
      TargetShaderBundleAssetMode.generatedTree,
  String? dataAssetName,
  int? glesLanguageVersion,
  bool copyToGeneratedTree = true,
  bool pruneGeneratedTree = true,
  String? owner,
  String? stamp,
  String? fileVariant,
}) => throw UnsupportedError(
  'buildTargetShaderBundleJson runs at build time on native hosts only.',
);
