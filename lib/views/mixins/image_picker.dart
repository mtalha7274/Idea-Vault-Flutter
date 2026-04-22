import 'dart:async';

import '../../core/utils/helpers.dart';
import 'package:image_picker/image_picker.dart';

mixin ImagePickerMixin {
  Future<void> pickImageFromGallery(
      {FutureOr<dynamic> Function(XFile)? onImagePicked,
      bool crop = true}) async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        await onImagePicked?.call(image);
      }
    } catch (e) {
      printLog('Error picking image: $e');
    }
  }
}
