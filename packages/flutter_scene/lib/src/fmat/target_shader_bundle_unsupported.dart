enum TargetShaderBundleAssetMode {
  legacyOnly,
  dataAssetsIfAvailable,
  dataAssetsRequired,
}

Never buildTargetShaderBundleJson({
  required Object buildInput,
  required Object buildOutput,
  required String manifestFileName,
  List<Uri> includeDirectories = const [],
  TargetShaderBundleAssetMode assetMode =
      TargetShaderBundleAssetMode.legacyOnly,
  String? dataAssetName,
  int? glesLanguageVersion,
}) => throw UnsupportedError(
  'buildTargetShaderBundleJson runs at build time on native hosts only.',
);
