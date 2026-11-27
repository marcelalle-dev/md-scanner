import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:md_scanner/core/errors/failure.dart';
import 'package:md_scanner/core/errors/result.dart';
import 'package:md_scanner/features/ocr/domain/text_recognition.dart';

/// ML Kit text recognition with the bundled Latin model: works offline.
class MlKitTextRecognitionService implements TextRecognitionService {
  TextRecognizer? _recognizer;

  @override
  Future<Result<OcrPage>> recognize(String imagePath) async {
    try {
      final recognizer = _recognizer ??= TextRecognizer(
        script: TextRecognitionScript.latin,
      );
      final result = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return Success(
        OcrPage(
          text: result.text,
          lines: [
            for (final block in result.blocks)
              for (final line in block.lines) line.text,
          ],
        ),
      );
    } on MissingPluginException {
      return const Err(OcrFailure(OcrFailureKind.engineUnavailable));
    } on PlatformException catch (error) {
      return Err(
        OcrFailure(OcrFailureKind.recognitionFailed, debugMessage: error.code),
      );
    }
  }

  @override
  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
