import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

abstract class ImageTextRecognitionService {
  Future<String> recognizeText(String imagePath);
}

class GoogleMlKitImageTextRecognitionService
    implements ImageTextRecognitionService {
  @override
  Future<String> recognizeText(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognizedText = await recognizer.processImage(inputImage);
      return recognizedText.text.trim();
    } finally {
      await recognizer.close();
    }
  }
}
