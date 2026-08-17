enum TargetShaderBundleAssetMode { generatedTree, dataAssetsRequired }

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
