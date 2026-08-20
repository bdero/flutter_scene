// EdgeBreaker connectivity decoding. See the Draco Bitstream Specification,
// "EdgeBreaker Decoder" (https://google.github.io/draco/spec/).

import 'attribute_decoders.dart';
import 'decoder_buffer.dart';
import 'mesh_decoder.dart';

/// Decodes EdgeBreaker-coded connectivity.
class EdgebreakerMeshDecoder extends DracoMeshDecoder {
  EdgebreakerMeshDecoder(super.buffer);

  @override
  void decodeConnectivity() {
    // TODO(draco-edgebreaker): port the EdgeBreaker connectivity decoder.
    throw dracoError('EdgeBreaker connectivity is not yet supported');
  }

  @override
  AttributesDecoderController createAttributesController(int controllerId) {
    throw dracoError('EdgeBreaker connectivity is not yet supported');
  }
}
