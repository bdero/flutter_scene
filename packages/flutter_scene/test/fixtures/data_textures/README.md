Shader bundle for `data_texture_webgl_browser_test.dart`, built from the shaders beside it with the SDK cache's `impellerc` and embedded as base64 (browser tests cannot run `impellerc` or read files):

```sh
impellerc --sl=data_textures.shaderbundle \
  --shader-bundle="$(cat manifest.json)" --gles-language-version=300 --include=.
base64 -i data_textures.shaderbundle  # into data_textures_bundle.dart
```
