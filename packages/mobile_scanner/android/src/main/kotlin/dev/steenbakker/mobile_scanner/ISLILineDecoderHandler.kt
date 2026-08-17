package com.google_mlkit_barcode_scanning

import android.graphics.Rect
import android.graphics.ImageFormat
import android.graphics.YuvImage
import java.io.ByteArrayOutputStream

/**
 * ISLI 线性码（1D）native 解码器的 Kotlin 包装。
 *
 * 与 [ISLIDecoderHandler]（图标 2D 码）形态一致：
 * - 输入支持 `bytes` / `bitmap` / `file` 三种 imageData。
 * - native 端返回 `Map<String, Any>`，键约定：
 *   - `isliCode`      -> String
 *   - `featurePoints` -> List<Map<String, Int>>（2 个点：x、y）
 *   - `brightness`    -> Int     （0 ~ 255）
 *   - `isBlur`        -> Boolean
 *
 * 提供两种解码入口：
 * - [decode]：全图解码（对应 native `nativeDecode`）
 * - [decodeWindowed]：开窗解码（对应 native `nativeDecodeWindowed`），适合给定 ROI 时使用
 */
class ISLILineDecoderHandler {
    companion object {
        init {
            System.loadLibrary("isli_line_decoder")
        }

        @JvmStatic
        external fun nativeInit()

        @JvmStatic
        external fun nativeUninit()

        @JvmStatic
        external fun nativeClearCache()

        @JvmStatic
        external fun nativeDecode(
            pixels: ByteArray, w: Int, h: Int, bpl: Int
        ): Map<String, Any>?

        @JvmStatic
        external fun nativeDecodeWindowed(
            pixels: ByteArray, w: Int, h: Int, bpl: Int,
            rectX: Int, rectY: Int, rectW: Int, rectH: Int,
            orientation: Int
        ): Map<String, Any>?

        /**
         * 调整 native 解码日志级别（logcat 过滤 tag = `isliline`）。
         * 级别： 0=OFF 1=ERROR 2=WARN 3=INFO 4=DEBUG(默认) 5=VERBOSE。
         * 排查解码流程时设为 4/5；上线/性能测试设为 0 静默。
         */
        @JvmStatic
        external fun nativeSetLogLevel(level: Int)
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

    /**
     * 调整解码日志级别（logcat tag = `isliline`）。
     * 0=OFF 1=ERROR 2=WARN 3=INFO 4=DEBUG(默认) 5=VERBOSE。
     */
    fun setLogLevel(level: Int) {
        nativeSetLogLevel(level)
    }

    fun decode(imageData: Map<String, Any>): Map<String, Any>? {
        if (!initialized) {
            nativeInit()
            initialized = true
        }
        val gray = convertToGrayscale(imageData) ?: return null
        return nativeDecode(gray.pixels, gray.width, gray.height, gray.bytesPerLine)
    }

    /**
     * 带 ROI 的解码。
     *
     * @param rect 解码区域，格式同 native：x/y/w/h（基于灰度图坐标系）。
     * @param orientation 可选 0 / 90 / 270，传给 native。
     */
    fun decodeWindowed(
        imageData: Map<String, Any>,
        rectX: Int, rectY: Int, rectW: Int, rectH: Int,
        orientation: Int
    ): Map<String, Any>? {
        if (!initialized) {
            nativeInit()
            initialized = true
        }
        val gray = convertToGrayscale(imageData) ?: return null
        return nativeDecodeWindowed(
            gray.pixels, gray.width, gray.height, gray.bytesPerLine,
            rectX, rectY, rectW, rectH, orientation
        )
    }

    /** 清空 native 端的累计缓存（例如切换页面 / 重新启动扫描时调用）。 */
    fun clearCache() {
        if (initialized) {
            nativeClearCache()
        }
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
        val metadata = imageData["metadata"] as? Map<*, *> ?: return null
        val bytes = imageData["bytes"] as? ByteArray ?: return null
        val width = (metadata["width"] as? Number)?.toInt() ?: return null
        val height = (metadata["height"] as? Number)?.toInt() ?: return null
        val imageFormat = (metadata["image_format"] as? Number)?.toInt() ?: return null

        // NV21 / YV12 / YUV_420_888 的首平面就是 Y 平面
        if (imageFormat == ImageFormat.NV21 || imageFormat == 17 ||
            imageFormat == ImageFormat.YV12 || imageFormat == 842094169 ||
            imageFormat == 35 // YUV_420_888
        ) {
            val grayPixels = ByteArray(width * height)
            System.arraycopy(bytes, 0, grayPixels, 0, width * height)
            return GrayImage(grayPixels, width, height, width)
        }

        // 其它格式走 YuvImage -> JPEG -> Bitmap -> 灰度
        return try {
            val yuvImage = YuvImage(bytes, imageFormat, width, height, null)
            val out = ByteArrayOutputStream()
            yuvImage.compressToJpeg(Rect(0, 0, width, height), 100, out)
            convertJpegToGrayscale(out.toByteArray())
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
        return convertJpegToGrayscale(file.readBytes())
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
                // 标准 BT.601 灰度系数（与 ISLIDecoderHandler 保持一致）
                grayPixels[i] = ((r * 77 + g * 150 + b * 29) shr 8).toByte()
            }
            bitmap.recycle()
            GrayImage(grayPixels, width, height, width)
        } catch (e: Exception) {
            null
        }
    }
}
