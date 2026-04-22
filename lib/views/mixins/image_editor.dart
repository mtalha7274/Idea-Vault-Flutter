import 'dart:io';

import '../../core/utils/helpers.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;

mixin ImageEditorMixin {
  Future<File> compressImage(File file) async {
    try {
      final extension = path.extension(file.path);
      final targetPath = path.join(
        path.dirname(file.path),
        '${path.basenameWithoutExtension(file.path)}_compressed$extension',
      );
      final compressedXFile = await _compressImage(file, targetPath);
      if (compressedXFile != null) {
        return File(compressedXFile.path);
      }
    } catch (e) {
      printLog('Error compressing image: $e');
    }
    return file;
  }

  Future<XFile?> _compressImage(File file, String targetPath) async {
    final imageBytes = await file.readAsBytes();
    final originalImage = img.decodeImage(imageBytes);

    if (originalImage == null) {
      printLog('Failed to decode image.');
      return null;
    }

    final originalWidth = originalImage.width;
    final originalHeight = originalImage.height;
    final longerSide =
        originalWidth > originalHeight ? originalWidth : originalHeight;
    printLog('Original width: $originalWidth, height: $originalHeight');

    double scaleFactor;
    if (longerSide >= 4000) {
      scaleFactor = 5.0;
    } else if (longerSide >= 3000) {
      scaleFactor = 4.0;
    } else if (longerSide >= 2000) {
      scaleFactor = 3.0;
    } else if (longerSide >= 1000) {
      scaleFactor = 2.0;
    } else {
      scaleFactor = 1.5;
    }

    final scaledWidth = (originalWidth / scaleFactor).round();
    final scaledHeight = (originalHeight / scaleFactor).round();
    printLog('Scaled width: $scaledWidth, height: $scaledHeight');

    var result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 90,
      minWidth: scaledWidth,
      minHeight: scaledHeight,
    );

    final originalSize = file.lengthSync();
    final compressedSize = await result?.length() ?? 0;

    printLog(
        'Original size: ${(originalSize / (1024 * 1024)).toStringAsFixed(2)}MB');
    printLog(
        'Compressed size: ${(compressedSize / (1024 * 1024)).toStringAsFixed(2)}MB');

    if (compressedSize >= originalSize) {
      printLog('Compression equal or greater than original size');
      return XFile(file.path);
    }

    return result;
  }
}
