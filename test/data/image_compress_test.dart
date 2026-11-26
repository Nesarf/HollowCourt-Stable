import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/image_compress.dart';
import 'package:image/image.dart' as img;

/// **The photograph on its way out.** A gallery original is several thousand pixels of bottle label, and every turn
/// that carries it keeps re-sending the base64 of whatever arrived. These tests check the two promises: it gets
/// smaller, and it is still a picture afterwards.
void main() {
  /// A frame with something in it.
  ///
  /// **The first version of this file used a blank image and the assertion about size failed the right way round.**
  /// A blank 3000 by 2000 frame is 22 KB of PNG and 30 KB of JPEG, because PNG compresses a constant almost to
  /// nothing while JPEG carries a fixed cost per frame. Noise is what a photograph actually is, and against noise the
  /// claim this file makes -- smaller in, smaller out -- holds.
  img.Image noisy(int width, int height, {int seed = 7}) {
    final image = img.Image(width: width, height: height);
    final random = math.Random(seed);
    for (final pixel in image) {
      pixel
        ..r = random.nextInt(256)
        ..g = random.nextInt(256)
        ..b = random.nextInt(256);
    }
    return image;
  }

  test('**a large photograph comes back at the long side, and smaller**', () async {
    final big = Uint8List.fromList(img.encodePng(noisy(1400, 1050)));
    final sent = await compressForChat(big);

    final decoded = img.decodeImage(sent);
    expect(decoded, isNotNull, reason: 'what is sent has to still be an image');
    expect(math.max(decoded!.width, decoded.height), chatImageLongSide);
    // The aspect ratio survives, which is the part a resize gets wrong when only one axis is computed.
    expect(decoded.width / decoded.height, closeTo(4 / 3, 0.02));
    expect(sent.length, lessThan(big.length));
  });

  test('a portrait frame is bounded on its height instead', () async {
    final tall = Uint8List.fromList(img.encodePng(noisy(1024, 1600)));
    final decoded = img.decodeImage(await compressForChat(tall))!;
    expect(decoded.height, chatImageLongSide);
  });

  test('a picture already inside the limit keeps its dimensions', () async {
    final small = Uint8List.fromList(img.encodeJpg(img.Image(width: 640, height: 480)));
    final decoded = img.decodeImage(await compressForChat(small))!;
    expect(decoded.width, 640);
    expect(decoded.height, 480);
  });

  test('**bytes this build cannot decode come back untouched**', () async {
    // Deciding here that a file is unreadable would be a decision about what a provider accepts, and this layer does
    // not know. Passing the bytes through leaves that where it can still be made.
    final junk = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
    expect(await compressForChat(junk), junk);
  });

  test('a transparent PNG comes back as JPEG rather than as a broken frame', () async {
    final png = Uint8List.fromList(img.encodePng(img.Image(width: 400, height: 300)));
    final sent = await compressForChat(png);
    // JPEG's own signature, which is what the request will declare.
    expect(sent.sublist(0, 3), <int>[0xFF, 0xD8, 0xFF]);
  });
}
