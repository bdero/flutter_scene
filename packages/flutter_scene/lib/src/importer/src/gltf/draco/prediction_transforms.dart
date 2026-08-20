// Prediction scheme decoding transforms. See the Draco Bitstream
// Specification, "Prediction Wrap Transform" and "Prediction Normal
// Transform" (https://google.github.io/draco/spec/).

import 'dart:typed_data';

import 'attributes.dart';
import 'constants.dart';
import 'decoder_buffer.dart';

/// Converts transformed corrections plus predictions back to original values.
abstract class PredictionTransform {
  int get type;

  /// Whether corrections are stored unsigned (no zigzag decode needed).
  bool get areCorrectionsPositive;

  void init(int numComponents) {}

  void decodeTransformData(DecoderBuffer buffer);

  void computeOriginalValue(
    Int32List predicted,
    int predictedOffset,
    Int32List corrections,
    int correctionsOffset,
    Int32List output,
    int outputOffset,
  );
}

/// Wrap transform, corrections wrap the result back into the value range.
class WrapTransform extends PredictionTransform {
  int _numComponents = 0;
  int _minValue = 0;
  int _maxValue = 0;
  int _maxDif = 0;

  @override
  int get type => DracoPredictionTransform.wrap;

  @override
  bool get areCorrectionsPositive => false;

  @override
  void init(int numComponents) {
    _numComponents = numComponents;
  }

  @override
  void decodeTransformData(DecoderBuffer buffer) {
    _minValue = buffer.decodeInt32();
    _maxValue = buffer.decodeInt32();
    if (_minValue > _maxValue) {
      throw dracoError('invalid wrap transform bounds');
    }
    final dif = _maxValue - _minValue;
    if (dif < 0 || dif >= 0x7FFFFFFF) {
      throw dracoError('invalid wrap transform bounds');
    }
    _maxDif = 1 + dif;
  }

  @override
  void computeOriginalValue(
    Int32List predicted,
    int predictedOffset,
    Int32List corrections,
    int correctionsOffset,
    Int32List output,
    int outputOffset,
  ) {
    for (var i = 0; i < _numComponents; i++) {
      var pred = predicted[predictedOffset + i];
      if (pred > _maxValue) {
        pred = _maxValue;
      } else if (pred < _minValue) {
        pred = _minValue;
      }
      var orig = toInt32(pred + corrections[correctionsOffset + i]);
      if (orig > _maxValue) {
        orig -= _maxDif;
      } else if (orig < _minValue) {
        orig += _maxDif;
      }
      output[outputOffset + i] = orig;
    }
  }
}

/// Shared base for the two octahedral normal transforms.
abstract class NormalOctahedronTransformBase extends PredictionTransform {
  final OctahedronToolBox toolBox = OctahedronToolBox();

  @override
  bool get areCorrectionsPositive => true;

  int get quantizationBits => toolBox.quantizationBits;

  void _setMaxQuantizedValue(int maxQuantizedValue) {
    if (maxQuantizedValue.isEven) {
      throw dracoError('invalid octahedron max quantized value');
    }
    var q = 0;
    var v = maxQuantizedValue;
    while (v > 0) {
      v >>= 1;
      q++;
    }
    toolBox.setQuantizationBits(q);
  }

  // Rotates an out-of-diamond point into the diamond (an involution).
  // Returns s in [0] and t in [1] of the scratch list.
  void _invertDiamond(Int32List st) {
    final center = toolBox.centerValue;
    final s = st[0];
    final t = st[1];
    int signS;
    int signT;
    if (s >= 0 && t >= 0) {
      signS = 1;
      signT = 1;
    } else if (s <= 0 && t <= 0) {
      signS = -1;
      signT = -1;
    } else {
      signS = s > 0 ? 1 : -1;
      signT = t > 0 ? 1 : -1;
    }
    final cornerPointS = signS * center;
    final cornerPointT = signT * center;
    var us = toInt32(s * 2 - cornerPointS);
    var ut = toInt32(t * 2 - cornerPointT);
    if (signS * signT >= 0) {
      final temp = us;
      us = -ut;
      ut = -temp;
    } else {
      final temp = us;
      us = ut;
      ut = temp;
    }
    st[0] = (us + cornerPointS) ~/ 2;
    st[1] = (ut + cornerPointT) ~/ 2;
  }

  int _modMax(int x) {
    final center = toolBox.centerValue;
    if (x > center) return x - toolBox.maxQuantizedValue;
    if (x < -center) return x + toolBox.maxQuantizedValue;
    return x;
  }
}

/// Octahedral normal transform without canonicalization.
class NormalOctahedronTransform extends NormalOctahedronTransformBase {
  final Int32List _st = Int32List(2);

  @override
  int get type => DracoPredictionTransform.normalOctahedron;

  @override
  void decodeTransformData(DecoderBuffer buffer) {
    _setMaxQuantizedValue(buffer.decodeInt32());
  }

  @override
  void computeOriginalValue(
    Int32List predicted,
    int predictedOffset,
    Int32List corrections,
    int correctionsOffset,
    Int32List output,
    int outputOffset,
  ) {
    final center = toolBox.centerValue;
    var predS = predicted[predictedOffset] - center;
    var predT = predicted[predictedOffset + 1] - center;
    final predIsInDiamond = predS.abs() + predT.abs() <= center;
    if (!predIsInDiamond) {
      _st[0] = predS;
      _st[1] = predT;
      _invertDiamond(_st);
      predS = _st[0];
      predT = _st[1];
    }
    var origS = _modMax(toInt32(predS + corrections[correctionsOffset]));
    var origT = _modMax(toInt32(predT + corrections[correctionsOffset + 1]));
    if (!predIsInDiamond) {
      _st[0] = origS;
      _st[1] = origT;
      _invertDiamond(_st);
      origS = _st[0];
      origT = _st[1];
    }
    output[outputOffset] = toInt32(origS + center);
    output[outputOffset + 1] = toInt32(origT + center);
  }
}

/// Octahedral normal transform with canonicalized rotations.
class NormalOctahedronCanonicalizedTransform
    extends NormalOctahedronTransformBase {
  final Int32List _st = Int32List(2);

  @override
  int get type => DracoPredictionTransform.normalOctahedronCanonicalized;

  @override
  void decodeTransformData(DecoderBuffer buffer) {
    final maxQuantizedValue = buffer.decodeInt32();
    buffer.decodeInt32(); // Center value, read and ignored.
    _setMaxQuantizedValue(maxQuantizedValue);
    if (toolBox.quantizationBits < 2 || toolBox.quantizationBits > 30) {
      throw dracoError('invalid octahedron quantization bits');
    }
  }

  @override
  void computeOriginalValue(
    Int32List predicted,
    int predictedOffset,
    Int32List corrections,
    int correctionsOffset,
    Int32List output,
    int outputOffset,
  ) {
    final center = toolBox.centerValue;
    final corrS = corrections[correctionsOffset];
    final corrT = corrections[correctionsOffset + 1];
    var predS = predicted[predictedOffset] - center;
    var predT = predicted[predictedOffset + 1] - center;

    final predIsInDiamond = predS.abs() + predT.abs() <= center;
    if (!predIsInDiamond) {
      _st[0] = predS;
      _st[1] = predT;
      _invertDiamond(_st);
      predS = _st[0];
      predT = _st[1];
    }
    final predIsInBottomLeft =
        (predS == 0 && predT == 0) || (predS < 0 && predT <= 0);
    var rotationCount = 0;
    if (predS == 0) {
      if (predT > 0) {
        rotationCount = 3;
      } else if (predT < 0) {
        rotationCount = 1;
      }
    } else if (predS > 0) {
      rotationCount = predT >= 0 ? 2 : 1;
    } else {
      if (predT > 0) rotationCount = 3;
    }
    if (!predIsInBottomLeft) {
      final s = predS;
      final t = predT;
      switch (rotationCount) {
        case 1:
          predS = t;
          predT = -s;
        case 2:
          predS = -s;
          predT = -t;
        case 3:
          predS = -t;
          predT = s;
      }
    }
    var origS = _modMax(toInt32(predS + corrS));
    var origT = _modMax(toInt32(predT + corrT));
    if (!predIsInBottomLeft) {
      final s = origS;
      final t = origT;
      switch ((4 - rotationCount) & 3) {
        case 1:
          origS = t;
          origT = -s;
        case 2:
          origS = -s;
          origT = -t;
        case 3:
          origS = -t;
          origT = s;
      }
    }
    if (!predIsInDiamond) {
      _st[0] = origS;
      _st[1] = origT;
      _invertDiamond(_st);
      origS = _st[0];
      origT = _st[1];
    }
    output[outputOffset] = origS + center;
    output[outputOffset + 1] = origT + center;
  }
}
