package com.google_mlkit_barcode_scanning

import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import java.io.ByteArrayOutputStream

class ISLIDecoderHandler {
    companion object {
        init {
            System.loadLibrary("isli_icon_decoder")
        }

        @JvmStatic
        external fun nativeInit()

        @JvmStatic
        external fun nativeDecode(
            pixels: ByteArray, w: Int, h: Int, bpl: Int
        ): Map<String, Any>?

        @JvmStatic
        external fun nativeUninit()
    }

    private var initialized = false
    private val instances = mutableSetOf<String>()

    fun init(id: String) {
        if (!initialized) {
            nativeInit()
            initialized = true
        }
        instances.add(id)
    }

    fun decode(imageData: Map<String, Any>): Map<String, Any>? {
        if (!initialized) {
            nativeInit()
            initialized = true
        }
        val gray = convertToGrayscale(imageData) ?: return null
        return nativeDecode(gray.pixels, gray.width, gray.height, gray.bytesPerLine)
    }

    fun close(id: String) {
        instances.remove(id)
        if (instances.isEmpty() && initialized) {
            nativeUninit()
            initialized = false
        }
    }

    private data class GrayImage(
        val pixels: ByteArray,
        val width: Int,
        val height: Int,
        val bytesPerLine: Int
    )

    private fun convertToGrayscale(imageData: Map<String, Any>): GrayImage? {
        val type = imageData["type"] as? String ?: return null

        return when (type) {
            "bytes" -> convertBytesToGrayscale(imageData)
            "bitmap" -> convertBitmapToGrayscale(imageData)
            "file" -> convertFileToGrayscale(imageData)
            else -> null
        }
    }

    private fun convertBytesToGrayscale(imageData: Map<String, Any>): GrayImage? {
        val metadata = imageData["metadata"] as? Map<String, Any> ?: return null
        val bytes = imageData["bytes"] as? ByteArray ?: return null
        val width = (metadata["width"] as? Number)?.toInt() ?: return null
        val height = (metadata["height"] as? Number)?.toInt() ?: return null
        val imageFormat = (metadata["image_format"] as? Number)?.toInt() ?: return null

        // NV21 format: Y plane is the first width*height bytes
        if (imageFormat == ImageFormat.NV21 || imageFormat == 17) {
            val grayPixels = ByteArray(width * height)
            System.arraycopy(bytes, 0, grayPixels, 0, width * height)
            return GrayImage(grayPixels, width, height, width)
        }

        // YUV_420_888 or YV12: extract Y plane
        if (imageFormat == ImageFormat.YV12 || imageFormat == 842094169 ||
            imageFormat == 35 // YUV_420_888
        ) {
            val grayPixels = ByteArray(width * height)
            System.arraycopy(bytes, 0, grayPixels, 0, width * height)
            return GrayImage(grayPixels, width, height, width)
        }

        // For other formats, try converting via YuvImage
        return try {
            val yuvImage = YuvImage(bytes, imageFormat, width, height, null)
            val out = ByteArrayOutputStream()
            yuvImage.compressToJpeg(Rect(0, 0, width, height), 100, out)
            val jpegBytes = out.toByteArray()
            convertJpegToGrayscale(jpegBytes)
        } catch (e: Exception) {
            null
        }
    }

    private fun convertBitmapToGrayscale(imageData: Map<String, Any>): GrayImage? {
        val bitmapData = imageData["bitmapData"] as? ByteArray ?: return null
        return convertJpegToGrayscale(bitmapData)
    }

    private fun convertFileToGrayscale(imageData: Map<String, Any>): GrayImage? {
        val path = imageData["path"] as? String ?: return null
        val file = java.io.File(path)
        if (!file.exists()) return null
        val bytes = file.readBytes()
        return convertJpegToGrayscale(bytes)
    }

    private fun convertJpegToGrayscale(jpegBytes: ByteArray): GrayImage? {
        return try {
            val bitmap = android.graphics.BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.size)
                ?: return null
            val width = bitmap.width
            val height = bitmap.height
            val pixels = IntArray(width * height)
            bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

            val grayPixels = ByteArray(width * height)
            for (i in pixels.indices) {
                val p = pixels[i]
                val r = (p shr 16) and 0xFF
                val g = (p shr 8) and 0xFF
                val b = p and 0xFF
                grayPixels[i] = ((r * 77 + g * 150 + b * 29) shr 8).toByte()
            }
            bitmap.recycle()
            GrayImage(grayPixels, width, height, width)
        } catch (e: Exception) {
            null
        }
    }
}
