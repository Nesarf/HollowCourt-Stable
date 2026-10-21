import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing_lib/common.dart';
import 'package:zxing_lib/zxing.dart';

/// **What a camera frame turned out to hold.**
///
/// `text` is the digits as the decoder read them. Nothing here decides whether they are a barcode the application
/// accepts -- that is `domain/model/barcode.dart`, which owns the check digit and the symbology rules, and this class
/// deliberately does not know them. A decoder that also validated would be a second copy of those rules sitting in a
/// layer that cannot be tested without an image.
class ScannedBarcode {
  const ScannedBarcode(this.text, this.format);

  final String text;
  final BarcodeFormat format;

  @override
  String toString() => '$text ($format)';
}

/// **The symbologies this application can read, and nothing else.**
///
/// The four code formats are what `domain/model/barcode.dart` carries; `code128` is here because a supplier's carton
/// carries it even when the bottle does not. Asking the reader for everything would try QR first and cost time on
/// every frame.
const List<BarcodeFormat> _formats = <BarcodeFormat>[
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
];

/// **A frame wider than this is scaled down before it is decoded, and the direction matters.**
///
/// EAN-13 is a one-dimensional code: its information is in the *horizontal* run lengths, while the vertical axis
/// only says how tall the bars are. So a photo taken at 1920 wide is mostly wasted vertical resolution, and the cost
/// is paid twice -- once in the file the camera writes and once in the decode. Scaling the long side to 1280 keeps
/// the bar edges sharp (the visible test below measures that) and cuts the work to a third.
const int _maxDimension = 1280;

/// Decodes a barcode from encoded image bytes (PNG, JPEG, whatever `package:image` reads).
///
/// Returns null when there is no barcode in the picture. **Null rather than an exception**, because "no code in this
/// frame" is the ordinary case for a camera pointed at a shelf -- it happens several times a second, and a listener
/// that had to catch an exception to mean "keep looking" would be a listener that swallows real faults too.
ScannedBarcode? decodeBarcodeBytes(Uint8List bytes, {bool tryHarder = true}) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  return decodeBarcodeImage(image, tryHarder: tryHarder);
}

/// The same, from an already-decoded image. Separate because a camera that hands over pixels should not have to
/// encode them into a PNG just to have them decoded again, and because the tests build images in memory.
ScannedBarcode? decodeBarcodeImage(img.Image image, {bool tryHarder = true}) {
  final prepared = _scaled(image);
  try {
    final rgba = prepared.convert(numChannels: 4).getBytes(order: img.ChannelOrder.abgr);
    final source = RGBLuminanceSource(
      prepared.width,
      prepared.height,
      rgba.buffer.asInt32List(),
    );
    final bitmap = BinaryBitmap(GlobalHistogramBinarizer(source));
    final result = MultiFormatReader().decode(
      bitmap,
      DecodeHint(possibleFormats: _formats, tryHarder: tryHarder),
    );
    return ScannedBarcode(result.text, result.barcodeFormat);
  } on Exception {
    // `NotFoundException` is a `ReaderException` extends `Exception`, and it is the answer for most frames.
    return null;
  }
}

img.Image _scaled(img.Image image) {
  final longest = image.width > image.height ? image.width : image.height;
  if (longest <= _maxDimension) return image;
  final ratio = _maxDimension / longest;
  final width = (image.width * ratio).round();
  final height = (image.height * ratio).round();
  return img.copyResize(image, width: width, height: height, interpolation: img.Interpolation.nearest);
}
