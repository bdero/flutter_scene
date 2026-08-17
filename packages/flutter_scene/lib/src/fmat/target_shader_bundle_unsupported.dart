enum TargetShaderBundleAssetMode {
  generatedTree,
  dataAssetsIfAvailable,
  dataAssetsRequired,
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
  String? owner,
}) => throw UnsupportedError(
  'buildTargetShaderBundleJson runs at build time on native hosts only.',
);
