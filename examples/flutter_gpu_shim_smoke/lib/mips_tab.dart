import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_scene/src/gpu/shared/encoded_image_types.dart';
import 'package:flutter_scene/src/gpu/web/_gpu.dart' as gpu;
import 'package:flutter_scene/src/texture/mipmap.dart';
import 'package:web/web.dart' as web;

/// A 37x23 RGBA PNG with random color and a mix of opaque and translucent
/// texels. Odd sides exercise the edge clamp of the box filter.
const String _kPng =
    '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';

/// The PNG's pixels, straight alpha, row-major RGBA8.
const String _kRaw =
    '710p/5VaSP/jjjb/gJix//dijv+nSqIr7K6n/5F99P+pGSb+Ukjk/9xfqP+b5/n/jMHk/3y9'
    'T1PByH9/x3K+/4WTwP+sY7X/Yp8P/6xzR0kkM+2o15PG/y8v9/9NRl7/nkJZ/8Bz2P9yvwD/'
    'YSTf/37EKv+hF5v/gReFTzfQuFgXHD7/jl+x/5npbS53sQf/6HZt6NysdTIYZQX/y+fW/4g9'
    'w//Gwh//B2K8LH4hG9NaO7B9kcgu/yqxcyazwjH/ewvq/3HKyP+PVI7/22WC6DQ6PP/24ZX/'
    'ZPPOsutbSxibaYv/w7kS/+ySEB0+rYn/fCOr/xdHv//0zpX/RzId/5KB4v8BeqP/2Klk/0sK'
    'KXwPD3YoSQiu/18J1P9cQAj/qYBO/2Tehf9ykGb/hp9l/6i/kv8RsApaOS/W53GY+B1CvqPF'
    'ZVw8J37CiP9B4H3/0xy3/yVwiP8zIGr/i2ah/8uEt0zF9nBxSW9lnBmvqP+p+G8r9Goy//kY'
    'e/8Fo7gpy2/u+yqpt/8NMltjajztwWwONv/Dif+oneJ0/9Ylhf+IfJb/Zgif/1yBaf/JTCZj'
    'B9Wl/0Pe7b7qoqn/gUqL/7DlqItWvrD/vFd1/15hSf/m/s7/a6vHAvCNW9vxQVltDPyf/0o8'
    'KP8lEJb/375u/9PDYReQjaP/A2LF/6CJqv+5F1GESrsV/yQaWv/kjbn/bs70VmyDV/8vfAv/'
    'dpW+v6zqqv/Hq2rxZy8H/0w4PCfFRpn/kD63/3adMO7OqV3/EsqX/96YQ/+9fRP/d/BcPXcu'
    'yf8lQtv/lMMH/5OkpBcAsCsaRdw7/2ptrY0HJlsfn03d/4u7If+IyhASnK9X/y2xG0tphTSc'
    '+5as/9+xQP88lNL/yrBT/+Xd24gu3Xn/KSty/zTx0f+z1Xb/pUgn/x9MkP+8pVz/9wT3/8qK'
    '9R59g353Iu3N/6+dcP+9Zr7/GSk+/8yAzv+oi3d+DriG/wlodus+7Gv/UKpUcDAt0afPsVX/'
    'DF88/x7+7P/+wqhYxjUq/2k53H9IomL/ehYr/9iP6cE6Ksr/CHvo/0et5WZmJZn/D+v+VxZg'
    'tf9kyULHIvAb/3JAuP+S+e3/4poM/z/Hkf/ZWvH/riNk/0HJ0/8RfX7/gFDM//fkqP8yLtf/'
    'YhiS/77XSCA2pX3/KAG3/0dAGP97lGD/o5h+/w6idP8XFUb/P97s/4gQgfyw6ZH/brF5/1oI'
    'FP+pkjf/wPlPqaHImv+1Z7n/BuUj/5Ou7/8ANMMjORNR/979Zf/2oIH/fkNZ/w1xMP+qyuT/'
    'rgehKx0zD//zGQL/yLbe/07B7zsibJj/7NfK/8XtCP/GxDz/MoIH/xEZZf/PLQD/0eG0/w99'
    'GTIWDsz/43ePbNKQO//P7Uj/XWbR/0rVrf+pKD2EJ1m0/5HRd/+SRGr/l+6W0gDIH5T9XSv/'
    'XkFd/6mHz5QF423/PDZ9/2gPoyv+6A5X0Qxc/x3gDv+0uLbpelNO/8i979uANpTheGvr/0rP'
    'QP9PJDD/IGu6o+fU0P/I7mX/meyO/z9vsfTcBAn/Z2bE51qt7/9Fzob/AX1W6Y0wYf83gEr/'
    'tTUS/yYK5/+pmNT/QNjs/12aT/+F45PKPg0H/zEykP9iFnv/QYee/8lKK/8XXQsruVeT/24C'
    'DP8lLkn/7J7hzNGb+v/XH1n/lM92XUsefwqeien/8kLx/wDSa/8Md+vLIwk761tWjP94+pqE'
    'o2TdXYJsd/8IeQL/pFh3/3I9zv/D2Lz/VLCw/9wFK//hwmxDVD9tmYU6mf+tXyX/6Zhd/73D'
    '9P+TjXj/COgM/yMqmv+84yxSBcxp/5i70v9Pm6iIRLOx/7vF+P9aYa7/L/OL/zip/v8c9Pz/'
    'dwb//1fVQma4+gr/xdCI/zvtDP+bFjL/6mkh/0DM9XjPDmP/5e7qNXFJ5Tp3svT/Gu4yVR/R'
    'q67dVNH/Ju5y/9f90v9E0n7/msUv/zmW9v8k9wD/AkUf/8auVv9k9Z5kWUEd/wGBRKLlzsH/'
    'EgsW/3kTo//h+hB1pEyiL/sCYf/Qez2rIsr6ciQt3v+83jf/rd86/3Gf8801WAyoKn8t/3D0'
    'nv/V3Qb/mPj6ujBQhP9HyJn/3iTL/03f3F9zMq//r4WuBkuEoP+FEJ7MYx4h/2ZJoWOSS3j/'
    'NnJO//mSMP+PYhv/aeau/3Aq7f+RIcX/Jphi/6JCL/8dQlLwHo1E//WbJfrGLNP/4HMQPM+h'
    't/9SFB//CRhN/wqL9v/Gu5f6Gi3c//CgD/8dnff/D5IF/1vnNv+F2I//zNab/100Tnr1kbX/'
    '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'
    'E/8=';

const int _kWidth = 37;
const int _kHeight = 23;

/// Checks the shim's encoded-image upload against the engine's CPU mip chain,
/// byte for byte per level, for every mip content mode, plus the size cap and
/// level cap.
class MipsTab extends StatefulWidget {
  const MipsTab({super.key});

  @override
  State<MipsTab> createState() => _MipsTabState();
}

class _MipsTabState extends State<MipsTab> {
  final List<String> _lines = [];
  bool? _passed;

  @override
  void initState() {
    super.initState();
    _run();
  }

  void _log(String line) => setState(() => _lines.add(line));

  Future<void> _run() async {
    var passed = true;
    try {
      final png = base64Decode(_kPng);
      final raw = base64Decode(_kRaw);
      for (final (content, mode) in [
        (TextureContent.color, MipContent.color),
        (TextureContent.data, MipContent.data),
        (TextureContent.normal, MipContent.normal),
      ]) {
        final texture = (await gpu.createTextureFromEncodedImage(
          png,
          content: mode,
        ))!;
        final expected = generateMipChain(raw, _kWidth, _kHeight, content);
        _log(
          '$mode: ${texture.width}x${texture.height}, '
          '${texture.mipLevelCount} levels',
        );
        for (var level = 0; level < texture.mipLevelCount; level++) {
          final want = expected[level];
          final got = _readLevel(texture, level, want.width, want.height);
          var maxDiff = 0;
          var over = 0;
          for (var i = 0; i < want.pixels.length; i++) {
            final diff = (got[i] - want.pixels[i]).abs();
            maxDiff = math.max(maxDiff, diff);
            if (diff > 1) over++;
          }
          // Level 0 is the decoded image and must match exactly; the GPU's
          // float-to-byte rounding may differ from the CPU's by one.
          final ok = level == 0 ? maxDiff == 0 : over == 0;
          passed &= ok;
          _log(
            '  level $level ${want.width}x${want.height}: '
            'max diff $maxDiff, ${ok ? 'ok' : 'MISMATCH ($over texels off by >1)'}',
          );
        }
      }

      final capped = (await gpu.createTextureFromEncodedImage(
        png,
        maxSize: 16,
      ))!;
      final cappedOk =
          capped.width == 16 && capped.height == 9 && capped.mipLevelCount == 3;
      passed &= cappedOk;
      _log(
        'maxSize 16: ${capped.width}x${capped.height}, '
        '${capped.mipLevelCount} levels, ${cappedOk ? 'ok' : 'MISMATCH'}',
      );

      final flat = (await gpu.createTextureFromEncodedImage(
        png,
        mipmaps: false,
      ))!;
      final two = (await gpu.createTextureFromEncodedImage(
        png,
        maxMipLevels: 2,
      ))!;
      final levelsOk = flat.mipLevelCount == 1 && two.mipLevelCount == 2;
      passed &= levelsOk;
      _log(
        'mipmaps off: ${flat.mipLevelCount} level, maxMipLevels 2: '
        '${two.mipLevelCount} levels, ${levelsOk ? 'ok' : 'MISMATCH'}',
      );
    } catch (e, st) {
      passed = false;
      _log('FAILED: $e\n$st');
    }
    setState(() => _passed = passed);
  }

  Uint8List _readLevel(gpu.Texture texture, int level, int width, int height) {
    final gl = gpu.gpuContext.gl;
    final fbo = gl.createFramebuffer();
    gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, fbo);
    gl.framebufferTexture2D(
      web.WebGL2RenderingContext.FRAMEBUFFER,
      web.WebGL2RenderingContext.COLOR_ATTACHMENT0,
      web.WebGL2RenderingContext.TEXTURE_2D,
      texture.glTexture,
      level,
    );
    final out = Uint8List(width * height * 4).toJS;
    gl.readPixels(
      0,
      0,
      width,
      height,
      web.WebGL2RenderingContext.RGBA,
      web.WebGL2RenderingContext.UNSIGNED_BYTE,
      out,
    );
    gl.bindFramebuffer(web.WebGL2RenderingContext.FRAMEBUFFER, null);
    gl.deleteFramebuffer(fbo);
    return out.toDart;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(switch (_passed) {
            null => 'Mip parity: running',
            true => 'Mip parity: PASS',
            false => 'Mip parity: FAIL',
          }, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                _lines.join('\n'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
