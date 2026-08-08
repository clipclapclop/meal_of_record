import 'package:image/image.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for the center-crop-then-resize logic used in ImageStorageService.saveImage().
/// Uses the image package directly (pure Dart, no Flutter/platform dependencies).
void main() {
  const maxImageSize = 200;

  /// Replicates the crop-then-resize logic from ImageStorageService.saveImage()
  Image cropAndResize(Image image) {
    final cropSize = image.width < image.height ? image.width : image.height;
    final x = (image.width - cropSize) ~/ 2;
    final y = (image.height - cropSize) ~/ 2;
    final cropped = copyCrop(
      image,
      x: x,
      y: y,
      width: cropSize,
      height: cropSize,
    );
    return copyResize(cropped, width: maxImageSize);
  }

  test(
    'Landscape image: 400x300 crops to 300x300 from center then resizes to 200x200',
    () {
      final image = Image(width: 400, height: 300);
      final result = cropAndResize(image);

      expect(result.width, 200);
      expect(result.height, 200);
    },
  );

  test(
    'Portrait image: 300x400 crops to 300x300 from center then resizes to 200x200',
    () {
      final image = Image(width: 300, height: 400);
      final result = cropAndResize(image);

      expect(result.width, 200);
      expect(result.height, 200);
    },
  );

  test('Already square image: 300x300 resizes to 200x200', () {
    final image = Image(width: 300, height: 300);
    final result = cropAndResize(image);

    expect(result.width, 200);
    expect(result.height, 200);
  });

  test(
    'Full pipeline: 4000x3000 crops to 3000x3000 then resizes to 200x200',
    () {
      final image = Image(width: 4000, height: 3000);
      final result = cropAndResize(image);

      expect(result.width, 200);
      expect(result.height, 200);
    },
  );

  test(
    'Ultra-wide panoramic: 1000x100 crops to 100x100 from center then resizes to 200x200',
    () {
      final image = Image(width: 1000, height: 100);
      final result = cropAndResize(image);

      expect(result.width, 200);
      expect(result.height, 200);
    },
  );

  test('Tiny 1x1 image crops to 1x1 then upscales to 200x200', () {
    final image = Image(width: 1, height: 1);
    final result = cropAndResize(image);

    expect(result.width, 200);
    expect(result.height, 200);
  });

  test('Landscape crop coordinates are correct', () {
    final image = Image(width: 400, height: 300);
    final cropSize = image.width < image.height ? image.width : image.height;
    final x = (image.width - cropSize) ~/ 2;
    final y = (image.height - cropSize) ~/ 2;

    expect(cropSize, 300);
    expect(x, 50);
    expect(y, 0);
  });

  test('Portrait crop coordinates are correct', () {
    final image = Image(width: 300, height: 400);
    final cropSize = image.width < image.height ? image.width : image.height;
    final x = (image.width - cropSize) ~/ 2;
    final y = (image.height - cropSize) ~/ 2;

    expect(cropSize, 300);
    expect(x, 0);
    expect(y, 50);
  });

  test('Ultra-wide crop coordinates are correct', () {
    final image = Image(width: 1000, height: 100);
    final cropSize = image.width < image.height ? image.width : image.height;
    final x = (image.width - cropSize) ~/ 2;
    final y = (image.height - cropSize) ~/ 2;

    expect(cropSize, 100);
    expect(x, 450);
    expect(y, 0);
  });

  test('Square image crop coordinates are zero', () {
    final image = Image(width: 300, height: 300);
    final cropSize = image.width < image.height ? image.width : image.height;
    final x = (image.width - cropSize) ~/ 2;
    final y = (image.height - cropSize) ~/ 2;

    expect(cropSize, 300);
    expect(x, 0);
    expect(y, 0);
  });
}
