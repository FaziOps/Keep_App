package io.keepr.app

import android.graphics.BitmapFactory
import androidx.exifinterface.media.ExifInterface
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream

class MainActivity : FlutterActivity() {
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // On-device receipt text recognition with ML Kit. Returns one entry per
        // recognised line with a normalised bounding box (origin top-left).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "io.keepr.app/ocr").setMethodCallHandler { call, result ->
            if (call.method != "recognizeText") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            val bitmap = bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
            if (bytes == null || bitmap == null) {
                result.error("bad_image", "The image could not be decoded.", null)
                return@setMethodCallHandler
            }
            val rotation = try {
                ExifInterface(ByteArrayInputStream(bytes)).rotationDegrees
            } catch (e: Exception) {
                0
            }
            val width = (if (rotation % 180 == 0) bitmap.width else bitmap.height).toDouble()
            val height = (if (rotation % 180 == 0) bitmap.height else bitmap.width).toDouble()

            recognizer.process(InputImage.fromBitmap(bitmap, rotation))
                .addOnSuccessListener { text ->
                    val lines = text.textBlocks.flatMap { it.lines }.mapNotNull { line ->
                        val box = line.boundingBox ?: return@mapNotNull null
                        mapOf(
                            "text" to line.text,
                            "confidence" to line.confidence.toDouble(),
                            "left" to box.left / width,
                            "top" to box.top / height,
                            "width" to box.width() / width,
                            "height" to box.height() / height,
                        )
                    }
                    result.success(lines)
                }
                .addOnFailureListener { e -> result.error("ocr_failed", e.message, null) }
        }
    }
}
