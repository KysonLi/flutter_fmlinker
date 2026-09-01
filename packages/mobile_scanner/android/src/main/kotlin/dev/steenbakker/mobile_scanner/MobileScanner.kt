package dev.steenbakker.mobile_scanner

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Size
import android.graphics.SurfaceTexture
import android.view.Surface
import androidx.annotation.VisibleForTesting
import androidx.camera.camera2.Camera2Config
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.CameraXConfig
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ExperimentalLensFacing
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import androidx.camera.core.TorchState
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.google_mlkit_barcode_scanning.ISLIDecoderHandler
import com.google_mlkit_barcode_scanning.ISLILineDecoderHandler
import dev.steenbakker.mobile_scanner.objects.BarcodeFormats
import dev.steenbakker.mobile_scanner.objects.DetectionSpeed
import dev.steenbakker.mobile_scanner.objects.MobileScannerErrorCodes
import dev.steenbakker.mobile_scanner.objects.MobileScannerStartParameters
import dev.steenbakker.mobile_scanner.utils.YuvToRgbConverter
import dev.steenbakker.mobile_scanner.utils.serialize
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.Executors
import kotlin.math.roundToInt

class MobileScanner(
    private val activity: Activity,
    private val textureRegistry: TextureRegistry,
    private val mobileScannerCallback: MobileScannerCallback,
    private val mobileScannerErrorCallback: MobileScannerErrorCallback,
    private val deviceOrientationListener: DeviceOrientationListener,
    private val barcodeScannerFactory: (options: BarcodeScannerOptions?) -> BarcodeScanner = ::defaultBarcodeScannerFactory,
) {

    init {
        configureCameraProcessProvider()
    }

    /// Internal variables
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var cameraSelector: CameraSelector? = null
    private var preview: Preview? = null
    private var surfaceTextureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var scanner: BarcodeScanner? = null
    private var lastScanned: List<String?>? = null
    private var scannerTimeout = false
    private var displayListener: DisplayManager.DisplayListener? = null

    /// 自定义 ISLI 图标码解码器（与 MLKit 并行运行）
    private val isliDecoder = ISLIDecoderHandler()
    private val isliInstanceId = "mobile_scanner"

    /// 自定义 ISLI 线性码（1D）解码器（与 MLKit 并行运行）
    private val isliLineDecoder = ISLILineDecoderHandler()

    /// ISLI 线性码解码器开关。
    /// 默认关闭，因为 libisli_line_decoder.so 存在 native 崩溃（SIGSEGV @ nativeDecode+204）。
    /// 如需启用，在 start() 之后设置为 true。
    @Volatile
    var isliLineDecoderEnabled: Boolean = false

    /// ISLI 图标码（2D）解码开关，由 setISLIMode(icon:) 控制，与 iOS 对齐。
    @Volatile
    var isliIconEnabled: Boolean = true

    /// ISLI 线性码（1D）解码开关，由 setISLIMode(line:) 控制，与 iOS 对齐。
    /// 与 isliLineDecoderEnabled（解码器初始化可用性）分离：此开关只控制是否参与本帧解码。
    @Volatile
    var isliLineEnabled: Boolean = true

    /// 是否保存解码 Y 平面图片到缓存目录（PGM 格式），用于排查解码失败原因。
    /// 默认开启。如不需要，手动设为 false 以减少磁盘 I/O。
    @Volatile
    var yPlaneDumpEnabled: Boolean = false

    // 单帧解码统一串行链：MLKit(~tens ms) → ISLI 图标码(~70ms) → ISLI 线性码(~2s)。
    // 三者共享同一个单线程 executor，按顺序串行执行，任意一个成功即 post 回调并跳过
    // 剩余解码器。线性码单帧 ~2s，必须异步跑且在忙时直接丢帧，否则会阻塞 ImageAnalysis
    // 线程导致预览卡顿。decodeBusy 保证同一时刻只有一帧解码在飞。
    //
    // 两个 native decoder 各自非线程安全，但在同一个单线程上顺序调用是安全的
    //（icon 走 isliDecoder，line 走 isliLineDecoder，不同实例，永不并发）。
    private val decodeExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "isli-decode").apply { isDaemon = true }
    }
    private val decodeBusy = java.util.concurrent.atomic.AtomicBoolean(false)

    /// The in-flight MLKit latch, tracked so [releaseCamera] can unblock a decode
    /// that is waiting on it when the scanner is closed mid-decode on stop().
    /// `@Volatile` because it is set on the decode executor and read on the main thread.
    @Volatile
    private var pendingMlKitLatch: java.util.concurrent.CountDownLatch? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    /// Configurable variables
    var scanWindow: List<Float>? = null
    private var invertImage: Boolean = false
    private var detectionSpeed: DetectionSpeed = DetectionSpeed.NO_DUPLICATES
    private var detectionTimeout: Long = 250
    private var returnImage = false
    private var isPaused = false

    /// Requested barcode formats from Dart side.
    /// null means all formats (including ISLI/ISLI line).
    /// If non-null, ISLI/ISLI line decoding only runs when the corresponding format is in this list.
    private var requestedFormats: List<Int>? = null

    /// Whether [requestedFormats] contains the ISLI icon-code format (8192).
    private fun shouldDecodeIsli(formats: List<Int>?): Boolean {
        return formats == null  || formats.isEmpty() || formats.contains(BarcodeFormats.ISLI_FORMAT)
    }

    /// Whether [requestedFormats] contains the ISLI line-code format (16384).
    private fun shouldDecodeIsliLine(formats: List<Int>?): Boolean {
        return formats == null || formats.isEmpty() || formats.contains(BarcodeFormats.ISLI_LINE_FORMAT)
    }

    companion object {
        /// Maximum time (seconds) to wait for an MLKit `BarcodeScanner.process` Task
        /// to complete. Bounds the decode executor so a scanner closed mid-decode
        /// cannot block it forever. See [awaitMlKit].
        private const val MLKIT_AWAIT_TIMEOUT_SECONDS = 5L

        // Configure the `ProcessCameraProvider` to only log errors.
        // This prevents the informational log spam from CameraX.
        private fun configureCameraProcessProvider() {
            try {
                val config = CameraXConfig.Builder.fromConfig(Camera2Config.defaultConfig()).apply {
                    setMinimumLoggingLevel(Log.ERROR)
                }
                ProcessCameraProvider.configureInstance(config.build())
            } catch (_: IllegalStateException) {
                // The ProcessCameraProvider was already configured.
                // Do nothing.
            }
        }

        /**
         * Create a barcode scanner from the given options.
         */
        fun defaultBarcodeScannerFactory(options: BarcodeScannerOptions?) : BarcodeScanner {
            return if (options == null) BarcodeScanning.getClient() else BarcodeScanning.getClient(options)
        }
    }

    /**
     * callback for the camera. Every frame is passed through this function.
     */
    // 解码计时统计：每 30 帧打印一次 analyzer 平均耗时，便于排查"卡顿/慢"问题。
    private var isliFrameCount = 0
    private var analyzerTotalNs = 0L

    @ExperimentalGetImage
    val captureOutput = ImageAnalysis.Analyzer { imageProxy -> // YUV_420_888 format
        val analyzerStartNs = System.nanoTime()
        val mediaImage = imageProxy.image ?: return@Analyzer

        // ---- Hoisted dimensions (shared across all decode paths) ----
        val width = mediaImage.width
        val height = mediaImage.height
        val sensorRotation = camera?.cameraInfo?.sensorRotationDegrees ?: 0
        val proxyRotation = imageProxy.imageInfo.rotationDegrees
        // displayRotation = sensorRotation (hardware rotation to device orientation).
        // Do NOT add proxyRotation — on some CameraX versions it already includes
        // sensor rotation, causing double-counting. sensorRotation alone is the
        // guaranteed rotation from raw sensor output to upright device view.
        val displayRotation = if (sensorRotation > 0) sensorRotation else proxyRotation
        val portrait = sensorRotation % 180 == 0
        val cbWidth = if (portrait) width else height
        val cbHeight = if (portrait) height else width
        val window = scanWindow  // local snapshot for lambda capture

        // ---- Y-plane: extract once when any ISLI decoder is active ----
        val needIsliY = !invertImage &&
            (shouldDecodeIsli(requestedFormats) || (shouldDecodeIsliLine(requestedFormats) && isliLineDecoderEnabled))
        val doCrop = window != null && window.size >= 4 && !invertImage
        var croppedY: CroppedYPlane? = null
        var yBytesForAll: ByteArray? = null
        if (doCrop) {
            yBytesForAll = extractYPlane(mediaImage)
            if (yBytesForAll != null) {
                croppedY = cropYPlaneToScanWindow(
                    yBytesForAll, width, height, proxyRotation, cbWidth, cbHeight, window!!
                )
            }
        } else if (needIsliY) {
            // No crop but ISLI needs Y-plane: extract once, share between icon and line decoders
            yBytesForAll = extractYPlane(mediaImage)
        }
        val useCropped = croppedY != null

        // ---- MLKit InputImage (cropped when scanWindow is active) ----
        val inputImage = if (invertImage) {
            invertInputImage(imageProxy)
        } else if (useCropped) {
            val crop = croppedY!!
            val nv21 = buildNv21FromY(crop.bytes, crop.width, crop.height)
            InputImage.fromByteArray(nv21, crop.width, crop.height, proxyRotation, InputImage.IMAGE_FORMAT_NV21)
        } else {
            InputImage.fromMediaImage(mediaImage, proxyRotation)
        }

        // NORMAL 节流：仍在上一帧的超时窗口内 → 丢帧。scannerTimeout 只在真正派发链路时才置位。
        if (detectionSpeed == DetectionSpeed.NORMAL && scannerTimeout) {
            imageProxy.close()
            return@Analyzer
        }

        // ---- 单帧解码串行链：MLKit → ISLI 图标码 → ISLI 线性码 ----
        // 三者在同一个 decodeExecutor 单线程上顺序执行，任一成功即 post 回调并跳过剩余解码器。
        // 线性码单帧 ~2s，忙时（上一帧仍在解码）直接丢这一帧，避免队列堆积拖慢预览。
        val doIcon = shouldDecodeIsli(requestedFormats) && isliIconEnabled && !invertImage
        val doLine = shouldDecodeIsliLine(requestedFormats) && isliLineDecoderEnabled && isliLineEnabled && !invertImage

        val dispatched = decodeBusy.compareAndSet(false, true)
        if (dispatched) {
            // NORMAL 节流窗口随本次派发开启：detectionTimeout 后放行下一帧。
            if (detectionSpeed == DetectionSpeed.NORMAL) {
                scannerTimeout = true
                Handler(Looper.getMainLooper()).postDelayed({ scannerTimeout = false }, detectionTimeout)
            }

            // 捕获链路所需的局部快照（decode 线程不直接读可变字段）
            val chainScanner = scanner
            val chainUseCropped = useCropped
            val chainCroppedY = croppedY
            val chainYAll = yBytesForAll
            val chainWindow = window
            val chainSensorW = width
            val chainSensorH = height
            val chainProxyRotation = proxyRotation
            val chainDisplayRotation = displayRotation
            val chainCbW = cbWidth
            val chainCbH = cbHeight
            val chainMediaImage = mediaImage
            val chainInputImage = inputImage
            try {
                decodeExecutor.execute {
                    try {
                        // ---- 统一旋转预处理（ISLI 共用）----
                        // scanWindow 关闭且任一 ISLI 解码器在全帧上工作时，把 Y 平面按 proxyRotation 预旋转到
                        // 显示朝向一次，icon 与 line 共用这份 displayY——各传 rotationDegrees=0（rotateY(0) 为恒等），
                        // 避免同一帧被 icon、line 各 rotateY 一次。line 的 S3 取 (0+90)=90°，与原先
                        // (proxyRotation+90) 位级等价（旋转与对比度拉伸可交换 → S2/S3 结果 bit-exact）。
                        // 统一用 proxyRotation：与 line/MLKit 同值；displayRotation 仅保留给 dump 用。
                        // scanWindow 开启时不预旋转——line 的 S1 需在 sensor 空间做 canvas→sensor 裁剪映射。
                        val displayY: RotatedPlane? =
                            if (chainWindow == null && chainYAll != null && (doIcon || doLine))
                                rotateY(chainYAll, chainSensorW, chainSensorH, chainProxyRotation)
                            else null

                        // ---- Step 1: ISLI 线性码（1D）----
                        // 仅用已提取的 Y 平面（needIsliY 在 doLine 时已保证 chainYAll 非空）。
                        if (doLine && chainYAll != null) {
                            // 首个成功即终止（first-success-wins）：线性码命中时跳过 icon/MLKit。
                            // scanWindow 激活时复用 preamble 的统一裁剪（chainCroppedY），不再在
                            // decodeIsliLineAsync 内重复裁剪。displayY 非空 → 已预旋转，传 0；否则传 sensor + proxyRotation。
                            val preCrop = chainCroppedY   // scanWindow 激活并裁剪成功时非空，否则 null
                            val lineHit = if (displayY != null) {
                                decodeIsliLineAsync(
                                    displayY.bytes, displayY.width, displayY.height,
                                    0, chainDisplayRotation, chainCbW, chainCbH, preCrop,
                                )
                            } else {
                                decodeIsliLineAsync(
                                    chainYAll, chainSensorW, chainSensorH,
                                    chainProxyRotation, chainDisplayRotation, chainCbW, chainCbH, preCrop,
                                )
                            }
                            if (lineHit) {
                                // 回调已在 tryDecodeIsliLineCore → mainHandler.post 完成，
                                // imageProxy 由 finally 统一关闭。
                                return@execute
                            }
                        }

                        // ---- Step 2: ISLI 图标码（2D）----
                        if (doIcon) {
                            val iconMap = when {
                                chainUseCropped && chainCroppedY != null ->
                                    // 裁剪路径：解码 sensor 朝向（native 定位器四向扫描，朝向鲁棒），
                                    // 用 proxyRotation 做特征点 sensor→canvas 回正（与裁剪时同值）。
                                    tryDecodeIsliFromCroppedY(chainCroppedY, chainProxyRotation)
                                displayY != null ->
                                    // 全帧路径：复用预旋转的 displayY，rotationDegrees=0（rotateY 恒等）。
                                    tryDecodeIsliFromYPlane(displayY.bytes, displayY.width, displayY.height, 0)
                                chainYAll != null ->
                                    tryDecodeIsliFromYPlane(chainYAll, chainSensorW, chainSensorH, chainProxyRotation)
                                else -> null
                            }
                            if (iconMap != null) {
                                mainHandler.post { mobileScannerCallback(listOf(iconMap), null, chainCbW, chainCbH) }
                                return@execute
                            }
                        }
                        // ---- Step 3: MLKit（async Task，用 latch 等待）----
                        val mlkitBarcodes: List<Barcode> =
                            if (chainScanner != null) awaitMlKit(chainScanner.process(chainInputImage))
                            else emptyList()
                        val mlkitMaps = if (mlkitBarcodes.isNotEmpty()) {
                            buildMlkitMaps(
                                mlkitBarcodes, chainUseCropped, chainCroppedY, chainWindow,
                                chainSensorW, chainSensorH, chainProxyRotation, imageProxy,
                            )
                        } else {
                            emptyList()
                        }
                        if (mlkitMaps.isNotEmpty()) {
                            // 首个成功 → 投递（returnImage 位图在此用 mediaImage 构建，必须先于 close）→ 终止链路。
                            deliverMlkitResult(mlkitBarcodes, mlkitMaps, chainMediaImage, chainCbW, chainCbH)
                            imageProxy.close()
                            return@execute
                        }

                        // MLKit 未命中：MLKit 与 returnImage 都不再需要 mediaImage，尽早释放相机缓冲，
                        // 避免在 ~2s 的线性码解码期间占用 image buffer。此后 Step 2/3 只用已拷贝的 Y 平面。
                        imageProxy.close()




                    } catch (e: Exception) {
                        Log.e("isliperf", "decode chain error", e)
                    } finally {
                        // imageProxy 通常已在 MLKit 步骤后关闭；此处为异常路径兜底（close 幂等，重复调用安全）。
                        runCatching { imageProxy.close() }
                        decodeBusy.set(false)
                    }
                }
            } catch (e: java.util.concurrent.RejectedExecutionException) {
                // dispose() 在 CAS 成功与本派发之间关闭了 executor：兜底释放本帧资源。
                runCatching { imageProxy.close() }
                decodeBusy.set(false)
            }
        } else {
            // 上一帧仍在解码中：丢这一帧（正常运行状态，不打日志避免刷屏）
            imageProxy.close()
        }
    }

    /**
     * Create a {@link Preview.SurfaceProvider} that specifies how to provide a {@link Surface} to a
     * {@code Preview}.
     */
    @VisibleForTesting
    fun createSurfaceProvider(surfaceTextureEntry: TextureRegistry.SurfaceTextureEntry): Preview.SurfaceProvider {
        return Preview.SurfaceProvider {
            request: SurfaceRequest ->
            run {
                // Flutter 3.7's SurfaceTextureEntry has no SurfaceProducer lifecycle callback,
                // so the invalidate-on-cleanup path from the 3.16 SurfaceProducer API is not
                // reproduced here. Size the backing SurfaceTexture to the requested resolution.
                surfaceTextureEntry.surfaceTexture()
                    .setDefaultBufferSize(request.resolution.width, request.resolution.height)

                val surface = Surface(surfaceTextureEntry.surfaceTexture())

                // The single thread executor is only used to invoke the result callback.
                // Thus it is safe to use a new executor,
                // instead of reusing the executor that is passed to the camera process provider.
                request.provideSurface(surface, Executors.newSingleThreadExecutor()) {
                    // Handle the result of the request for a surface.
                    // See: https://developer.android.com/reference/androidx/camera/core/SurfaceRequest.Result

                    // Always attempt a release.
                    surface.release()

                    val resultCode: Int = it.resultCode

                    when(resultCode) {
                        SurfaceRequest.Result.RESULT_REQUEST_CANCELLED,
                        SurfaceRequest.Result.RESULT_WILL_NOT_PROVIDE_SURFACE,
                        SurfaceRequest.Result.RESULT_SURFACE_ALREADY_PROVIDED,
                        SurfaceRequest.Result.RESULT_SURFACE_USED_SUCCESSFULLY -> {
                            // Only need to release, do nothing.
                        }
                        SurfaceRequest.Result.RESULT_INVALID_SURFACE -> {
                            // The surface was invalid, so it is not clear how to recover from this.
                        }
                        else -> {
                            // Fallthrough, in case any result codes are added later.
                        }
                    }
                }
            }
        }
    }

    @ExperimentalLensFacing
    private fun getCameraLensFacing(camera: Camera?): Int? {
        return when(camera?.cameraInfo?.lensFacing) {
            CameraSelector.LENS_FACING_BACK -> 1
            CameraSelector.LENS_FACING_FRONT -> 0
            CameraSelector.LENS_FACING_EXTERNAL -> 2
            CameraSelector.LENS_FACING_UNKNOWN -> null
            else -> null
        }
    }

    private fun rotateBitmap(bitmap: Bitmap, degrees: Float): Bitmap {
        val matrix = Matrix()
        matrix.postRotate(degrees)
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }

    // Scales the scanWindow to the provided inputImage and checks if that scaled
    // scanWindow contains the barcode.
    @VisibleForTesting
    fun isBarcodeInScanWindow(
        scanWindow: List<Float>,
        barcode: Barcode,
        inputImage: ImageProxy
    ): Boolean {
        // TODO: use `cornerPoints` instead, since the bounding box is not bound to the coordinate system of the input image
        // On iOS we do this correctly, so the calculation should match that.
        val barcodeBoundingBox = barcode.boundingBox ?: return false

        try {
            // MLKit boundingBox is in the InputImage coordinate system (which accounts for rotation).
            // scanWindow fractions are relative to the user-facing canvas dimensions.
            val rotation = inputImage.imageInfo.rotationDegrees
            val portrait = rotation % 180 == 0
            val canvasWidth = if (portrait) inputImage.width else inputImage.height
            val canvasHeight = if (portrait) inputImage.height else inputImage.width

            val left = (scanWindow[0] * canvasWidth).roundToInt()
            val top = (scanWindow[1] * canvasHeight).roundToInt()
            val right = (scanWindow[2] * canvasWidth).roundToInt()
            val bottom = (scanWindow[3] * canvasHeight).roundToInt()

            val scaledScanWindow = Rect(left, top, right, bottom)

            return scaledScanWindow.contains(barcodeBoundingBox)
        } catch (exception: IllegalArgumentException) {
            // Rounding of the scan window dimensions can fail, due to encountering NaN.
            // If we get NaN, rather than give a false positive, just return false.
            return false
        }
    }

    /**
     * Checks whether the center of ISLI feature points falls within the scanWindow.
     *
     * Unlike MLKit barcodes, the native ISLI decoder does not expose a bounding box.
     * We use the center of the feature points (endpoints of the barcode) as a proxy.
     *
     * Canvas dimensions are derived from the sensor dimensions and rotation,
     * matching the convention in [isBarcodeInScanWindow].
     */
    private fun isIsliInScanWindow(
        scanWindow: List<Float>,
        corners: List<Map<String, Any?>>?,
        sensorWidth: Int,
        sensorHeight: Int,
        rotationDegrees: Int,
    ): Boolean {
        if (corners.isNullOrEmpty()) return false
        try {
            // Compute center of feature points in sensor coordinates
            val cx = corners.mapNotNull { (it["x"] as? Number)?.toDouble() }.average()
            val cy = corners.mapNotNull { (it["y"] as? Number)?.toDouble() }.average()

            // Map sensor → canvas coordinates, matching isBarcodeInScanWindow convention.
            val portrait = rotationDegrees % 180 == 0
            val canvasW = if (portrait) sensorWidth else sensorHeight
            val canvasH = if (portrait) sensorHeight else sensorWidth
            val (ux, uy) = when (((rotationDegrees % 360) + 360) % 360) {
                90  -> cy to (sensorHeight - 1.0 - cx)
                180 -> (sensorWidth - 1.0 - cx) to (sensorHeight - 1.0 - cy)
                270 -> (sensorWidth - 1.0 - cy) to cx
                else -> cx to cy // 0°
            }

            val left = (scanWindow[0] * canvasW).roundToInt()
            val top = (scanWindow[1] * canvasH).roundToInt()
            val right = (scanWindow[2] * canvasW).roundToInt()
            val bottom = (scanWindow[3] * canvasH).roundToInt()

            return ux.roundToInt() in left..right && uy.roundToInt() in top..bottom
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * Simplified variant for points already in user-facing (rotated) coordinates.
     * Used by the async ISLI line-code path where [rotateY] has already been applied.
     */
    private fun isIsliInScanWindowRotated(
        scanWindow: List<Float>,
        corners: List<Map<String, Any?>>?,
        canvasWidth: Int,
        canvasHeight: Int,
    ): Boolean {
        if (corners.isNullOrEmpty()) return false
        try {
            val cx = corners.mapNotNull { (it["x"] as? Number)?.toDouble() }.average()
            val cy = corners.mapNotNull { (it["y"] as? Number)?.toDouble() }.average()

            val left = (scanWindow[0] * canvasWidth).roundToInt()
            val top = (scanWindow[1] * canvasHeight).roundToInt()
            val right = (scanWindow[2] * canvasWidth).roundToInt()
            val bottom = (scanWindow[3] * canvasHeight).roundToInt()

            return cx.roundToInt() in left..right && cy.roundToInt() in top..bottom
        } catch (_: Exception) {
            return false
        }
    }

    /**
     * Maps [scanWindow] from canvas (user-facing) coordinates back to sensor coordinates
     * and extracts the corresponding sub-rectangle from the Y-plane.
     *
     * The scanWindow is defined as fractions of the canvas (cbWidth × cbHeight).
     * This function reverses the rotation to find the corresponding sensor region,
     * extracts it, and returns the cropped Y-plane together with the canvas offset
     * needed to map decoded feature points back to full-canvas coordinates.
     *
     * Returns null if the mapped region is empty or out of bounds.
     */
    private data class CroppedYPlane(
        val bytes: ByteArray,
        val width: Int,
        val height: Int,
        val canvasOffsetX: Int,
        val canvasOffsetY: Int,
        val sensorOffsetX: Int,
        val sensorOffsetY: Int,
    )

    private fun cropYPlaneToScanWindow(
        yBytes: ByteArray,
        sensorWidth: Int,
        sensorHeight: Int,
        rotationDegrees: Int,
        canvasWidth: Int,
        canvasHeight: Int,
        scanWindow: List<Float>,
    ): CroppedYPlane? {
        val cL = (scanWindow[0] * canvasWidth).roundToInt().coerceIn(0, canvasWidth)
        val cT = (scanWindow[1] * canvasHeight).roundToInt().coerceIn(0, canvasHeight)
        val cR = (scanWindow[2] * canvasWidth).roundToInt().coerceIn(0, canvasWidth)
        val cB = (scanWindow[3] * canvasHeight).roundToInt().coerceIn(0, canvasHeight)
        if (cL >= cR || cT >= cB) return null

        // Map canvas rect [cL, cT, cR, cB] → sensor rect [sX, sY, sW, sH]
        val sX: Int
        val sY: Int
        val sW: Int
        val sH: Int
        when (((rotationDegrees % 360) + 360) % 360) {
            90 -> {
                // canvas(cx,cy) → sensor(sx=cy, sy=sensorH-1-cx)
                sX = cT
                sY = sensorHeight - cR
                sW = cB - cT
                sH = cR - cL
            }
            270 -> {
                // canvas(cx,cy) → sensor(sx=sensorW-1-cy, sy=cx)
                sX = sensorWidth - cB
                sY = cL
                sW = cB - cT
                sH = cR - cL
            }
            180 -> {
                // canvas(cx,cy) → sensor(sx=sensorW-1-cx, sy=sensorH-1-cy)
                sX = sensorWidth - cR
                sY = sensorHeight - cB
                sW = cR - cL
                sH = cB - cT
            }
            else -> {
                // 0° — direct mapping
                sX = cL
                sY = cT
                sW = cR - cL
                sH = cB - cT
            }
        }

        // Clamp to sensor bounds
        val sx0 = sX.coerceIn(0, sensorWidth)
        val sy0 = sY.coerceIn(0, sensorHeight)
        val sx1 = (sX + sW).coerceIn(0, sensorWidth)
        val sy1 = (sY + sH).coerceIn(0, sensorHeight)
        val croppedW = sx1 - sx0
        val croppedH = sy1 - sy0
        if (croppedW <= 0 || croppedH <= 0) return null

        // Extract cropped region: row-by-row copy from the packed Y-plane
        val cropped = ByteArray(croppedW * croppedH)
        for (row in 0 until croppedH) {
            val srcOffset = (sy0 + row) * sensorWidth + sx0
            System.arraycopy(yBytes, srcOffset, cropped, row * croppedW, croppedW)
        }

        return CroppedYPlane(cropped, croppedW, croppedH, cL, cT, sx0, sy0)
    }

    /**
     * Build an NV21 byte array from a Y-plane and gray (0x80) UV plane.
     * The output is sized width * height * 3 / 2, suitable for both MLKit
     * InputImage.fromByteArray and ISLI native decoders.
     */
    private fun buildNv21FromY(yBytes: ByteArray, width: Int, height: Int): ByteArray {
        val ySize = width * height
        val nv21Size = ySize * 3 / 2
        val nv21 = ByteArray(nv21Size)
        System.arraycopy(yBytes, 0, nv21, 0, ySize)
        nv21.fill(0x80.toByte(), ySize, nv21Size)
        return nv21
    }

    /**
     * Map a point from sensor coordinates to canvas (user-facing) coordinates.
     *
     * Sensor: mediaImage.width × mediaImage.height (typically landscape).
     * Canvas: what the user sees after applying rotationDegrees.
     * Supports 0/90/180/270 degree rotations.
     */
    private fun sensorToCanvas(
        sx: Double, sy: Double,
        sensorWidth: Int, sensorHeight: Int,
        rotationDegrees: Int,
    ): Pair<Double, Double> {
        val r = ((rotationDegrees % 360) + 360) % 360
        return when (r) {
            90  -> sy to (sensorHeight - 1.0 - sx)
            180 -> (sensorWidth - 1.0 - sx) to (sensorHeight - 1.0 - sy)
            270 -> (sensorWidth - 1.0 - sy) to sx
            else -> sx to sy  // 0°
        }
    }

    /**
     * Offset an MLKit barcode's coordinates from a cropped InputImage back to
     * full-canvas coordinates.
     *
     * MLKit returns cornerPoints and boundingBox in the InputImage's coordinate
     * system. Since the InputImage was built from a sensor-cropped NV21, the
     * coordinates are in cropped-sensor space. This function:
     * 1. Adds sensorOffset to get full-sensor coordinates
     * 2. Maps sensor → canvas using rotation
     * Returns a new barcode data map with corrected coordinates.
     */
    private fun offsetMlKitBarcodeData(
        barcode: Barcode,
        crop: CroppedYPlane,
        sensorWidth: Int,
        sensorHeight: Int,
        rotationDegrees: Int,
    ): Map<String, Any?> {
        val data = barcode.data.toMutableMap()

        // Offset cornerPoints: cropped-sensor → full-sensor → canvas
        @Suppress("UNCHECKED_CAST")
        val corners = data["corners"] as? List<Map<String, Any?>>
        if (corners != null) {
            data["corners"] = corners.map { corner ->
                val cx = (corner["x"] as? Number)?.toDouble() ?: 0.0
                val cy = (corner["y"] as? Number)?.toDouble() ?: 0.0
                val (canvasX, canvasY) = sensorToCanvas(
                    cx + crop.sensorOffsetX, cy + crop.sensorOffsetY,
                    sensorWidth, sensorHeight, rotationDegrees,
                )
                mapOf<String, Any?>("x" to canvasX, "y" to canvasY)
            }
        }

        return data
    }

    /**
     * 在 decode 线程上阻塞等待 MLKit [com.google.android.gms.tasks.Task] 完成。
     *
     * MLKit 的 `process()` 是异步的，串行链需要把它的结果"拉直"成同步语义。失败按
     * "无条码"处理（让链路继续尝试 ISLI），而不是直接回调错误——避免 MLKit 瞬时失败
     * 却掩盖了 ISLI 可能的成功。
     */
    private fun awaitMlKit(task: com.google.android.gms.tasks.Task<List<Barcode>>): List<Barcode> {
        val latch = java.util.concurrent.CountDownLatch(1)
        pendingMlKitLatch = latch
        val result = java.util.concurrent.atomic.AtomicReference<List<Barcode>>(emptyList())
        task.addOnSuccessListener { barcodes ->
            result.set(barcodes ?: emptyList())
            latch.countDown()
        }.addOnFailureListener { e ->
            Log.d("isliperf", "MLKit process failed, continuing to ISLI: ${e.message}")
            latch.countDown()
        }
        try {
            // Bound the wait: if the scanner is closed mid-decode (stop() during analysis),
            // MLKit may abandon the in-flight Task without invoking either listener. Without
            // a timeout the single-thread decode executor would block here forever, pinning
            // decodeBusy=true and silently dropping every frame after re-entry.
            if (!latch.await(MLKIT_AWAIT_TIMEOUT_SECONDS, java.util.concurrent.TimeUnit.SECONDS)) {
                Log.w("isliperf", "MLKit process did not complete within ${MLKIT_AWAIT_TIMEOUT_SECONDS}s, continuing to ISLI")
            }
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
        } finally {
            pendingMlKitLatch = null
        }
        return result.get()
    }

    /**
     * 把 MLKit 返回的条码列表构造成回调用的 map 列表，应用 scanWindow 偏移/过滤
     * （逻辑搬自原 captureOutput 内联循环）。必须在 imageProxy 关闭前调用——
     * `isBarcodeInScanWindow` 会读取 imageProxy 的旋转角/尺寸。
     */
    private fun buildMlkitMaps(
        barcodes: List<Barcode>,
        useCropped: Boolean,
        croppedY: CroppedYPlane?,
        window: List<Float>?,
        width: Int,
        height: Int,
        proxyRotation: Int,
        imageProxy: ImageProxy,
    ): List<Map<String, Any?>> {
        val barcodeMap: MutableList<Map<String, Any?>> = mutableListOf()
        for (barcode in barcodes) {
            when {
                useCropped && croppedY != null -> {
                    // Barcode coords are in cropped-sensor space; offset to full canvas.
                    barcodeMap.add(offsetMlKitBarcodeData(barcode, croppedY, width, height, proxyRotation))
                }
                window == null -> {
                    barcodeMap.add(barcode.data)
                }
                else -> {
                    // Crop failed; fallback to full-image decode + scanWindow filter.
                    if (isBarcodeInScanWindow(window, barcode, imageProxy)) {
                        barcodeMap.add(barcode.data)
                    }
                }
            }
        }
        return barcodeMap
    }

    /**
     * MLKit 命中后的投递：NO_DUPLICATES 去重 + 可选 returnImage 位图 + mainHandler 回调。
     *
     * 链路在调用方已因 MLKit 非空而终止；这里只负责"是否真的回调"——重复帧抑制回调，
     * 但不影响"跳过 ISLI"的决策。位图改为同步构建（当前已在 decode 后台线程，不再另起协程，
     * 避免 imageProxy 在位图完成前被关闭）。必须在 imageProxy 关闭前调用。
     *
     * 去重使用完整的 MLKit 条码列表（与原逻辑一致），而非 scanWindow 过滤后的列表。
     */
    private fun deliverMlkitResult(
        barcodes: List<Barcode>,
        maps: List<Map<String, Any?>>,
        mediaImage: android.media.Image,
        cbWidth: Int,
        cbHeight: Int,
    ) {
        if (detectionSpeed == DetectionSpeed.NO_DUPLICATES) {
            val newScannedBarcodes = barcodes.mapNotNull { it.rawValue }.sorted()
            if (newScannedBarcodes == lastScanned) {
                // 与上一帧重复：抑制回调（链路已由调用方终止）
                return
            } else if (newScannedBarcodes.isNotEmpty()) {
                lastScanned = newScannedBarcodes
            }
        }

        if (!returnImage) {
            mainHandler.post { mobileScannerCallback(maps, null, cbWidth, cbHeight) }
            return
        }

        val payload = buildReturnImagePayload(mediaImage)
        if (payload != null) {
            mainHandler.post { mobileScannerCallback(maps, payload.byteArray, payload.width, payload.height) }
        } else {
            // 位图构建失败：回退为不带图回调，确保条码不丢
            mainHandler.post { mobileScannerCallback(maps, null, cbWidth, cbHeight) }
        }
    }

    private data class ReturnImagePayload(val byteArray: ByteArray, val width: Int, val height: Int)

    /**
     * 同步构建 returnImage 的 PNG 位图载荷（搬自原 captureOutput 的 IO 协程，去掉了
     * imageProxy.close() 与 mobileScannerCallback——前者由链路负责，后者由调用方 post）。
     * 失败返回 null。
     */
    private fun buildReturnImagePayload(mediaImage: android.media.Image): ReturnImagePayload? {
        var imageFormat: YuvToRgbConverter? = null
        var bmResult: Bitmap? = null
        var bmCropped: Bitmap? = null
        return try {
            val bitmap = Bitmap.createBitmap(mediaImage.width, mediaImage.height, Bitmap.Config.ARGB_8888)
            imageFormat = YuvToRgbConverter(activity.applicationContext)
            imageFormat.yuvToRgb(mediaImage, bitmap)

            bmResult = rotateBitmap(bitmap, camera?.cameraInfo?.sensorRotationDegrees?.toFloat() ?: 90f)

            // Crop to scanWindow if set. scanWindow fractions are relative to
            // the rotated (canvas / user-facing) bitmap dimensions.
            val window = scanWindow
            val finalBm: Bitmap
            if (window != null && window.size >= 4) {
                val left = (window[0] * bmResult.width).roundToInt().coerceIn(0, bmResult.width)
                val top = (window[1] * bmResult.height).roundToInt().coerceIn(0, bmResult.height)
                val right = (window[2] * bmResult.width).roundToInt().coerceIn(0, bmResult.width)
                val bottom = (window[3] * bmResult.height).roundToInt().coerceIn(0, bmResult.height)
                val cropW = right - left
                val cropH = bottom - top
                if (cropW > 0 && cropH > 0) {
                    bmCropped = Bitmap.createBitmap(bmResult, left, top, cropW, cropH)
                }
            }
            finalBm = bmCropped ?: bmResult

            val stream = ByteArrayOutputStream()
            finalBm.compress(Bitmap.CompressFormat.PNG, 100, stream)
            val byteArray = stream.toByteArray()

            ReturnImagePayload(byteArray, finalBm.width, finalBm.height)
        } catch (e: Exception) {
            Log.e("isliperf", "build return image failed", e)
            null
        } finally {
            // Recycle: when cropped, bmResult and bmCropped are separate bitmaps;
            // when not cropped, finalBm is bmResult — recycle bmResult once, plus the crop if present.
            bmResult?.recycle()
            bmCropped?.recycle()
            imageFormat?.release()
        }
    }

    /**
     * Decode ISLI icon from a pre-cropped Y plane.
     *
     * 与 line 解码器旋转处理一致：先把 sensor-crop 按 [rotationDegrees] 旋转到显示朝向再解码
     *（native icon 定位器四向扫描，朝向鲁棒，转与不转都能解）。命中后角点已在「显示裁剪空间」，
     * 用 [offsetFeaturePoints] 按 crop 的 canvasOffset 平移到全画布空间——与 line 完全相同。
     */
    private fun tryDecodeIsliFromCroppedY(
        crop: CroppedYPlane,
        rotationDegrees: Int,
    ): Map<String, Any?>? {
        return try {
            // 与 line 一致：sensor-crop → 显示朝向（post-rotateY = native 输入）。
            val rotated = rotateY(crop.bytes, crop.width, crop.height, rotationDegrees)
            val nv21 = buildNv21FromY(rotated.bytes, rotated.width, rotated.height)
            val imageData = mapOf<String, Any>(
                "type" to "bytes",
                "bytes" to nv21,
                "metadata" to mapOf<String, Any>(
                    "width" to rotated.width,
                    "height" to rotated.height,
                    "image_format" to ImageFormat.NV21,
                ),
            )
            val result = isliDecoder.decode(imageData)
            if (result == null) {
                dumpIconYPlane(rotated.bytes, rotated.width, rotated.height, false, null, 0)
                return null
            }
            val isliCode = result["isliCode"] as? String
            dumpIconYPlane(rotated.bytes, rotated.width, rotated.height, true, isliCode, 0)
            val barcodeMap = buildIsliBarcodeData(result, BarcodeFormats.ISLI.intValue) ?: return null
            // 显示空间平移：display-crop 角点 + canvasOffset = 全画布坐标（与 line 的 offsetFeaturePoints 一致）。
            offsetFeaturePoints(barcodeMap, crop.canvasOffsetX, crop.canvasOffsetY)
        } catch (e: Exception) {
            Log.e("islicode", "isli cropped decode error", e)
            null
        }
    }

    /**
     * Start barcode scanning by initializing the camera and barcode scanner.
     */
    @ExperimentalLensFacing
    @ExperimentalGetImage
    fun start(
        barcodeScannerOptions: BarcodeScannerOptions?,
        returnImage: Boolean,
        cameraPosition: CameraSelector,
        torch: Boolean,
        detectionSpeed: DetectionSpeed,
        torchStateCallback: TorchStateCallback,
        zoomScaleStateCallback: ZoomScaleStateCallback,
        mobileScannerStartedCallback: MobileScannerStartedCallback,
        mobileScannerErrorCallback: (exception: Exception) -> Unit,
        detectionTimeout: Long,
        cameraResolutionWanted: Size?,
        invertImage: Boolean,
        formats: List<Int>? = null,
    ) {
        this.detectionSpeed = detectionSpeed
        this.detectionTimeout = detectionTimeout
        this.returnImage = returnImage
        this.invertImage = invertImage
        this.requestedFormats = formats

        // 当 formats 包含 ISLI 线性码 (16384) 或全部格式 (null) 时自动启用解码器，
        // 避免 Dart 侧遗漏设置 isliLineDecoderEnabled = true
        if (shouldDecodeIsliLine(formats) && !isliLineDecoderEnabled) {
            isliLineDecoderEnabled = true
            Log.i("isliperf", "auto-enabled isliLineDecoder (format 16384 in requestedFormats)")
        }

        // 启动时输出解码配置状态，方便确认各项解码能力是否已启用
        Log.i(
            "isliperf",
            "start: formats=${
                if (formats == null) "ALL" else formats.joinToString(",")
            } " +
                "isliIcon=${
                    shouldDecodeIsli(formats)
                } isliLine=${
                    shouldDecodeIsliLine(formats)
                } " +
                "lineDecoderEnabled=$isliLineDecoderEnabled invert=$invertImage"
        )

        if (camera?.cameraInfo != null && preview != null && surfaceTextureEntry != null && !isPaused) {

// TODO: resume here for seamless transition
//            if (isPaused) {
//                resumeCamera()
//                val cameraDirection = getCameraLensFacing(camera)
//                mobileScannerStartedCallback(
//                  MobileScannerStartParameters(
//                    if (portrait) width else height,
//                    if (portrait) height else width,
//                    deviceOrientationListener.getUIOrientation().serialize(),
//                    sensorRotationDegrees,
//                    surfaceProducer!!.handlesCropAndRotation(),
//                    currentTorchState,
//                    surfaceProducer!!.id(),
//                    numberOfCameras ?: 0,
//                    cameraDirection
//                  )
//                )
//                return
//            }
            mobileScannerErrorCallback(AlreadyStarted())

            return
        }

        lastScanned = null
        scanner = barcodeScannerFactory(barcodeScannerOptions)
        isliDecoder.init(isliInstanceId)
        isliLineDecoder.init(isliInstanceId)

        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity)
        val executor = ContextCompat.getMainExecutor(activity)

        cameraProviderFuture.addListener({
            cameraProvider = cameraProviderFuture.get()
            val numberOfCameras = cameraProvider?.availableCameraInfos?.size

            if (cameraProvider == null) {
                mobileScannerErrorCallback(CameraError())

                return@addListener
            }

            cameraProvider?.unbindAll()
            surfaceTextureEntry = surfaceTextureEntry ?: textureRegistry.createSurfaceTexture()
            val surfaceProvider: Preview.SurfaceProvider = createSurfaceProvider(surfaceTextureEntry!!)

            // Preview

            // Build the preview to be shown on the Flutter texture
            val previewBuilder = Preview.Builder()
            preview = previewBuilder.build().apply { setSurfaceProvider(surfaceProvider) }

            // Build the analyzer to be passed on to MLKit
            val analysisBuilder = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            val displayManager = activity.applicationContext.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

            val cameraResolution =  cameraResolutionWanted ?: Size(1920, 1080)

            val selectorBuilder = ResolutionSelector.Builder()
            selectorBuilder.setResolutionStrategy(
                ResolutionStrategy(
                    cameraResolution,
                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                )
            )
            analysisBuilder.setResolutionSelector(selectorBuilder.build()).build()

            if (displayListener == null) {
                displayListener = object : DisplayManager.DisplayListener {
                    override fun onDisplayAdded(displayId: Int) {}

                    override fun onDisplayRemoved(displayId: Int) {}

                    override fun onDisplayChanged(displayId: Int) {
                        val selector = ResolutionSelector.Builder().setResolutionStrategy(
                            ResolutionStrategy(
                                cameraResolution,
                                ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                            )
                        )
                        analysisBuilder.setResolutionSelector(selector.build()).build()
                    }
                }

                displayManager.registerDisplayListener(
                    displayListener, null,
                )
            }

            val analysis = analysisBuilder.build().apply { setAnalyzer(executor, captureOutput) }

            try {
                camera = cameraProvider?.bindToLifecycle(
                    activity as LifecycleOwner,
                    cameraPosition,
                    preview,
                    analysis
                )
                cameraSelector = cameraPosition
            } catch(exception: Exception) {
                mobileScannerErrorCallback(NoCamera())

                return@addListener
            }

            camera?.let {
                // Register the torch listener
                it.cameraInfo.torchState.observe(activity as LifecycleOwner) { state ->
                    // TorchState.OFF = 0; TorchState.ON = 1
                    torchStateCallback(state)
                }

                // Register the zoom scale listener
                it.cameraInfo.zoomState.observe(activity) { state ->
                    zoomScaleStateCallback(state.linearZoom.toDouble())
                }

                // Enable torch if provided
                if (it.cameraInfo.hasFlashUnit()) {
                    it.cameraControl.enableTorch(torch)
                }
            }

            val resolution = analysis.resolutionInfo!!.resolution
            val width = resolution.width.toDouble()
            val height = resolution.height.toDouble()
            val sensorRotationDegrees = camera?.cameraInfo?.sensorRotationDegrees ?: 0
            val portrait = sensorRotationDegrees % 180 == 0
            val cameraDirection = getCameraLensFacing(camera)

            // Start with 'unavailable' torch state.
            var currentTorchState: Int = -1

            camera?.cameraInfo?.let {
                if (!it.hasFlashUnit()) {
                    return@let
                }

                currentTorchState = it.torchState.value ?: -1
            }

            deviceOrientationListener.start()

            mobileScannerStartedCallback(
                MobileScannerStartParameters(
                    if (portrait) width else height,
                    if (portrait) height else width,
                    deviceOrientationListener.getUIOrientation().serialize(),
                    sensorRotationDegrees,
                    true, // SurfaceTexture's transform matrix is applied by the Flutter engine
                          // when sampling the texture, so crop and rotation are already handled
                          // by the surface (same as SurfaceProducer.handlesCropAndRotation() == true).
                          // Setting false would make the Dart side wrap the texture in RotatedPreview,
                          // double-rotating the already-upright preview by 90°.
                    currentTorchState,
                    surfaceTextureEntry!!.id(),
                    numberOfCameras ?: 0,
                    cameraDirection,
                )
            )
        }, executor)

    }

    /**
     * Pause barcode scanning.
     */
    fun pause(force: Boolean = false) {
        if (!force) {
            if (isPaused) {
                throw AlreadyPaused()
            } else if (isStopped()) {
                throw AlreadyStopped()
            }
        }

        deviceOrientationListener.stop()
        pauseCamera()
    }

    /**
     * Stop barcode scanning.
     */
    fun stop(force: Boolean = false) {
        if (!force) {
            if (!isPaused && isStopped()) {
                throw AlreadyStopped()
            }
        }

        deviceOrientationListener.stop()
        releaseCamera()
    }

    private fun pauseCamera() {
        // Pause camera by unbinding all use cases
        cameraProvider?.unbindAll()
        isPaused = true
    }

//    private fun resumeCamera() {
//        // Resume camera by rebinding use cases
//        cameraProvider?.let { provider ->
//            val owner = activity as LifecycleOwner
//            cameraSelector?.let { provider.bindToLifecycle(owner, it, preview) }
//        }
//        isPaused = false
//    }

    private fun releaseCamera() {
        if (displayListener != null) {
            val displayManager = activity.applicationContext.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

            displayManager.unregisterDisplayListener(displayListener)
            displayListener = null
        }

        val owner = activity as LifecycleOwner
        // Release the camera observers first.
        camera?.cameraInfo?.let {
            it.torchState.removeObservers(owner)
            it.zoomState.removeObservers(owner)
            it.cameraState.removeObservers(owner)
        }

        // Unbind the camera use cases, the preview is a use case.
        // The camera will be closed when the last use case is unbound.
        cameraProvider?.unbindAll()

        // Release the surface for the preview.
        surfaceTextureEntry?.release()
        surfaceTextureEntry = null

        // Release the scanner.
        scanner?.close()
        scanner = null
        // Unblock any in-flight MLKit wait so the decode executor drains and
        // decodeBusy resets now, instead of staying pinned until the awaitMlKit
        // timeout fires after re-entry.
        pendingMlKitLatch?.countDown()
        lastScanned = null

        // NOTE: the icon (2D) and line (1D) native decoders are intentionally NOT
        // closed here. Both run on the single decodeExecutor; a line decode takes
        // ~2s. Calling nativeUninit() while a decode is in flight frees the BCH
        // lookup tables (__bch_ctrl127) the decode thread still dereferences in
        // decode_bch() → SIGSEGV (fault 0x8). Their native state (small BCH tables)
        // is cheap to retain across stop/start cycles, and is torn down — strictly
        // after draining the decode thread — in dispose() via shutdownDecoders(),
        // which submits both close() calls onto decodeExecutor (single-thread FIFO).
    }

    private fun isStopped() = camera == null && preview == null

    /**
     * Toggles the flash light on or off.
     */
    fun toggleTorch() {
        camera?.let {
            if (!it.cameraInfo.hasFlashUnit()) {
                return@let
            }

            when(it.cameraInfo.torchState.value) {
                TorchState.OFF -> it.cameraControl.enableTorch(true)
                TorchState.ON -> it.cameraControl.enableTorch(false)
            }
        }
    }

    /**
     * Inverts the image colours respecting the alpha channel
     */
    @ExperimentalGetImage
    fun invertInputImage(imageProxy: ImageProxy): InputImage {
        val image = imageProxy.image ?: throw IllegalArgumentException("Image is null")

        // Convert YUV_420_888 image to RGB Bitmap
        val bitmap = Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888)
        try {
            val imageFormat = YuvToRgbConverter(activity.applicationContext)
            imageFormat.yuvToRgb(image, bitmap)

            // Create an inverted bitmap
            val invertedBitmap = invertBitmapColors(bitmap)
            imageFormat.release()

            return InputImage.fromBitmap(invertedBitmap, imageProxy.imageInfo.rotationDegrees)
        } finally {
            // Release resources
            bitmap.recycle() // Free up bitmap memory
            // NOTE: imageProxy 的关闭由调用方（captureOutput 解码链 finally）统一负责，
            // 这里不关闭，避免重复 close（ImageProxy.close 幂等，但单一所有权更清晰）。
        }
    }

    // Efficiently invert bitmap colors using ColorMatrix
    private fun invertBitmapColors(bitmap: Bitmap): Bitmap {
        val colorMatrix = ColorMatrix().apply {
            set(floatArrayOf(
                -1f, 0f, 0f, 0f, 255f,  // Red
                0f, -1f, 0f, 0f, 255f,  // Green
                0f, 0f, -1f, 0f, 255f,  // Blue
                0f, 0f, 0f, 1f, 0f      // Alpha
            ))
        }
        val paint = Paint().apply { colorFilter = ColorMatrixColorFilter(colorMatrix) }

        val invertedBitmap = Bitmap.createBitmap(bitmap.width, bitmap.height, bitmap.config!!)
        val canvas = Canvas(invertedBitmap)
        canvas.drawBitmap(bitmap, 0f, 0f, paint)

        return invertedBitmap
    }

    /**
     * Analyze a single image.
     */
    fun analyzeImage(
        image: Uri,
        scannerOptions: BarcodeScannerOptions?,
        onSuccess: AnalyzerSuccessCallback,
        onError: AnalyzerErrorCallback,
        scanWindow: List<Float>? = null,
        formats: List<Int>? = null) {
        val inputImage: InputImage

        try {
            if (scanWindow != null && scanWindow.size >= 4) {
                // Crop the image to the scan window region before decoding.
                // Use ContentResolver to handle both file:// and content:// URIs.
                val inputStream = activity.contentResolver.openInputStream(image)
                val options = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeStream(inputStream, null, options)
                inputStream?.close()
                val imgWidth = options.outWidth
                val imgHeight = options.outHeight

                Log.d("MobileScanner", "analyzeImage crop: path=${image.path}, " +
                    "scanWindow=$scanWindow, imgSize=${imgWidth}x$imgHeight")

                if (imgWidth > 0 && imgHeight > 0) {
                    val left = (scanWindow[0] * imgWidth).toInt().coerceIn(0, imgWidth)
                    val top = (scanWindow[1] * imgHeight).toInt().coerceIn(0, imgHeight)
                    val right = (scanWindow[2] * imgWidth).toInt().coerceIn(0, imgWidth)
                    val bottom = (scanWindow[3] * imgHeight).toInt().coerceIn(0, imgHeight)

                    val cropWidth = right - left
                    val cropHeight = bottom - top

                    if (cropWidth > 0 && cropHeight > 0) {
                        // Re-open stream to read the full bitmap
                        val fullStream = activity.contentResolver.openInputStream(image)
                        val fullBitmap = BitmapFactory.decodeStream(fullStream)
                        fullStream?.close()
                        if (fullBitmap != null) {
                            val croppedBitmap = Bitmap.createBitmap(fullBitmap, left, top, cropWidth, cropHeight)
                            if (croppedBitmap != fullBitmap) {
                                fullBitmap.recycle()
                            }
                            inputImage = InputImage.fromBitmap(croppedBitmap, 0)
                            Log.d("MobileScanner", "analyzeImage: cropped to ${cropWidth}x$cropHeight at ($left,$top)")
                        } else {
                            Log.d("MobileScanner", "analyzeImage: decodeStream returned null, falling back")
                            inputImage = InputImage.fromFilePath(activity, image)
                        }
                    } else {
                        Log.d("MobileScanner", "analyzeImage: crop dimensions invalid, falling back to full image")
                        inputImage = InputImage.fromFilePath(activity, image)
                    }
                } else {
                    Log.d("MobileScanner", "analyzeImage: could not read image bounds, falling back to full image")
                    inputImage = InputImage.fromFilePath(activity, image)
                }
            } else {
                Log.d("MobileScanner", "analyzeImage: no scanWindow, using full image")
                inputImage = InputImage.fromFilePath(activity, image)
            }
        } catch (error: IOException) {
            onError(MobileScannerErrorCodes.ANALYZE_IMAGE_NO_VALID_IMAGE_ERROR_MESSAGE)

            return
        }

        // Use a short lived scanner instance, which is closed when the analysis is done.
        val barcodeScanner: BarcodeScanner = barcodeScannerFactory(scannerOptions)

        // 静态图同步运行 ISLI 解码——仅当请求的编码格式中包含对应格式时才解码。
        val isliBarcodeMap: Map<String, Any?>? = if (shouldDecodeIsli(formats)) tryDecodeIsliFromFile(image) else null
        val isliLineBarcodeMap: Map<String, Any?>? = if (shouldDecodeIsliLine(formats)) tryDecodeIsliLineFromFile(image) else null

        barcodeScanner.process(inputImage).addOnSuccessListener { barcodes ->
            val barcodeMap = barcodes.map { barcode -> barcode.data }.toMutableList()

            if (isliBarcodeMap != null) {
                barcodeMap.add(isliBarcodeMap)
            }
            if (isliLineBarcodeMap != null) {
                barcodeMap.add(isliLineBarcodeMap)
            }

            onSuccess(barcodeMap)
        }.addOnFailureListener { e ->
            // MLKit 失败但 ISLI 命中——仍然把 ISLI 结果回传，避免错失
            val fallback = mutableListOf<Map<String, Any?>>()
            isliBarcodeMap?.let { fallback.add(it) }
            isliLineBarcodeMap?.let { fallback.add(it) }
            if (fallback.isNotEmpty()) {
                onSuccess(fallback)
            } else {
                onError(e.localizedMessage ?: e.toString())
            }
        }.addOnCompleteListener {
            barcodeScanner.close()
        }
    }

    /**
     * 从 CameraX 的 [android.media.Image]（YUV_420_888）中提取 Y 平面，调用 ISLI 解码器。
     *
     * 注意：planes[0] 的 rowStride 可能 != width（CameraX 会按 16/32 字节对齐），
     * 必须按行紧凑拷贝到一个 width*height 的 ByteArray，否则解码会错位失败。
     *
     * 失败一律返回 null（不抛异常），避免打断 MLKit 主流程。
     *
     * @param preExtractedYBytes 如果调用方已从同一帧提取了 Y 平面，可传入避免重复拷贝。
     *   尺寸必须 == width * height，且 buffer position 已经对到第一行起点。
     */
    /**
     * ISLI 图标码解码核心 — 接收已提取的 Y 平面，旋转至显示方向后调用 native 解码。
     * 纯函数（除 dump 外无副作用），可在线程池中运行。
     */
    private fun tryDecodeIsliFromYPlane(yBytes: ByteArray, width: Int, height: Int, rotationDegrees: Int): Map<String, Any?>? {
        return try {
            // Rotate Y-plane from sensor orientation to display orientation.
            val rotated = rotateY(yBytes, width, height, rotationDegrees)
            val yPixels = rotated.bytes
            val rw = rotated.width
            val rh = rotated.height

            val nv21 = buildNv21FromY(yPixels, rw, rh)
            val imageData = mapOf<String, Any>(
                "type" to "bytes",
                "bytes" to nv21,
                "metadata" to mapOf<String, Any>(
                    "width" to rw,
                    "height" to rh,
                    "image_format" to ImageFormat.NV21,
                ),
            )
            val result = isliDecoder.decode(imageData)
            if (result == null) {
                dumpIconYPlane(yPixels, rw, rh, false, null, 0)
                return null
            }
            val isliCode = result["isliCode"] as? String
            dumpIconYPlane(yPixels, rw, rh, true, isliCode, 0)
            buildIsliBarcodeData(result, BarcodeFormats.ISLI.intValue)
        } catch (e: Exception) {
            Log.e("islicode", "icon decode error", e)
            null
        }
    }

    /**
     * 从静态文件路径调用 ISLI 解码器。
     */
    private fun tryDecodeIsliFromFile(uri: Uri): Map<String, Any?>? {
        val path = uri.path ?: return null
        return try {
            val imageData = mapOf<String, Any>(
                "type" to "file",
                "path" to path,
            )
            val result = isliDecoder.decode(imageData) ?: return null
            buildIsliBarcodeData(result, BarcodeFormats.ISLI.intValue)
        } catch (e: Exception) {
            Log.e("islicode", "decode isli code error", e)
            null
        }
    }

    /**
     * 从 CameraX 的 [android.media.Image]（YUV_420_888）拷出 Y 平面到一个 width*height 的紧凑数组。
     * 必须在 imageProxy 仍持有的时候调用（即 analyzer 线程同步路径）。
     *
     * 与 [tryDecodeIsliFromImage] 内部的拷贝逻辑保持一致：
     * - rowStride == width：直接相对 get
     * - rowStride != width：逐行绝对定位拷贝（CameraX 16/32 字节对齐场景）
     *
     * 失败返回 null，调用方丢这一帧。
     */
    private fun extractYPlane(mediaImage: android.media.Image): ByteArray? {
        return try {
            val width = mediaImage.width
            val height = mediaImage.height
            val plane = mediaImage.planes[0]
            val buffer = plane.buffer
            val rowStride = plane.rowStride

            // 与图标码解码器共享同一个 buffer，前一次相对 get 已推进 position，必须 rewind
            buffer.rewind()

            val extractStartNs = System.nanoTime()
            val yBytes = ByteArray(width * height)
            if (rowStride == width) {
                buffer.get(yBytes, 0, width * height)
            } else {
                val row = ByteArray(rowStride)
                var dstOffset = 0
                for (i in 0 until height) {
                    buffer.position(i * rowStride)
                    val remaining = buffer.remaining().coerceAtMost(rowStride)
                    buffer.get(row, 0, remaining)
                    System.arraycopy(row, 0, yBytes, dstOffset, width.coerceAtMost(remaining))
                    dstOffset += width
                }
            }
            yBytes
        } catch (e: Exception) {
            Log.e("isliline", "extract y-plane error", e)
            null
        }
    }

    /**
     * Min-max normalize Y-plane pixel values to the full 0-255 range.
     *
     * In dim/backlit conditions the Y-plane may only use a narrow band (e.g. 80-170).
     * Stretching ensures the native decoder's binarization threshold can reliably
     * separate bars from background.
     *
     * Cost: ~1ms for 1080p (two passes). Returns null if the image is uniform.
     */
    private fun contrastStretchY(yBytes: ByteArray): ByteArray? {
        var min = 255
        var max = 0
        for (v in yBytes) {
            val p = v.toInt() and 0xFF
            if (p < min) min = p
            if (p > max) max = p
        }
        if (max <= min) return null
        val range = max - min
        val result = ByteArray(yBytes.size)
        for (i in yBytes.indices) {
            val p = yBytes[i].toInt() and 0xFF
            result[i] = (((p - min) * 255.0) / range + 0.5).toInt().toByte()
        }
        return result
    }

    /**
     * 同步调用 ISLI 线性码 native 解码器（命中后通过 mainHandler 回调到主线程）。
     *
     *
     *（[decodeExecutor] 单线程）中被调用，由 [decodeBusy] 保证不会并发。
     *
     * @param yBytes Y 平面紧凑数组（sensor 原始坐标系）
     * @param width / height sensor 原始尺寸
     * @param rotationDegrees ImageProxy 报告的旋转角（0/90/180/270），把 sensor 帧转正到用户视角
     * @param cbWidth / cbHeight 回调到 Dart 的旋转后画面尺寸
     */
    /**
     * Core decode attempt: rotate, build NV21, call native, stats, dump, callback.
     *
     * @return true if decode succeeded (callback was posted), false on miss.
     */
    private fun tryDecodeIsliLineCore(
        yBytes: ByteArray,
        yWidth: Int, yHeight: Int,
        rotationDegrees: Int,          // rotation for native decode (sensor orientation)
        displayRotation: Int,          // rotation for dump (display orientation)
        canvasOffsetX: Int, canvasOffsetY: Int,
        isCropped: Boolean,
        cbWidth: Int, cbHeight: Int,
        strategy: String,
    ): Boolean {
        // ---- Rotate ----
        val rotated = rotateY(yBytes, yWidth, yHeight, rotationDegrees)

        // ---- NV21 + Native decode ----
        val nv21 = buildNv21FromY(rotated.bytes, rotated.width, rotated.height)
        val imageData = mapOf<String, Any>(
            "type" to "bytes", "bytes" to nv21,
            "metadata" to mapOf("width" to rotated.width, "height" to rotated.height, "image_format" to ImageFormat.NV21),
        )
        val result = try {
            isliLineDecoder.decode(imageData)
        } catch (e: Exception) {
            Log.e("isliline", "[$strategy] decode error", e)
            null
        }

        if (result == null) {
            // dump 解码器真正收到的图（rotated = post-rotateY = native 输入），而非 displayRotation 渲染的误导图。
            // 文件名带 strategy+rotationDegrees，便于和日志对照判断朝向是否正确。
            dumpYPlane(rotated.bytes, rotated.width, rotated.height, false, null, 0, "${strategy}_rot${rotationDegrees}")
            return false
        }

        val isliCode = result["isliCode"] as? String
        dumpYPlane(rotated.bytes, rotated.width, rotated.height, true, isliCode, 0, "${strategy}_rot${rotationDegrees}")

        // ---- Build barcode data + offset coordinates ----
        var barcodeMap = buildIsliBarcodeData(result, BarcodeFormats.ISLI_LINE.intValue) ?: return false
        if (canvasOffsetX != 0 || canvasOffsetY != 0) {
            barcodeMap = offsetFeaturePoints(barcodeMap, canvasOffsetX, canvasOffsetY)
        }

        // ---- ScanWindow filter (full-image strategies only) ----
        if (!isCropped) {
            val window = scanWindow
            if (window != null && window.size >= 4) {
                @Suppress("UNCHECKED_CAST")
                val corners = barcodeMap["corners"] as? List<Map<String, Any?>>
                if (!isIsliInScanWindowRotated(window, corners, cbWidth, cbHeight)) {
                    Log.d("isliline", "[$strategy] hit but outside scanWindow, skipping")
                    return false
                }
            }
        }

        // ---- Post callback ----
        mainHandler.post {
            mobileScannerCallback(listOf(barcodeMap), null, cbWidth, cbHeight)
        }
        return true
    }

    /**
     * ISLI linear-code async decode cascade with three strategies:
     *   S1: cropped to scanWindow → S2: full image, normal orientation
     *   → S3: full image, +90° rotation (emulates decode_portrait for Android).
     *
     * @return true if any strategy decoded successfully (callback posted via mainHandler),
     *         false if all three missed.
     *
     * Runs on the serial decode chain (decodeExecutor). Guarded by decodeBusy to prevent concurrent decodes.
     */
    private fun decodeIsliLineAsync(
        yBytes: ByteArray,
        width: Int,
        height: Int,
        rotationDegrees: Int,       // rotation for native decode
        displayRotation: Int,       // rotation for dump (display orientation)
        cbWidth: Int,
        cbHeight: Int,
        preCrop: CroppedYPlane? = null,   // 统一裁剪结果：scanWindow 激活时由 preamble 传入，避免重复裁剪
    ): Boolean {
        val window = scanWindow
        val hasWindow = window != null && window.size >= 4

        // ---- Strategy 1: cropped to scanWindow (if applicable) ----
        // 优先复用 preamble 的统一裁剪 preCrop；否则就地裁剪（scanWindow 激活但 preamble 未裁到的兜底）。
        // 裁剪后只对该区域做 contrast-stretch，避免全图拉伸浪费。
        if (hasWindow) {
            val crop = preCrop ?: cropYPlaneToScanWindow(yBytes, width, height, rotationDegrees, cbWidth, cbHeight, window!!)
            if (crop != null) {
                val cropStretched = contrastStretchY(crop.bytes) ?: crop.bytes
                if (tryDecodeIsliLineCore(cropStretched, crop.width, crop.height,
                        rotationDegrees, displayRotation,
                        crop.canvasOffsetX, crop.canvasOffsetY,
                        true, cbWidth, cbHeight, "S1-crop")) return true
            }
            // scanWindow is active: do NOT fall back to full-image decode.
            // Only the cropped region is of interest.
            Log.w("isliline", "S1-crop failed, scanWindow active — skipping full-image fallback")
            return false
        }

        // ---- Step 0: contrast-stretch (cheap, benefits S2+S3 full-image strategies) ----
        val stretchedY = contrastStretchY(yBytes)
        val workY = stretchedY ?: yBytes

        // ---- Strategy 2: full image, normal orientation ----
        // Only reached when no scanWindow is set.
        if (tryDecodeIsliLineCore(workY, width, height,
                rotationDegrees, displayRotation, 0, 0,
                false, cbWidth, cbHeight, "S2-full")) return true
        Log.w("isliline", "S2-full failed, trying +90° rotation")

        // ---- Strategy 3: full image, +90 degree rotation ----
        // The native decoder only runs decode_landscape on Android, which expects
        // horizontal barcode bars. Rotating 90° in Kotlin gives a second chance
        // for vertically-oriented (portrait) barcodes.
        val altRotation = (rotationDegrees + 90) % 360
        if (tryDecodeIsliLineCore(workY, width, height,
                altRotation, displayRotation, 0, 0,
                false, cbWidth, cbHeight, "S3-full+90")) return true

        // ---- All strategies exhausted ----
        Log.w("isliline", "all strategies exhausted: S2-full, S3-full+90 all missed " +
            "size=${width}x$height rotation=$rotationDegrees")
        val dumpFinal = rotateY(workY, width, height, displayRotation)
  //      dumpYPlane(dumpFinal.bytes, dumpFinal.width, dumpFinal.height, false, null, 0)
        return false
    }

    private data class RotatedPlane(val bytes: ByteArray, val width: Int, val height: Int)

    /**
     * 把 width*height 的 Y 平面按指定角度旋转。仅支持 0/90/180/270，其他角度按 0 处理。
     *
     * 实现是直接的索引映射（无插值，灰度图无所谓）。
     * 1920x1440 单帧 ~10ms 量级，对总耗时（line decode ~2s）可忽略。
     */
    private fun rotateY(src: ByteArray, width: Int, height: Int, rotation: Int): RotatedPlane {
        return when (((rotation % 360) + 360) % 360) {
            90 -> {
                // 顺时针 90°：dst[y, x] = src[H-1-y, x] -> 转为线性：
                //   dst[x][height-1-y] = src[y][x]，新尺寸 height x width
                val dst = ByteArray(width * height)
                val newW = height
                val newH = width
                for (y in 0 until height) {
                    val srcRow = y * width
                    for (x in 0 until width) {
                        dst[x * newW + (newW - 1 - y)] = src[srcRow + x]
                    }
                }
                RotatedPlane(dst, newW, newH)
            }
            180 -> {
                val dst = ByteArray(width * height)
                val total = width * height
                for (i in 0 until total) {
                    dst[total - 1 - i] = src[i]
                }
                RotatedPlane(dst, width, height)
            }
            270 -> {
                // 顺时针 270° = 逆时针 90°：dst[newW-1-x][y] = src[y][x]，新尺寸 height x width
                val dst = ByteArray(width * height)
                val newW = height
                val newH = width
                for (y in 0 until height) {
                    val srcRow = y * width
                    for (x in 0 until width) {
                        dst[(newH - 1 - x) * newW + y] = src[srcRow + x]
                    }
                }
                RotatedPlane(dst, newW, newH)
            }
            else -> RotatedPlane(src, width, height)
        }
    }

    // 每次解码都保存图片到外部缓存，便于排查解码失败原因。
    // 计数器在 decodeExecutor 单线程上递增，无需额外同步。
    // 用 adb pull 拉到本机：
    //   adb pull /sdcard/Android/data/<your.app.id>/cache/isli_line_*.pgm
    //   adb pull /sdcard/Android/data/<your.app.id>/cache/isli_icon_*.pgm
    private var yPlaneDumpCounter = 0
    private var iconDumpCounter = 0
    private val yPlaneDumpMax = 200  // 保留最近 200 帧，超出回绕

    /**
     * 把 Y 平面以 PGM (P5) 格式写到外部缓存目录，每次解码都保存。
     *
     * 文件名格式：isli_line_{HIT|MISS}_{seq}_{code}.pgm
     *   - HIT/MISS：解码成功/失败
     *   - seq：递增序号（0~yPlaneDumpMax-1，超出回绕）
     *   - code：解码结果（HIT 时为 isliCode，MISS 时为 "none"）
     *
     * IrfanView / GIMP / Photoshop / Photopea 都能直接打开 PGM。
     */
    private fun dumpYPlane(yBytes: ByteArray, width: Int, height: Int, success: Boolean, resultCode: String?, decodeTimeMs: Long, label: String = "") {
        if (!yPlaneDumpEnabled) return
        try {
            val dir = activity.externalCacheDir ?: activity.cacheDir
            val status = if (success) "HIT" else "MISS"
            val code = if (success && !resultCode.isNullOrBlank())
                resultCode.take(32).replace(Regex("[\\\\/:*?\"<>|]"), "_")
            else "none"
            val seq = yPlaneDumpCounter % yPlaneDumpMax
            val tag = if (label.isNotEmpty()) "${label}_" else ""
            val name = "isli_line_%05d_${tag}${code}_${decodeTimeMs}ms.pgm".format(seq)
            val file = java.io.File(dir, name)
            file.outputStream().use { out ->
                out.write("P5\n$width $height\n255\n".toByteArray(Charsets.US_ASCII))
                out.write(yBytes)
            }
            Log.d("isliline", "dumped #$yPlaneDumpCounter ${if (success) "HIT" else "MISS"} → ${file.absolutePath} (${width}x$height)")
            yPlaneDumpCounter++
        } catch (e: Exception) {
            Log.e("isliline", "dump y-plane failed", e)
        }
    }

    /**
     * ISLI 图标码（2D）解码 Y 平面 dump，与 [dumpYPlane] 形态一致但使用独立序号和
     * `isli_icon_` 前缀，避免与线性码 dumps 混淆。
     */
    private fun dumpIconYPlane(yBytes: ByteArray, width: Int, height: Int, success: Boolean, resultCode: String?, decodeTimeMs: Long) {
        if (!yPlaneDumpEnabled) return
        try {
            val dir = activity.externalCacheDir ?: activity.cacheDir
            val status = if (success) "HIT" else "MISS"
            val code = if (success && !resultCode.isNullOrBlank())
                resultCode.take(32).replace(Regex("[\\\\/:*?\"<>|]"), "_")
            else "none"
            val seq = iconDumpCounter % yPlaneDumpMax
            val name = "isli_icon_$status%05d_${code}_${decodeTimeMs}ms.pgm".format(seq)
            val file = java.io.File(dir, name)
            file.outputStream().use { out ->
                out.write("P5\n$width $height\n255\n".toByteArray(Charsets.US_ASCII))
                out.write(yBytes)
            }
            Log.d("islicode", "dumped icon #$iconDumpCounter ${if (success) "HIT" else "MISS"} → ${file.absolutePath} (${width}x$height)")
            iconDumpCounter++
        } catch (e: Exception) {
            Log.e("islicode", "dump icon y-plane failed", e)
        }
    }

    /**
     * 从静态文件路径调用 ISLI 线性码解码器。
     */
    private fun tryDecodeIsliLineFromFile(uri: Uri): Map<String, Any?>? {
        val path = uri.path ?: return null
        return try {
            val imageData = mapOf<String, Any>(
                "type" to "file",
                "path" to path,
            )
            val result = isliLineDecoder.decode(imageData) ?: return null
            buildIsliBarcodeData(result, BarcodeFormats.ISLI_LINE.intValue)
        } catch (e: Exception) {
            Log.e("isliline", "decode isli line error", e)
            null
        }
    }

    /**
     * 把 ISLI native 返回的 `{isliCode, featurePoints}` 转换为与 MLKit
     * [com.google.mlkit.vision.barcode.common.Barcode.data] 同形的 map，
     * 这样 Dart 端 [Barcode.fromNative] 不需要分支即可解析。
     *
     * featurePoints 的 x/y 是 Integer，这里转成 Double，与 MLKit cornerPoints 序列化一致。
     *
     * @param format [BarcodeFormats.ISLI.intValue] (图标码) 或 [BarcodeFormats.ISLI_LINE.intValue] (线性码)
     */
    private fun buildIsliBarcodeData(nativeResult: Map<String, Any>, format: Int): Map<String, Any?>? {
        val isliCode = nativeResult["isliCode"] as? String ?: return null
        @Suppress("UNCHECKED_CAST")
        val rawPoints = nativeResult["featurePoints"] as? List<Map<String, Any>>

        val corners = rawPoints?.map { p ->
            mapOf(
                "x" to (p["x"] as? Number)?.toDouble(),
                "y" to (p["y"] as? Number)?.toDouble(),
            )
        }

        return mapOf(
            "calendarEvent" to null,
            "contactInfo" to null,
            "corners" to corners,
            "displayValue" to isliCode,
            "driverLicense" to null,
            "email" to null,
            "format" to format,
            "geoPoint" to null,
            "phone" to null,
            "rawBytes" to null,
            "rawValue" to isliCode,
            "size" to null,
            "sms" to null,
            "type" to Barcode.TYPE_UNKNOWN,
            "url" to null,
            "wifi" to null,
        )
    }

    /**
     * Offsets feature points (corners) in a barcode map by the given canvas offset.
     * Used when the decoded image was cropped via scanWindow — the native decoder
     * returns coordinates relative to the cropped region, but the callback expects
     * full-canvas coordinates.
     */
    private fun offsetFeaturePoints(
        barcodeMap: Map<String, Any?>,
        offsetX: Int,
        offsetY: Int,
    ): Map<String, Any?> {
        @Suppress("UNCHECKED_CAST")
        val corners = barcodeMap["corners"] as? List<Map<String, Any?>> ?: return barcodeMap
        val offset = corners.map { corner ->
            mapOf<String, Any?>(
                "x" to ((corner["x"] as? Number)?.toDouble() ?: 0.0) + offsetX,
                "y" to ((corner["y"] as? Number)?.toDouble() ?: 0.0) + offsetY,
            )
        }
        return barcodeMap.toMutableMap().apply { this["corners"] = offset }
    }

    /**
     * Set the zoom rate of the camera.
     */
    fun setScale(scale: Double) {
        if (scale > 1.0 || scale < 0) throw ZoomNotInRange()
        if (camera == null) throw ZoomWhenStopped()
        camera?.cameraControl?.setLinearZoom(scale.toFloat())
    }

    fun setZoomRatio(zoomRatio: Double) {
        if (camera == null) throw ZoomWhenStopped()
        camera?.cameraControl?.setZoomRatio(zoomRatio.toFloat())
    }

    /**
     * Reset the zoom rate of the camera.
     */
    fun resetScale() {
        if (camera == null) throw ZoomWhenStopped()
        camera?.cameraControl?.setZoomRatio(1f)
    }

    /**
     * Dispose of this scanner instance.
     */
    fun dispose() {
        if (!isStopped()) {
            // Defer to stop(): releases camera, surface, scanner.
            // releaseCamera() no longer uninits the icon/line decoders (see note there).
            stop()
        }
        // Tear down the async decode threads and their native decoders.
        shutdownDecoders()
    }

    private val isliExecutorsStopped = java.util.concurrent.atomic.AtomicBoolean(false)

    /**
     * Shut down the single decode executor and release both native decoders' state.
     *
     * nativeUninit() frees global BCH lookup tables. A nativeDecode() in flight
     * dereferences the freed (null) structures → SIGSEGV (fault addr 0x8). Both
     * close/uninit calls are submitted onto [decodeExecutor] so they serialize
     * strictly behind any in-flight chain decode (single-thread FIFO). Idempotent.
     */
    private fun shutdownDecoders() {
        if (isliExecutorsStopped.getAndSet(true)) return

        // 两个 close 都提交到同一个 decodeExecutor：单线程 FIFO 保证它们严格排在任何
        // 正在运行的链路解码（isliDecoder.decode / isliLineDecoder.decode）之后执行，
        // 保留 BCH 表的 native 安全不变量。
        try {
            decodeExecutor.execute {
                try { isliDecoder.close(isliInstanceId) }
                catch (e: Exception) { Log.e("islicode", "icon close error", e) }
                try { isliLineDecoder.close(isliInstanceId) }
                catch (e: Exception) { Log.e("isliline", "line close error", e) }
            }
        } catch (_: java.util.concurrent.RejectedExecutionException) {
            // executor 已被关闭（如重复 dispose）：直接内联 close。
            try { isliDecoder.close(isliInstanceId) }
            catch (e: Exception) { Log.e("islicode", "icon close error", e) }
            try { isliLineDecoder.close(isliInstanceId) }
            catch (e: Exception) { Log.e("isliline", "line close error", e) }
        }
        decodeExecutor.shutdown()
    }
}
