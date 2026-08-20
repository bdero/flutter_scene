// Parses the Khronos basic data format descriptor block of a KTX2 file
// (Khronos Data Format Specification 1.3, section 5), enough to identify the
// color model (ETC1S/UASTC/uncompressed), transfer function, and sample
// channels of standard Basis Universal textures.

import 'dart:typed_data';

import 'package:flutter_scene/src/texture/ktx2/ktx2.dart';

// KHR_DF_MODEL_* values this reader distinguishes.
const int kDfModelRgbsda = 1;
const int kDfModelEtc1s = 163;
const int kDfModelUastc = 166;

// KHR_DF_TRANSFER_* values.
const int kDfTransferLinear = 1;
const int kDfTransferSrgb = 2;

// ETC1S channel types.
const int kDfChannelEtc1sRgb = 0;
const int kDfChannelEtc1sAaa = 15;

// UASTC channel types.
const int kDfChannelUastcRgb = 0;
const int kDfChannelUastcRgba = 3;
const int kDfChannelUastcRrrg = 5;

/// One sample from the basic descriptor block; only the channel type matters
/// for transcoding.
class Ktx2DfdSample {
  Ktx2DfdSample({required this.channelType});

  /// Low 4 bits of the sample's channel field (KHR_DF_CHANNEL_*).
  final int channelType;
}

/// The fields of a KTX2 basic data format descriptor block used to route
/// standard textures.
class Ktx2DataFormat {
  Ktx2DataFormat({
    required this.colorModel,
    required this.transferFunction,
    required this.samples,
  });

  final int colorModel;
  final int transferFunction;
  final List<Ktx2DfdSample> samples;

  bool get isSrgb => transferFunction == kDfTransferSrgb;

  /// Whether the encoded data carries alpha. ETC1S ships alpha as a second
  /// slice signaled by an AAA sample; UASTC encodes it in-block and signals it
  /// through the channel type.
  bool get hasAlpha => switch (colorModel) {
    kDfModelEtc1s =>
      samples.length >= 2 && samples[1].channelType == kDfChannelEtc1sAaa,
    kDfModelUastc =>
      samples.isNotEmpty &&
          (samples[0].channelType == kDfChannelUastcRgba ||
              samples[0].channelType == kDfChannelUastcRrrg),
    _ => false,
  };
}

/// Parses the first basic descriptor block out of [texture]'s data format
/// descriptor. Throws [Ktx2FormatException] when none is present.
Ktx2DataFormat readDataFormat(Ktx2Texture texture) {
  final dfd = texture.dataFormatDescriptor;
  if (dfd.length < 4) {
    throw Ktx2FormatException('Data format descriptor is too short');
  }
  final data = ByteData.sublistView(dfd);
  final totalSize = data.getUint32(0, Endian.little);
  if (totalSize > dfd.length) {
    throw Ktx2FormatException('Data format descriptor size exceeds section');
  }
  var offset = 4;
  while (offset + 8 <= totalSize) {
    final vendorAndType = data.getUint32(offset, Endian.little);
    final vendorId = vendorAndType & 0x1FFFF;
    final descriptorType = vendorAndType >> 17;
    final blockSize = data.getUint32(offset + 4, Endian.little) >> 16;
    if (blockSize < 8 || offset + blockSize > totalSize) {
      throw Ktx2FormatException('Malformed descriptor block');
    }
    // Khronos basic descriptor block: vendor 0, type 0.
    if (vendorId == 0 && descriptorType == 0 && blockSize >= 24) {
      final colorModel = data.getUint8(offset + 8);
      final transferFunction = data.getUint8(offset + 10);
      final samples = <Ktx2DfdSample>[];
      for (var s = offset + 24; s + 16 <= offset + blockSize; s += 16) {
        final word = data.getUint32(s, Endian.little);
        samples.add(Ktx2DfdSample(channelType: (word >> 24) & 0xF));
      }
      return Ktx2DataFormat(
        colorModel: colorModel,
        transferFunction: transferFunction,
        samples: samples,
      );
    }
    offset += blockSize;
  }
  throw Ktx2FormatException('No basic data format descriptor block');
}
