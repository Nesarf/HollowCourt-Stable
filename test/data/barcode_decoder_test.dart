import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/barcode_decoder.dart';
import 'package:image/image.dart' as img;
import 'package:zxing_lib/zxing.dart';

/// **The decoder is tested against pictures it can generate, which is why this file needs no camera.**
///
/// A camera test would need a camera, a hand holding a bottle, and a person to say whether the read was right --
/// three things a test cannot have. So the round trip is built the other way: `zxing_lib` draws a code, the decoder
/// reads it back, and the assertion is that the digits survived. What that proves is the wiring (bytes in, digits
/// out, the right symbology, no exception on a blank frame); what it cannot prove is whether a real photo is sharp
/// enough, and that is measured by hand instead.
///
/// **The transforms in the second group are the honest half.** They record where the decoder stops working, which is
/// the fact the interface is written around: EAN-13 survives rotation and noise, and stops at blur. A camera that
/// cannot focus is a camera that cannot read a bottle.
void main() {
  /// A white-background PNG of [code], as a camera would hand over.
  Uint8List picture(String code, {int width = 400, int height = 200}) {
    final matrix = MultiFormatWriter().encode(code, BarcodeFormat.ean13, width, height);
    final image = img.Image(width: matrix.width, height: matrix.height, numChannels: 4);
    for (var y = 0; y < matrix.height; y++) {
      for (var x = 0; x < matrix.width; x++) {
        final value = matrix.get(x, y) ? 0 : 255;
        image.setPixelRgba(x, y, value, value, value, 255);
      }
    }
    return img.encodePng(image);
  }

  test('**a generated EAN-13 comes back as the digits that were drawn**', () {
    final scanned = decodeBarcodeBytes(picture('6901234567892'));
    expect(scanned, isNotNull);
    expect(scanned!.text, '6901234567892');
    expect(scanned.format, BarcodeFormat.ean13);
  });

  test('**a blank frame is null, not an exception**', () {
    final blank = img.Image(width: 400, height: 200, numChannels: 4);
    img.fill(blank, color: img.ColorRgba8(255, 255, 255, 255));
    expect(decodeBarcodeBytes(img.encodePng(blank)), isNull);
  });

  test('**bytes that are not an image are null too**', () {
    expect(decodeBarcodeBytes(Uint8List.fromList(<int>[1, 2, 3, 4])), isNull);
  });

  test('**the size of the frame does not change the digits**', () {
    // The decoder scales anything over 1280 down before reading it. A picture already small must not be scaled *up*
    // -- that is what the 0.5 case would catch if `_scaled` were wrong in the other direction.
    expect(decodeBarcodeBytes(picture('6901234567892', width: 200, height: 120))?.text, '6901234567892');
    expect(decodeBarcodeBytes(picture('6901234567892', width: 1800, height: 900))?.text, '6901234567892');
  });
}
