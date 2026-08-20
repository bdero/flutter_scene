// Entropy-coded symbol decoding (tagged and raw schemes). See the Draco
// Bitstream Specification, "Rans Decoding" and "Core Functions"
// (https://google.github.io/draco/spec/).

import 'dart:typed_data';

import 'decoder_buffer.dart';
import 'rans.dart';

const int _symbolCodingTagged = 0;
const int _symbolCodingRaw = 1;

/// Decodes [numValues] entropy-coded symbols into [outValues].
/// [numComponents] selects the tag stride for the tagged scheme.
void decodeSymbols(
  int numValues,
  int numComponents,
  DecoderBuffer buffer,
  Uint32List outValues,
) {
  if (numValues == 0) {
    return;
  }
  final scheme = buffer.decodeUint8();
  if (scheme == _symbolCodingTagged) {
    _decodeTaggedSymbols(numValues, numComponents, buffer, outValues);
  } else if (scheme == _symbolCodingRaw) {
    _decodeRawSymbols(numValues, buffer, outValues);
  } else {
    throw dracoError('unknown symbol coding scheme $scheme');
  }
}

void _decodeTaggedSymbols(
  int numValues,
  int numComponents,
  DecoderBuffer buffer,
  Uint32List outValues,
) {
  final tagDecoder = RAnsSymbolDecoder(5);
  tagDecoder.create(buffer);
  tagDecoder.startDecoding(buffer);
  if (numValues > 0 && tagDecoder.numSymbols == 0) {
    throw dracoError('no tag symbols');
  }
  buffer.startBitDecoding(sizePrefixed: false);
  var valueId = 0;
  for (var i = 0; i < numValues; i += numComponents) {
    final bitLength = tagDecoder.decodeSymbol();
    for (var j = 0; j < numComponents; j++) {
      outValues[valueId++] = buffer.decodeLeastSignificantBits32(bitLength);
    }
  }
  buffer.endBitDecoding();
}

void _decodeRawSymbols(
  int numValues,
  DecoderBuffer buffer,
  Uint32List outValues,
) {
  final maxBitLength = buffer.decodeUint8();
  if (maxBitLength < 1 || maxBitLength > 18) {
    throw dracoError('invalid symbol bit length $maxBitLength');
  }
  final decoder = RAnsSymbolDecoder(maxBitLength);
  decoder.create(buffer);
  if (numValues > 0 && decoder.numSymbols == 0) {
    throw dracoError('no symbols');
  }
  decoder.startDecoding(buffer);
  decoder.decodeSymbols(outValues, numValues);
}
