// EdgeBreaker traversal symbol decoders (standard and valence coded). See the
// Draco Bitstream Specification, "EdgeBreaker Traversal" and "EdgeBreaker
// Traversal Valence" (https://google.github.io/draco/spec/).

import 'dart:typed_data';

import 'constants.dart';
import 'corner_table.dart';
import 'decoder_buffer.dart';
import 'rans.dart';
import 'symbol_decoding.dart';

/// Standard traversal decoder, topology symbols as variable-length bit codes,
/// start faces and attribute seams as rANS coded bits.
class MeshEdgebreakerTraversalDecoder {
  late DecoderBuffer buffer;
  DecoderBuffer? _symbolBuffer;
  RAnsBitDecoder? _startFaceDecoder;
  final List<RAnsBitDecoder> attributeConnectivityDecoders = [];
  int _numAttributeData = 0;

  void init(DecoderBuffer srcBuffer) {
    buffer = DecoderBuffer(srcBuffer.dataHead, srcBuffer.bitstreamVersion);
  }

  /// The total vertex count including split vertices. Only the valence
  /// decoder needs it.
  void setNumEncodedVertices(int numVertices) {}

  void setNumAttributeData(int numData) {
    _numAttributeData = numData;
  }

  /// Consumes the traversal sections and returns a buffer positioned at the
  /// data encoded after them.
  DecoderBuffer start() {
    _decodeTraversalSymbols();
    _decodeStartFaces();
    _decodeAttributeSeams();
    return DecoderBuffer(buffer.dataHead, buffer.bitstreamVersion);
  }

  bool decodeStartFaceConfiguration() {
    final decoder = _startFaceDecoder;
    if (decoder == null) {
      throw dracoError('missing start face data');
    }
    return decoder.decodeNextBit();
  }

  int decodeSymbol() {
    final symbolBuffer = _symbolBuffer!;
    var symbol = symbolBuffer.decodeLeastSignificantBits32(1);
    if (symbol == DracoTopology.c) {
      return symbol;
    }
    // Non-C symbols carry two additional bits.
    final suffix = symbolBuffer.decodeLeastSignificantBits32(2);
    return symbol | (suffix << 1);
  }

  void newActiveCornerReached(int corner) {}

  void mergeVertices(int dest, int source) {}

  void done() {
    final symbolBuffer = _symbolBuffer;
    if (symbolBuffer != null && symbolBuffer.bitDecoderActive) {
      symbolBuffer.endBitDecoding();
    }
  }

  void _decodeTraversalSymbols() {
    final symbolBuffer = DecoderBuffer(
      buffer.dataHead,
      buffer.bitstreamVersion,
    );
    final traversalSize = symbolBuffer.startBitDecoding(sizePrefixed: true);
    _symbolBuffer = symbolBuffer;
    // Advance the main buffer past the size varint and the symbol bits.
    buffer = DecoderBuffer(symbolBuffer.dataHead, buffer.bitstreamVersion);
    if (traversalSize > buffer.remainingSize) {
      throw dracoError('traversal section truncated');
    }
    buffer.advance(traversalSize);
  }

  void _decodeStartFaces() {
    _startFaceDecoder = RAnsBitDecoder()..startDecoding(buffer);
  }

  void _decodeAttributeSeams() {
    for (var i = 0; i < _numAttributeData; i++) {
      attributeConnectivityDecoders.add(
        RAnsBitDecoder()..startDecoding(buffer),
      );
    }
  }
}

/// Valence coded traversal decoder. The decoded portion's vertex valences
/// select the entropy context each symbol was coded with.
class MeshEdgebreakerTraversalValenceDecoder
    extends MeshEdgebreakerTraversalDecoder {
  MeshEdgebreakerTraversalValenceDecoder(this._cornerTable);

  final CornerTable _cornerTable;

  static const int _minValence = 2;
  static const int _maxValence = 7;

  int _numVertices = 0;
  int _lastSymbol = -1;
  int _activeContext = -1;
  Int32List _vertexValences = Int32List(0);
  final List<Uint32List> _contextSymbols = [];
  final List<int> _contextCounters = [];

  @override
  void setNumEncodedVertices(int numVertices) {
    _numVertices = numVertices;
  }

  @override
  DecoderBuffer start() {
    _decodeStartFaces();
    _decodeAttributeSeams();
    final outBuffer = DecoderBuffer(buffer.dataHead, buffer.bitstreamVersion);

    _vertexValences = Int32List(_numVertices);

    const numUniqueValences = _maxValence - _minValence + 1;
    for (var i = 0; i < numUniqueValences; i++) {
      final numSymbols = outBuffer.decodeVarint();
      if (numSymbols > _cornerTable.numFaces) {
        throw dracoError('invalid valence symbol count');
      }
      final symbols = Uint32List(numSymbols);
      if (numSymbols > 0) {
        decodeSymbols(numSymbols, 1, outBuffer, symbols);
      }
      _contextSymbols.add(symbols);
      // Symbols are consumed from the back.
      _contextCounters.add(numSymbols);
    }
    return outBuffer;
  }

  @override
  int decodeSymbol() {
    if (_activeContext == -1) {
      // The first symbol is always E.
      _lastSymbol = DracoTopology.e;
      return _lastSymbol;
    }
    final counter = --_contextCounters[_activeContext];
    if (counter < 0) {
      return DracoTopology.invalid;
    }
    final symbolId = _contextSymbols[_activeContext][counter];
    if (symbolId > 4) {
      return DracoTopology.invalid;
    }
    _lastSymbol = dracoSymbolToTopologyId[symbolId];
    return _lastSymbol;
  }

  @override
  void newActiveCornerReached(int corner) {
    final cornerToVertex = _cornerTable.cornerToVertex;
    final next = cornerNext(corner);
    final prev = cornerPrevious(corner);
    switch (_lastSymbol) {
      case DracoTopology.c:
      case DracoTopology.s:
        _vertexValences[cornerToVertex[next]] += 1;
        _vertexValences[cornerToVertex[prev]] += 1;
      case DracoTopology.r:
        _vertexValences[cornerToVertex[corner]] += 1;
        _vertexValences[cornerToVertex[next]] += 1;
        _vertexValences[cornerToVertex[prev]] += 2;
      case DracoTopology.l:
        _vertexValences[cornerToVertex[corner]] += 1;
        _vertexValences[cornerToVertex[next]] += 2;
        _vertexValences[cornerToVertex[prev]] += 1;
      case DracoTopology.e:
        _vertexValences[cornerToVertex[corner]] += 2;
        _vertexValences[cornerToVertex[next]] += 2;
        _vertexValences[cornerToVertex[prev]] += 2;
    }
    // The clamped valence of the next vertex selects the context.
    var valence = _vertexValences[cornerToVertex[next]];
    if (valence < _minValence) {
      valence = _minValence;
    } else if (valence > _maxValence) {
      valence = _maxValence;
    }
    _activeContext = valence - _minValence;
  }

  @override
  void mergeVertices(int dest, int source) {
    _vertexValences[dest] += _vertexValences[source];
  }
}
