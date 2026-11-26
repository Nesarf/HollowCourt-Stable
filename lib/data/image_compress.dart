import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// **The longest side a photograph is allowed to keep before it is sent.**
///
/// 1280 is not a guess: `barcode_decoder.dart` already uses it for the same reason, and a vision model downscales
/// whatever arrives to roughly this size before it looks at it. Sending four thousand pixels of a bottle label buys
/// nothing the model can use and costs a base64 string four times the size -- on the phone's data, on the request,
/// and on every turn that keeps the photograph in its history.
const int chatImageLongSide = 1280;

/// JPEG quality after the resize. High enough that a printed label still reads, low enough that the file is a
/// fraction of the original.
const int chatImageQuality = 85;

/// Downscales and re-encodes a photograph for the conversation, off the UI isolate.
///
/// **Not on the main isolate**, because decoding a modern phone photograph is tens of megabytes of pixels and the
/// screen would drop frames while it happened. `compute` is the whole of the machinery this needs.
///
/// **An unrecognised format comes back untouched.** The alternative is deciding here that a file is unreadable, and
/// this layer does not know what the provider accepts -- HEIC that this build cannot decode may well be fine at the
/// other end. Passing the bytes through leaves that decision where it can still be made.
Future<Uint8List> compressForChat(Uint8List bytes) => compute(_compress, bytes);

Uint8List _compress(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  final longSide = decoded.width >= decoded.height ? decoded.width : decoded.height;
  final resized = longSide <= chatImageLongSide
      ? decoded
      : decoded.width >= decoded.height
          ? img.copyResize(decoded, width: chatImageLongSide, interpolation: img.Interpolation.average)
          : img.copyResize(decoded, height: chatImageLongSide, interpolation: img.Interpolation.average);

  return Uint8List.fromList(img.encodeJpg(resized, quality: chatImageQuality));
}
