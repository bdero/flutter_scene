import 'package:flutter_gpu/gpu.dart' as gpu;

base class Environment {
  Environment({this.texture, this.intensity = 1.0});

  gpu.Texture? texture;
  double intensity;
}
