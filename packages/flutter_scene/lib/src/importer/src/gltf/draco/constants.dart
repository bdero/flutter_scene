// Shared constants for the Draco bitstream, matching the values in the Draco
// Bitstream Specification, "Draco Decoder" and "Descriptions" sections
// (https://google.github.io/draco/spec/).

/// Geometry attribute types.
abstract final class DracoAttributeType {
  static const int invalid = -1;
  static const int position = 0;
  static const int normal = 1;
  static const int color = 2;
  static const int texCoord = 3;
  static const int generic = 4;
  static const int namedAttributesCount = 5;
}

/// Component data types.
abstract final class DracoDataType {
  static const int invalid = 0;
  static const int int8 = 1;
  static const int uint8 = 2;
  static const int int16 = 3;
  static const int uint16 = 4;
  static const int int32 = 5;
  static const int uint32 = 6;
  static const int int64 = 7;
  static const int uint64 = 8;
  static const int float32 = 9;
  static const int float64 = 10;
  static const int bool_ = 11;
  static const int typesCount = 12;

  static int byteLength(int dataType) {
    switch (dataType) {
      case int8:
      case uint8:
      case bool_:
        return 1;
      case int16:
      case uint16:
        return 2;
      case int32:
      case uint32:
      case float32:
        return 4;
      case int64:
      case uint64:
      case float64:
        return 8;
      default:
        return -1;
    }
  }
}

/// Geometry type codes in the Draco header.
abstract final class DracoGeometryType {
  static const int pointCloud = 0;
  static const int triangularMesh = 1;
}

/// Mesh connectivity encoding methods.
abstract final class DracoMeshEncoderMethod {
  static const int sequential = 0;
  static const int edgebreaker = 1;
}

/// Sequential attribute decoder types.
abstract final class DracoSequentialAttributeEncoderType {
  static const int generic = 0;
  static const int integer = 1;
  static const int quantization = 2;
  static const int normals = 3;
}

/// Attribute prediction scheme methods.
abstract final class DracoPredictionScheme {
  static const int none = -2;
  static const int undefined = -1;
  static const int difference = 0;
  static const int meshParallelogram = 1;
  static const int meshMultiParallelogram = 2;
  static const int meshTexCoordsDeprecated = 3;
  static const int meshConstrainedMultiParallelogram = 4;
  static const int meshTexCoordsPortable = 5;
  static const int meshGeometricNormal = 6;
  static const int count = 7;
}

/// Prediction scheme transform types.
abstract final class DracoPredictionTransform {
  static const int none = -1;
  static const int delta = 0;
  static const int wrap = 1;
  static const int normalOctahedron = 2;
  static const int normalOctahedronCanonicalized = 3;
  static const int count = 4;
}

/// Mesh attribute traversal methods.
abstract final class DracoTraversalMethod {
  static const int depthFirst = 0;
  static const int predictionDegree = 1;
  static const int count = 2;
}

/// EdgeBreaker connectivity coding variants.
abstract final class DracoEdgebreakerMethod {
  static const int standard = 0;
  static const int predictive = 1; // Deprecated in bitstream 2.2.
  static const int valence = 2;
}

/// Mesh attribute element types.
abstract final class DracoMeshAttributeElementType {
  static const int vertex = 0;
  static const int corner = 1;
  static const int face = 2;
}

/// EdgeBreaker topology symbols (bit patterns from the specification).
abstract final class DracoTopology {
  static const int c = 0x0;
  static const int s = 0x1;
  static const int l = 0x3;
  static const int r = 0x5;
  static const int e = 0x7;
  static const int invalid = 9;
}

/// Symbol id (valence coding) to topology bit pattern.
const List<int> dracoSymbolToTopologyId = [
  DracoTopology.c,
  DracoTopology.s,
  DracoTopology.l,
  DracoTopology.r,
  DracoTopology.e,
];

/// Metadata presence bit in the Draco header flags.
const int dracoMetadataFlagMask = 0x8000;

const int dracoInvalidCornerIndex = -1;
