import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart';
import 'package:meal_of_record/services/live_database.dart';

class ImageStorageService {
  static final ImageStorageService instance = ImageStorageService._();
  ImageStorageService._();

  // Public constant for use throughout the app
  static const String localPrefix = 'local:';
  static const String _imagesFolderName = 'app_images';
  static const int _maxImageSize = 200;
  static const int _jpegQuality = 85;

  Directory? _imagesDirectory;

  /// Initialize the image storage service
  /// Ensures the images folder exists in the documents directory
  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _imagesDirectory = Directory('${appDir.path}/$_imagesFolderName');

    if (!await _imagesDirectory!.exists()) {
      await _imagesDirectory!.create(recursive: true);
    }
  }

  /// Save an image file to the images folder
  /// Resizes to fit within 200x200 pixels at 85% quality
  /// Returns the GUID of the saved image
  Future<String> saveImage(File sourceFile) async {
    if (_imagesDirectory == null) {
      await init();
    }

    // Generate GUID for filename
    final guid = const Uuid().v4();
    final fileName = '$guid.jpg';
    final targetPath = '${_imagesDirectory!.path}/$fileName';

    // Load and resize image
    final imageBytes = await sourceFile.readAsBytes();
    final image = decodeImage(imageBytes);

    if (image == null) {
      throw Exception('Failed to decode image');
    }

    // Center-crop to square
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

    // Resize (input is already square, so only width needed)
    final resized = copyResize(cropped, width: _maxImageSize);

    // Encode as JPEG at 85% quality
    final encoded = encodeJpg(resized, quality: _jpegQuality);

    // Write to file
    final outputFile = File(targetPath);
    await outputFile.writeAsBytes(encoded);

    return guid;
  }

  /// Delete an image file by GUID
  Future<void> deleteImage(String guid) async {
    if (_imagesDirectory == null) {
      await init();
    }

    final imagePath = '${_imagesDirectory!.path}/$guid.jpg';
    final file = File(imagePath);

    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Get the full file path for a GUID
  Future<String> getImagePath(String guid) async {
    if (_imagesDirectory == null) {
      await init();
    }

    return '${_imagesDirectory!.path}/$guid.jpg';
  }

  /// Check if a thumbnail string refers to a local image
  bool isLocalImage(String? thumbnail) {
    return thumbnail != null && thumbnail.startsWith(localPrefix);
  }

  /// Extract the GUID from a local thumbnail string
  String? extractGuid(String thumbnail) {
    if (!isLocalImage(thumbnail)) {
      return null;
    }
    return thumbnail.substring(localPrefix.length);
  }

  /// Get all GUIDs referenced in the database
  Future<Set<String>> getAllReferencedGuids(LiveDatabase db) async {
    final foods = await (db.select(db.foods).get());
    final guids = <String>{};

    for (final food in foods) {
      if (food.thumbnail != null) {
        final guid = extractGuid(food.thumbnail!);
        if (guid != null) {
          guids.add(guid);
        }
      }
    }

    return guids;
  }

  /// Delete unreferenced images (garbage collection)
  /// Scans the images folder and deletes any files not in the referenced set
  Future<void> deleteUnreferencedImages(LiveDatabase db) async {
    if (_imagesDirectory == null) {
      await init();
    }

    final referencedGuids = await getAllReferencedGuids(db);
    final files = await _imagesDirectory!.list().toList();

    for (final file in files) {
      if (file is File) {
        final fileName = file.path.split('/').last;
        // Remove .jpg extension to get GUID
        final guid = fileName.replaceAll('.jpg', '');

        if (!referencedGuids.contains(guid)) {
          await file.delete();
        }
      }
    }
  }

  /// Get the images directory path
  Future<String> getImagesDirectoryPath() async {
    if (_imagesDirectory == null) {
      await init();
    }
    return _imagesDirectory!.path;
  }

  /// Get the images directory
  Future<Directory> getImagesDirectory() async {
    if (_imagesDirectory == null) {
      await init();
    }
    return _imagesDirectory!;
  }

  /// Encode an image to Base64 string for QR sharing
  Future<String?> encodeImageToBase64(String guid) async {
    final imagePath = await getImagePath(guid);
    final file = File(imagePath);
    if (!await file.exists()) {
      return null;
    }
    final bytes = await file.readAsBytes();
    return base64Encode(bytes);
  }

  /// Save an image from a Base64 string (used during QR import)
  /// Returns the new GUID
  Future<String> saveImageFromBase64(String base64Data) async {
    if (_imagesDirectory == null) {
      await init();
    }

    final bytes = base64Decode(base64Data);
    final guid = const Uuid().v4();
    final fileName = '$guid.jpg';
    final targetPath = '${_imagesDirectory!.path}/$fileName';

    final outputFile = File(targetPath);
    await outputFile.writeAsBytes(bytes);

    return guid;
  }
}
