// Attribute prediction scheme decoders. See the Draco Bitstream
// Specification, "Prediction Decoder" (https://google.github.io/draco/spec/).

import 'dart:typed_data';

import 'attributes.dart';
import 'constants.dart';
import 'decoder_buffer.dart';
import 'prediction_transforms.dart';

/// Base class for prediction scheme decoders.
abstract class PredictionSchemeDecoder {
  PredictionSchemeDecoder(this.transform);

  final PredictionTransform transform;

  bool get areCorrectionsPositive => transform.areCorrectionsPositive;

  int get numParentAttributes => 0;

  int parentAttributeType(int i) => DracoAttributeType.invalid;

  void setParentAttribute(PortableAttribute attribute) {
    throw dracoError('prediction scheme takes no parent attribute');
  }

  void decodePredictionData(DecoderBuffer buffer) {
    transform.decodeTransformData(buffer);
  }

  /// Reconstructs original values from corrections, in place ([corrections]
  /// and [output] may alias).
  void computeOriginalValues(
    Int32List corrections,
    Int32List output,
    int size,
    int numComponents,
    Int32List entryToPointIdMap,
  );
}

/// Difference (delta) prediction, value(i) = value(i-1) + correction(i).
class DeltaPredictionDecoder extends PredictionSchemeDecoder {
  DeltaPredictionDecoder(super.transform);

  @override
  void computeOriginalValues(
    Int32List corrections,
    Int32List output,
    int size,
    int numComponents,
    Int32List entryToPointIdMap,
  ) {
    transform.init(numComponents);
    final zeros = Int32List(numComponents);
    transform.computeOriginalValue(zeros, 0, corrections, 0, output, 0);
    for (var i = numComponents; i < size; i += numComponents) {
      transform.computeOriginalValue(
        output,
        i - numComponents,
        corrections,
        i,
        output,
        i,
      );
    }
  }
}
