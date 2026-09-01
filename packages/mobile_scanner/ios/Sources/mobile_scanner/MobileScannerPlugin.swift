import AVFoundation
import Vision
import VideoToolbox
import Accelerate
import AudioToolbox

import isli_icon_native
import isli_line_native

#if os(iOS)
  import Flutter
  import UIKit
  import MobileCoreServices
#else
  import AppKit
  import FlutterMacOS
#endif

public class MobileScannerPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    let registry: FlutterTextureRegistry
    
    // Sink for publishing event changes
    var sink: FlutterEventSink!

    // Texture id of the camera preview
    var textureId: Int64!

    // Capture session of the camera
    var captureSession: AVCaptureSession?

    // The selected camera
    weak var device: AVCaptureDevice!

    // Image to be sent to the texture
    var latestBuffer: CVImageBuffer!

    // optional window to limit scan search
    var scanWindow: CGRect?

    /// Whether to return the input image with the barcode event.
    /// This is static to avoid accessing `self` in the `VNDetectBarcodesRequest` callback.
    private static var returnImage: Bool = false

    var detectionSpeed: DetectionSpeed = DetectionSpeed.noDuplicates

    var timeoutSeconds: Double = 0

    var symbologies:[VNBarcodeSymbology] = []

    var position = AVCaptureDevice.Position.back

    var standardZoomFactor: CGFloat = 1

#if os(iOS)
    var deviceOrientation: UIDeviceOrientation = UIDeviceOrientation.unknown
#endif

    // ISLI custom decoder support
    var shouldDecodeIsli = false
    var shouldDecodeIsliLine = false

    /// Serial queue for ISLI decode (line ~2s, icon ~70ms).
    /// Both native decoders are NOT thread-safe (global BCH tables);
    /// this queue guarantees exclusive access and FIFO ordering.
    private let isliDecodeQueue = DispatchQueue(label: "mobile_scanner.isli_decode")
    private var isliDecodeBusy = false
    /// Dedicated queue for sample-buffer delivery (kept alive for the session's lifetime).
    private var sampleBufferQueue: DispatchQueue?

    private var stopped: Bool {
        return device == nil || captureSession == nil
    }

    private var paused: Bool {
        return stopped && textureId != nil
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
#if os(iOS)
        let textures = registrar.textures()
        let messenger = registrar.messenger()
#else
        let textures = registrar.textures
        let messenger = registrar.messenger
#endif

        let instance = MobileScannerPlugin(textures)
        let method = FlutterMethodChannel(name:
                                            "dev.steenbakker.mobile_scanner/scanner/method", binaryMessenger: messenger)
        let event = FlutterEventChannel(name:
                                            "dev.steenbakker.mobile_scanner/scanner/event", binaryMessenger: messenger)

        registrar.addMethodCallDelegate(instance, channel: method)
        event.setStreamHandler(instance)
        
#if os(iOS)
        let orientationEvent = FlutterEventChannel(name:
                                            "dev.steenbakker.mobile_scanner/scanner/deviceOrientation", binaryMessenger: messenger)
        orientationEvent.setStreamHandler(DeviceOrientationStreamHandler(onOrientationChanged: instance.setDeviceOrientation))
#endif
    }
    
    init(_ registry: FlutterTextureRegistry) {
        self.registry = registry
        super.init()
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "state":
            checkPermission(call, result)
        case "request":
            requestPermission(call, result)
        case "start":
            start(call, result)
        case "toggleTorch":
            toggleTorch(result)
        case "setScale":
            setScale(call, result)
        case "resetScale":
            resetScale(call, result)
        case "pause":
            pause(call, result)
        case "stop":
            stop(call, result)
        case "updateScanWindow":
            updateScanWindow(call, result)
        case "analyzeImage":
            analyzeImage(call, result)
        case "setISLIMode":
            setISLIMode(call, result)
        case "playScanSound":
            playScanSound(call, result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // FlutterStreamHandler
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }
    
    // FlutterStreamHandler
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
    
    // FlutterTexture
    public func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        if latestBuffer == nil {
            return nil
        }
        return Unmanaged<CVPixelBuffer>.passRetained(latestBuffer)
    }
    
    var nextScanTime = 0.0
    var imagesCurrentlyBeingProcessed = false
    
    // Gets called when a new image is added to the buffer
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Ignore invalid texture id.
        if textureId == nil {
            return
        }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        latestBuffer = imageBuffer
        registry.textureFrameAvailable(textureId)
        
        let currentTime = Date().timeIntervalSince1970
        let eligibleForScan = currentTime > nextScanTime && !imagesCurrentlyBeingProcessed
        if ((detectionSpeed == DetectionSpeed.normal || detectionSpeed == DetectionSpeed.noDuplicates) && eligibleForScan || detectionSpeed == DetectionSpeed.unrestricted) {
            nextScanTime = currentTime + timeoutSeconds
            imagesCurrentlyBeingProcessed = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                if self!.latestBuffer == nil {
                    return
                }
                var cgImage: CGImage?
                VTCreateCGImageFromCVPixelBuffer(self!.latestBuffer, options: nil, imageOut: &cgImage)
                let imageRequestHandler = VNImageRequestHandler(cgImage: cgImage!)
                do {
                    let barcodeRequest: VNDetectBarcodesRequest = VNDetectBarcodesRequest(completionHandler: { [weak self] (request, error) in
                        self?.imagesCurrentlyBeingProcessed = false

                        if error != nil {
                            DispatchQueue.main.async {
                                self?.sink?(FlutterError(
                                    code: MobileScannerErrorCodes.BARCODE_ERROR,
                                    message: error?.localizedDescription, details: nil))
                            }
                            return
                        }

                        guard let results: [VNBarcodeObservation] = request.results as? [VNBarcodeObservation] else {
                            return
                        }

                        if results.isEmpty {
                            return
                        }

                        let barcodes: [VNBarcodeObservation] = results.compactMap({ barcode in
                            return barcode
                        })

                        DispatchQueue.main.async {
                            // If the image is nil, use zero as the size.
                            guard let image = cgImage else {
                                self?.sink?([
                                    "name": "barcode",
                                    "data": barcodes.map({ $0.toMap(imageWidth: 0, imageHeight: 0, scanWindow: nil)}),
                                ])
                                return
                            }

                            // The image dimensions are always provided.
                            // The image bytes are only non-null when `returnImage` is true.
                            let imageData: [String: Any?] = [
                                "bytes": MobileScannerPlugin.returnImage ? FlutterStandardTypedData(bytes: image.jpegData(compressionQuality: 0.8)!) : nil,
                                "width": Double(image.width),
                                "height": Double(image.height),
                            ]

                            self?.sink?([
                                "name": "barcode",
                                "data": barcodes.map({ $0.toMap(imageWidth: image.width, imageHeight: image.height, scanWindow: self?.scanWindow) }),
                                "image": imageData,
                            ])
                        }
                    })

                    if self?.symbologies.isEmpty == false {
                        // Add the symbologies the user wishes to support.
                        barcodeRequest.symbologies = self!.symbologies
                    }

                    // Set the region of interest to match scanWindow
                    if let scanWindow = self?.scanWindow {
                        barcodeRequest.regionOfInterest = scanWindow
                    }

                    try imageRequestHandler.perform([barcodeRequest])
                } catch let error {
                    DispatchQueue.main.async {
                        self?.sink?(FlutterError(
                            code: MobileScannerErrorCodes.BARCODE_ERROR,
                            message: error.localizedDescription, details: nil))
                    }
                }
            }
        }

        // ---- ISLI decode: serial queue, non-blocking for Vision ----
        if (shouldDecodeIsli || shouldDecodeIsliLine) && !isliDecodeBusy {
            guard let buf = latestBuffer else { return }
            isliDecodeBusy = true
            isliDecodeQueue.async { [weak self] in
                guard let self = self else {
                    return
                }
                defer { self.isliDecodeBusy = false }
                // Read the scan window at decode time, not frame-delivery time:
                // decodes can lag delivery by many seconds, while the Dart widget
                // pushes the window a moment after camera start. Snapshotting at
                // delivery produced full-frame decodes for the first cycle.
                self.decodeISLIFrame(buf, scanWindow: self.scanWindow)
            }
        }
    }

    // MARK: - ISLI Custom Decode Pipeline

    // MARK: - TEMPORARY DEBUG: dump decoder-bound frames

    /// TEMPORARY DEBUG (removed): PNG dumping of decoder-bound frames was the
    /// dominant per-frame stall (2 PNG encodes/frame, one on the 3× upscaled
    /// 2592×1605 line crop). Deleting the calls removed it entirely.

    /// Convert a BGRA CVPixelBuffer to 8bpp grayscale and run ISLI decoders.
    /// Called on `isliDecodeQueue` (serial, non-concurrent).
    ///
    /// Icon-first: icon (2D, 6-way robust) runs before line — it's the common
    /// scan target. Line gets the grayscale crop with no orientation handling:
    /// straight decode first, then the wrapper's native +90° CW rotate as fallback.
    private func decodeISLIFrame(_ pixelBuffer: CVPixelBuffer, scanWindow: CGRect?) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Determine the working region FIRST (scanWindow box, else full frame),
        // then grayscale only that region. The source vImage_Buffer points into
        // the BGRA frame at the box's top-left with the full-frame row stride, so
        // the matrix multiply converts just boxW×boxH pixels — no full-frame gray
        // pass and no separate Swift copy loop.
        // BGRA byte order: pixel[0]=B, [1]=G, [2]=R, [3]=A.
        // vImageMatrixMultiply_ARGB8888ToPlanar8 expects the 4 coefficients in
        // A,R,G,B channel order, so luma = (77*R + 150*G + 29*B)/256 maps to
        // [A=0, R=77, G=150, B=29].
        let lumaMatrix: [Int16] = [0, 77, 150, 29]

        var decPixels: UnsafeMutablePointer<UInt8>
        var decWidth = width
        var decHeight = height
        var offX = 0, offY = 0
        var cropAlloc: UnsafeMutablePointer<UInt8>? = nil
        var grayAlloc: UnsafeMutablePointer<UInt8>? = nil
        var srcData: UnsafeMutableRawPointer = baseAddress
        var srcRowBytes = bytesPerRow

        if let sw = scanWindow {
            let boxX = max(0, Int(sw.minX * CGFloat(width)))
            // NOTE: scanWindow was Y-flipped for Vision (regionOfInterest uses
            // bottom-left origin). The buffer below is top-left origin, so undo
            // the flip here: unflipped top == 1 - sw.maxY (since sw.minY = 1-bottom).
            let boxY = max(0, Int((1.0 - sw.maxY) * CGFloat(height)))
            let boxW = min(width - boxX, Int(sw.width * CGFloat(width)))
            let boxH = min(height - boxY, Int(sw.height * CGFloat(height)))
            if boxW >= 32 && boxH >= 32 {
                let crop = UnsafeMutablePointer<UInt8>.allocate(capacity: boxW * boxH)
                cropAlloc = crop
                decPixels = crop
                decWidth = boxW; decHeight = boxH; offX = boxX; offY = boxY
                // Point the source directly at the box inside the BGRA frame:
                // pixel offset (boxY*bpl + boxX*4), row stride stays full-frame.
                srcData = baseAddress.advanced(by: boxY * bytesPerRow + boxX * 4)
                srcRowBytes = bytesPerRow
            } else {
                let gray = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
                grayAlloc = gray
                decPixels = gray
            }
        } else {
            let gray = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
            grayAlloc = gray
            decPixels = gray
        }
        defer { grayAlloc?.deallocate() }

        var srcBuf = vImage_Buffer(
            data: srcData,
            height: vImagePixelCount(decHeight),
            width: vImagePixelCount(decWidth),
            rowBytes: srcRowBytes
        )
        var dstBuf = vImage_Buffer(
            data: decPixels,
            height: vImagePixelCount(decHeight),
            width: vImagePixelCount(decWidth),
            rowBytes: decWidth
        )
        let vErr = vImageMatrixMultiply_ARGB8888ToPlanar8(
            &srcBuf, &dstBuf,
            lumaMatrix, 256,
            nil, 128,
            vImage_Flags(kvImageNoFlags)
        )
        if vErr != kvImageNoError {
            NSLog("[ISLI-DEBUG] vImage ERROR %ld — gray buffer may be garbage!", vErr)
        }

        // Step 1: ISLI icon code (2D) — icon-first, common case. No orientation
        // attempts, no contrast stretch: the grayscale crop is handed straight
        // to the decoder.
        if shouldDecodeIsli {
            if let result = ISLIDecoderWrapper.decodeGrayscalePixels(
                decPixels, width: decWidth, height: decHeight, bytesPerLine: decWidth) {
                emitISLIBarcode(result, format: 8192, imageWidth: width, imageHeight: height,
                                offX: offX, offY: offY)
                cropAlloc?.deallocate()
                return
            }
        }

        // Step 2: ISLI line code (1D). The grayscale crop is fed straight to the
        // decoder with no orientation handling; only on a miss does the wrapper's
        // native +90° CW rotate path run (two-step, see block below).
        if shouldDecodeIsliLine {
            // Step 1: feed the decoder the grayscale crop directly. The raw
            // portrait camera frame gets NO orientation handling up front.
            if let result = ISLILineDecoderWrapper.decodeGrayscalePixels(
                decPixels, width: decWidth, height: decHeight, bytesPerLine: decWidth) {
                emitISLIBarcode(result, format: 16384, imageWidth: width, imageHeight: height,
                                offX: offX, offY: offY)
                cropAlloc?.deallocate()
                return
            }

            // Step 2: fallback — the wrapper rotates 90° CW natively then decodes.
            if let result = ISLILineDecoderWrapper.decodeGrayscalePixelsRotated(
                decPixels, width: decWidth, height: decHeight, bytesPerLine: decWidth) {
                emitISLIBarcode(result, format: 16384, imageWidth: width, imageHeight: height,
                                offX: offX, offY: offY)
                cropAlloc?.deallocate()
                return
            }
        }

        cropAlloc?.deallocate()
    }

    /// Build an ISLI barcode map dictionary (Android MLKit-compatible, 16 fields).
    /// offX/offY translate cropped-space feature points back to full-frame coords.
    private func buildISLIBarcodeMap(_ nativeResult: [AnyHashable : Any], format: Int,
                                      imageWidth: Int, imageHeight: Int,
                                      offX: Int = 0, offY: Int = 0) -> [String: Any?]? {
        guard let isliCode = nativeResult["isliCode"] as? String,
              let featurePoints = nativeResult["featurePoints"] as? [[String: NSNumber]] else {
            return nil
        }

        var corners: [[String: Any]] = []
        for pt in featurePoints {
            if let x = pt["x"], let y = pt["y"] {
                corners.append(["x": Double(truncating: x) + Double(offX),
                                "y": Double(truncating: y) + Double(offY)])
            }
        }

        return [
            "calendarEvent": nil,
            "contactInfo": nil,
            "corners": corners,
            "displayValue": isliCode,
            "driverLicense": nil,
            "email": nil,
            "format": format,
            "geoPoint": nil,
            "phone": nil,
            "rawBytes": nil,
            "rawValue": isliCode,
            "size": nil,
            "sms": nil,
            // Dart 侧按 int 解析（`as int?`），字符串会抛 TypeError 导致事件丢失；
            // 0 = BarcodeType.unknown，与 Android 端 TYPE_UNKNOWN 保持一致。
            "type": 0,
            "url": nil,
            "wifi": nil,
        ]
    }

    /// Emit an ISLI barcode result to the Flutter event channel.
    private func emitISLIBarcode(_ nativeResult: [AnyHashable : Any], format: Int,
                                  imageWidth: Int, imageHeight: Int,
                                  offX: Int = 0, offY: Int = 0) {
        guard let barcodeData = buildISLIBarcodeMap(nativeResult, format: format,
                                                     imageWidth: imageWidth, imageHeight: imageHeight,
                                                     offX: offX, offY: offY) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.sink?([
                "name": "barcode",
                "data": [barcodeData],
                // 图像尺寸：供 Dart 侧把 featurePoints（图像坐标）映射到预览坐标
                "image": ["bytes": nil,
                          "width": Double(imageWidth),
                          "height": Double(imageHeight)],
            ])
        }
    }

    /// Convert a CGImage (any pixel format) to 8bpp grayscale bytes using BT.601 luma.
    /// Returns (data, width, height, bytesPerLine).
    private func extractGrayscaleFromCGImage(_ image: CGImage) -> (data: UnsafeMutablePointer<UInt8>, width: Int, height: Int, bytesPerLine: Int)? {
        let width = image.width
        let height = image.height
        let bytesPerLine = width
        let byteCount = width * height

        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)

        // Render CGImage into a BGRA8 bitmap context, then extract luma
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let context = CGContext(data: nil, width: width, height: height,
                                       bitsPerComponent: 8, bytesPerRow: width * 4,
                                       space: colorSpace, bitmapInfo: bitmapInfo.rawValue) else {
            data.deallocate()
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rgbaData = context.data else {
            data.deallocate()
            return nil
        }

        let rgba = rgbaData.assumingMemoryBound(to: UInt8.self)
        for i in 0..<byteCount {
            // BGRA layout in little-endian: bytes are [B, G, R, A] at offsets 0,1,2,3
            let off = i * 4
            let b = Int(rgba[off])
            let g = Int(rgba[off + 1])
            let r = Int(rgba[off + 2])
            data[i] = UInt8(((r * 77 + g * 150 + b * 29) >> 8) & 0xFF)
        }

        return (data, width, height, bytesPerLine)
    }

    func checkPermission(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        if #available(iOS 12.0, macOS 10.14, *) {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            switch status {
            case .notDetermined:
                result(0)
            case .authorized:
                result(1)
            default:
                result(2)
            }
        } else {
            result(1)
        }
    }
    
    func requestPermission(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        if #available(iOS 12.0, macOS 10.14, *) {
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { result($0) })
        } else {
            result(0)
        }
    }

    /// Parse a normalized rect `[left, top, right, bottom]` (top-left origin,
    /// texture-relative percentages, as sent by the Dart side) from a method
    /// call argument, converting it to a Vision-space CGRect (bottom-left
    /// origin). Reads `[NSNumber]` directly to avoid any bridging surprises.
    private func parseRectFromArgs(_ key: String, in args: [String: Any]?) -> CGRect? {
        guard let raw = args?[key] as? [NSNumber], raw.count == 4,
              raw.allSatisfy({ $0.doubleValue.isFinite }) else { return nil }
        let l = raw[0].doubleValue
        let t = raw[1].doubleValue
        let r = raw[2].doubleValue
        let b = raw[3].doubleValue
        guard r > l, b > t else { return nil }
        return CGRect(x: l, y: 1.0 - b, width: r - l, height: b - t)
    }

    func updateScanWindow(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        if let rect = parseRectFromArgs("rect", in: call.arguments as? [String: Any]) {
            scanWindow = rect
        } else {
            scanWindow = nil
        }
        result(nil)
    }

    private func getVideoOrientation() -> AVCaptureVideoOrientation {
#if os(iOS)
        // Get the orientation from the window scene if available
        // When the app's orientation is fixed and the app orientation is actually different from the device orientation, it malfunctions.
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                let orientation = windowScene.interfaceOrientation
                switch orientation {
                case .portrait:
                    return .portrait
                case .portraitUpsideDown:
                    return .portraitUpsideDown
                case .landscapeLeft:
                    return .landscapeLeft
                case .landscapeRight:
                    return .landscapeRight
                default:
                    break
                }         
            }
        }

        var videoOrientation: AVCaptureVideoOrientation

        switch UIDevice.current.orientation {
        case .portrait:
            videoOrientation = .portrait
        case .portraitUpsideDown:
            videoOrientation = .portraitUpsideDown
        case .landscapeLeft:
            videoOrientation = .landscapeLeft
        case .landscapeRight:
            videoOrientation = .landscapeRight
        default:
            videoOrientation = .portrait
        }

        return videoOrientation
#else
        return .portrait
#endif
    }


    func start(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        if (device != nil || captureSession != nil) {
            result(FlutterError(code: MobileScannerErrorCodes.ALREADY_STARTED_ERROR,
                                message: MobileScannerErrorCodes.ALREADY_STARTED_ERROR_MESSAGE,
                                details: nil))
            return
        }

        textureId = textureId ?? registry.register(self)
        captureSession = AVCaptureSession()

        let argReader = MapArgumentReader(call.arguments as? [String: Any])

        let torch:Bool = argReader.bool(key: "torch") ?? false
        let facing:Int = argReader.int(key: "facing") ?? 1
        let speed:Int = argReader.int(key: "speed") ?? 0
        let timeoutMs:Int = argReader.int(key: "timeout") ?? 0
        symbologies = argReader.toSymbology()
        MobileScannerPlugin.returnImage = argReader.bool(key: "returnImage") ?? false

        timeoutSeconds = Double(timeoutMs) / 1000.0
        detectionSpeed = DetectionSpeed(rawValue: speed)!

        // ---- ISLI format detection ----
        // Parse the raw formats list to check for custom ISLI codes (8192, 16384)
        // that are not handled by Apple Vision.
        if let formatsList = call.arguments as? [String: Any],
           let formats = formatsList["formats"] as? [Int] {
            if formats.isEmpty || formats.contains(0) || formats.contains(8192) {
                shouldDecodeIsli = true
            }
            if formats.isEmpty || formats.contains(0) || formats.contains(16384) {
                shouldDecodeIsliLine = true
            }
        } else {
            // No formats specified → decode all, including ISLI
            shouldDecodeIsli = true
            shouldDecodeIsliLine = true
        }

        // Pre-apply the scan window carried in the start options (the Dart
        // controller retains the last window across stop/start). The widget
        // also pushes it later via updateScanWindow.
        if let rect = parseRectFromArgs("scanWindow", in: call.arguments as? [String: Any]) {
            scanWindow = rect
        }

        // Initialize native ISLI decoders if needed
        if shouldDecodeIsli {
            _ = ISLIDecoderWrapper.initializeDecoder()
        }
        if shouldDecodeIsliLine {
            _ = ISLILineDecoderWrapper.initializeDecoder()
        }

        // Set the camera to use. In macOS only a front camera is available.
#if os(iOS)
        position = facing == 0 ? AVCaptureDevice.Position.front : .back
#else
        position = AVCaptureDevice.Position.front
#endif
        
        // Open the camera device
        if #available(macOS 10.15, *) {
            device = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: position).devices.first
        } else {
            device = AVCaptureDevice.devices(for: .video).filter({$0.position == position}).first
        }
        
        if (device == nil) {
            result(FlutterError(code: MobileScannerErrorCodes.NO_CAMERA_ERROR,
                                message: MobileScannerErrorCodes.NO_CAMERA_ERROR_MESSAGE,
                                details: nil))
            return
        }

        device.addObserver(self, forKeyPath: #keyPath(AVCaptureDevice.torchMode), options: .new, context: nil)
#if os(iOS)
        device.addObserver(self, forKeyPath: #keyPath(AVCaptureDevice.videoZoomFactor), options: [.new, .initial], context: nil)
#endif
        captureSession!.beginConfiguration()
        
        // Check the zoom factor at switching from ultra wide camera to wide camera.
        standardZoomFactor = 1
#if os(iOS)
        if #available(iOS 13.0, *) {
            for (index, actualDevice) in device.constituentDevices.enumerated() {
                if (actualDevice.deviceType != .builtInUltraWideCamera) {
                    if index > 0 && index <= device.virtualDeviceSwitchOverVideoZoomFactors.count {
                        standardZoomFactor = CGFloat(truncating: device.virtualDeviceSwitchOverVideoZoomFactors[index - 1])
                    }
                    break
                }
            }
        }
#endif

        // Add device input
        do {
            let input = try AVCaptureDeviceInput(device: device)
            
            if (!(captureSession!.canAddInput(input))) {
                result(FlutterError(
                    code: MobileScannerErrorCodes.CAMERA_ERROR,
                    message: MobileScannerErrorCodes.CAMERA_ERROR_CAPTURE_SESSION_INPUT_OCCUPIED_MESSAGE,
                    details: nil))
                return
            }
            
            captureSession!.addInput(input)
        } catch {
            result(FlutterError(
                code: MobileScannerErrorCodes.CAMERA_ERROR,
                message: error.localizedDescription, details: nil))
            return
        }
        // Use .high (1080p) instead of .photo (12MP/48MP). Full-sensor BGRA
        // frames (~48MB each) delivered on the main thread + the Flutter
        // texture copy on the raster thread starve the preview pipeline on
        // older devices → black texture. 1080p is ample for both Vision and
        // the ISLI decoders, and is 5.7× cheaper per frame.
        captureSession!.sessionPreset = AVCaptureSession.Preset.high

        // Add video output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true

        // Deliver frames on a dedicated serial queue, not the main thread:
        // at 1080p30 the main-thread delegate would still throttle the UI.
        sampleBufferQueue = DispatchQueue(label: "mobile_scanner.sample_buffer")
        videoOutput.setSampleBufferDelegate(self, queue: sampleBufferQueue!)
        captureSession!.addOutput(videoOutput)
        let deviceVideoOrientation = self.getVideoOrientation()
        

        // Adjust orientation for the video connection
        if let connection = videoOutput.connections.first {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = deviceVideoOrientation
            }

            if position == .front && connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        captureSession!.commitConfiguration()

        // Move startRunning to a background thread to avoid blocking the main UI thread.
        DispatchQueue.global(qos: .background).async {
            self.captureSession!.startRunning()

            DispatchQueue.main.async {
                let dimensions: CMVideoDimensions

                if let device = self.device {
                    dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                } else {
                    dimensions = CMVideoDimensions()
                }

                // Turn on the torch if requested.
                if (torch) {
                    self.turnTorchOn()
                }

#if os(iOS)
                // The height and width are swapped because the default video orientation for ios is landscape right, but mobile_scanner operates in portrait mode.
                // When mobile_scanner is opened in landscape mode, the Dart code automatically swaps the width and height parameters back to match the correct orientation.
                let size = ["width": Double(dimensions.height), "height": Double(dimensions.width)]
#else
                let size = ["width": Double(dimensions.width), "height": Double(dimensions.height)]
#endif
                // Return the result on the main thread after the session starts.
                let answer: [String : Any?]

                if let device = self.device {
                    // Xcode 14 (Swift 5.7) does not support `switch` expressions.
                    let cameraDirection: Int?
                    switch device.position {
                    case .back: cameraDirection = 1
                    case .unspecified: cameraDirection = nil
                    case .front: cameraDirection = 0
                    @unknown default: cameraDirection = nil
                    }
                    
                    answer = [
                        "textureId": self.textureId,
                        "size": size,
                        "currentTorchState": device.hasTorch ? device.torchMode.rawValue : -1,
                        "cameraDirection": cameraDirection,
                        "initialDeviceOrientation": deviceVideoOrientation.toOrientationString
                    ]
                } else {
                    answer = [
                        "textureId": self.textureId,
                        "size": size,
                        "currentTorchState": -1,
                    ]
                }

                result(answer)
            }
        }
    }

    /// Turn the torch on.
    private func turnTorchOn() {
        guard let device = self.device else {
            return
        }

        if (!device.hasTorch || !device.isTorchModeSupported(.on) || device.torchMode == .on) {
            return
        }

        if #available(macOS 15.0, *) {
            if(!device.isTorchAvailable) {
                return
            }
        }

        do {
            try device.lockForConfiguration()
            device.torchMode = .on
            device.unlockForConfiguration()
        } catch(_) {
            // Do nothing.
        }
    }

    /// Sets the zoomScale.
    private func setScale(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let scale = call.arguments as? CGFloat
        if (scale == nil) {
            result(FlutterError(code: MobileScannerErrorCodes.GENERIC_ERROR,
                                message: MobileScannerErrorCodes.INVALID_ZOOM_SCALE_ERROR_MESSAGE,
                                details: "The invalid zoom scale was nil."))
            return
        }
        do {
            try setScaleInternal(scale!)
            result(nil)
        } catch MobileScannerError.zoomWhenStopped {
            result(FlutterError(code: MobileScannerErrorCodes.SET_SCALE_WHEN_STOPPED_ERROR,
                                message: MobileScannerErrorCodes.SET_SCALE_WHEN_STOPPED_ERROR_MESSAGE,
                                details: nil))
        } catch MobileScannerError.zoomError(let error) {
            result(FlutterError(code: MobileScannerErrorCodes.GENERIC_ERROR,
                                message: error.localizedDescription,
                                details: nil))
        } catch {
            result(FlutterError(code: MobileScannerErrorCodes.GENERIC_ERROR,
                                message: MobileScannerErrorCodes.GENERIC_ERROR_MESSAGE,
                                details: nil))
        }
    }

    /// Reset the zoomScale.
    private func resetScale(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        do {
            try resetScaleInternal()
            result(nil)
        } catch MobileScannerError.zoomWhenStopped {
            result(FlutterError(code: MobileScannerErrorCodes.SET_SCALE_WHEN_STOPPED_ERROR,
                                message: MobileScannerErrorCodes.SET_SCALE_WHEN_STOPPED_ERROR_MESSAGE,
                                details: nil))
        } catch MobileScannerError.zoomError(let error) {
            result(FlutterError(code: MobileScannerErrorCodes.GENERIC_ERROR,
                                message: error.localizedDescription,
                                details: nil))
        } catch {
            result(FlutterError(code: MobileScannerErrorCodes.GENERIC_ERROR,
                                message: MobileScannerErrorCodes.GENERIC_ERROR_MESSAGE,
                                details: nil))
        }
    }

    /// Set the zoom factor of the camera
    func setScaleInternal(_ scale: CGFloat) throws {
        if (device == nil) {
            throw MobileScannerError.zoomWhenStopped
        }

        do {
#if os(iOS)
                try device.lockForConfiguration()
                // Limit to 1.0 scale
                device.videoZoomFactor = getSafeZoomFactor(scale: scale)

                device.unlockForConfiguration()
#endif
        } catch {
            throw MobileScannerError.zoomError(error)
        }

    }
    
#if os(iOS)
    /// Set the device orientation if it differs from previous orientation
    func setDeviceOrientation(orientation: UIDeviceOrientation) {
        if (device == nil || deviceOrientation == orientation) {
            return
        }

        deviceOrientation = orientation
        updateOrientation(orientation: orientation)
    }

    /// Update the device orientation of the first open video output
    func updateOrientation(orientation: UIDeviceOrientation) {
        if let videoOutput = captureSession!.outputs.compactMap({ $0 as? AVCaptureVideoDataOutput }).first {
            for connection in videoOutput.connections {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = orientation.videoOrientation
                }
            }
        }
    }
    
#endif

    /// Reset the zoom factor of the camera
    func resetScaleInternal() throws {
        if (device == nil) {
            throw MobileScannerError.zoomWhenStopped
        }

        do {
#if os(iOS)
                try device.lockForConfiguration()
                device.videoZoomFactor = standardZoomFactor
                device.unlockForConfiguration()
#endif
        } catch {
            throw MobileScannerError.zoomError(error)
        }
    }
    
    func getSafeZoomFactor(scale: CGFloat) -> CGFloat {
        var scaleToUse = scale
#if os(iOS)
        var actualScale = (scale * 4) + 1
        
        // Set a maximum zoom limit of 5x
        actualScale = min(5.0, actualScale)
        
        // Ensure it does not exceed the camera's max zoom capability
        scaleToUse = min(device.activeFormat.videoMaxZoomFactor, actualScale)
#endif
        return scaleToUse
    }
    
    func getScaleFromZoomFactor(actualScale: CGFloat) -> CGFloat {
        return (actualScale - 1) / 4
    }

    private func toggleTorch(_ result: @escaping FlutterResult) {
        guard let device = self.device else {
            result(nil)
            return
        }
        
        if (!device.hasTorch) {
            result(nil)
            return
        }
        
        if #available(macOS 15.0, *) {
            if(!device.isTorchAvailable) {
                result(nil)
                return
            }
        }
        
        var newTorchMode: AVCaptureDevice.TorchMode = device.torchMode
        
        switch(device.torchMode) {
        case AVCaptureDevice.TorchMode.auto:
            if #available(macOS 10.15, *) {
                newTorchMode = device.isTorchActive ? AVCaptureDevice.TorchMode.off : AVCaptureDevice.TorchMode.on
            }
            break;
        case AVCaptureDevice.TorchMode.off:
            newTorchMode = AVCaptureDevice.TorchMode.on
            break;
        case AVCaptureDevice.TorchMode.on:
            newTorchMode = AVCaptureDevice.TorchMode.off
            break;
        default:
            result(nil)
            return;
        }
        
        if (!device.isTorchModeSupported(newTorchMode) || device.torchMode == newTorchMode) {
            result(nil)
            return;
        }

        do {
            try device.lockForConfiguration()
            device.torchMode = newTorchMode
            device.unlockForConfiguration()
        } catch(_) {
            // Do nothing.
        }

        result(nil)
    }

    func pause(_ call: FlutterMethodCall, _ result: FlutterResult) {
        let force = (call.arguments as? Bool) ?? false
        if (!force) {
            if (paused || stopped) {
                result(nil)

                return
            }
        }

        releaseCamera()

        result(nil)
    }

    func stop(_ call: FlutterMethodCall, _ result: FlutterResult) {
        let force = (call.arguments as? Bool) ?? false
        if (!paused && stopped && !force) {
            result(nil)

            return
        }
        releaseCamera()
        releaseTexture()

        // Cleanup ISLI decoders: serialize behind any in-flight decode
        // on the decode queue to prevent SIGSEGV from freed BCH tables.
        if shouldDecodeIsli || shouldDecodeIsliLine {
            isliDecodeQueue.async { [weak self] in
                if self?.shouldDecodeIsli == true {
                    ISLIDecoderWrapper.uninitializeDecoder()
                }
                if self?.shouldDecodeIsliLine == true {
                    ISLILineDecoderWrapper.uninitializeDecoder()
                }
                self?.shouldDecodeIsli = false
                self?.shouldDecodeIsliLine = false
            }
        }

        result(nil)
    }

    private func releaseCamera() {
        guard let captureSession = captureSession else {
            return
        }

        guard let device = device else {
            return
        }

        captureSession.stopRunning()
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
        device.removeObserver(self, forKeyPath: #keyPath(AVCaptureDevice.torchMode))
#if os(iOS)
        device.removeObserver(self, forKeyPath: #keyPath(AVCaptureDevice.videoZoomFactor))
#endif

        latestBuffer = nil
        self.captureSession = nil
        self.device = nil
    }

    private func releaseTexture() {
        if (textureId == nil) {
            return
        }

        registry.unregisterTexture(textureId)
        textureId = nil
    }

    /// Switch which native ISLI decoder is active for live frames at runtime
    /// (called by the Dart UI when toggling between line-code and icon-code
    /// scan modes). Decoders are initialized lazily on demand; they stay
    /// initialized until the scanner is fully stopped.
    func setISLIMode(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        if let icon = args?["icon"] as? Bool {
            shouldDecodeIsli = icon
        }
        if let line = args?["line"] as? Bool {
            shouldDecodeIsliLine = line
        }
        if shouldDecodeIsli {
            _ = ISLIDecoderWrapper.initializeDecoder()
        }
        if shouldDecodeIsliLine {
            _ = ISLILineDecoderWrapper.initializeDecoder()
        }
        result(nil)
    }

    /// 播放扫码成功提示音（"滴"一声）。
    /// iOS 系统音效 1057 = Tink（清脆"叮"），比 Flutter SystemSound.click 悦耳，
    /// 且不受 Flutter SystemSoundType.alert 在 iOS 上映射失效的影响。
    func playScanSound(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        AudioServicesPlaySystemSound(1057)
        result(nil)
    }

    func analyzeImage(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        // The iOS Simulator cannot use some of the GPU features that are required for the Vision API.
        // Thus analyzing images is not supported on the iOS Simulator.
        //
        // See https://forums.developer.apple.com/forums/thread/696714
#if os(iOS) && targetEnvironment(simulator)
        result(FlutterError(
            code: MobileScannerErrorCodes.UNSUPPORTED_OPERATION_ERROR,
            message: MobileScannerErrorCodes.ANALYZE_IMAGE_IOS_SIMULATOR_NOT_SUPPORTED_ERROR_MESSAGE,
            details: nil
        ))
        return
#endif

        let argReader = MapArgumentReader(call.arguments as? [String: Any])
        let symbologies:[VNBarcodeSymbology] = argReader.toSymbology()

        // Check for ISLI formats in the analyzeImage call
        var analyzeIsli = false
        var analyzeIsliLine = false
        if let formatsList = argReader.args?["formats"] as? [Int] {
            if formatsList.isEmpty || formatsList.contains(0) || formatsList.contains(8192) {
                analyzeIsli = true
            }
            if formatsList.isEmpty || formatsList.contains(0) || formatsList.contains(16384) {
                analyzeIsliLine = true
            }
        }

        guard let filePath: String = argReader.string(key: "filePath") else {
            result(nil)
            return
        }

        // Read the optional scanWindow from the analyzeImage call arguments.
        // Falls back to the stored scanWindow if not provided in the call.
        var effectiveScanWindow: CGRect? = nil
        if let scanWindowData: [CGFloat] = argReader.floatArray(key: "scanWindow") {
            let left = scanWindowData[0]
            let top = scanWindowData[1]
            let right = scanWindowData[2]
            let bottom = scanWindowData[3]

            // Convert from top-left origin (Dart) to bottom-left origin (Vision)
            effectiveScanWindow = CGRect(
                x: left,
                y: 1 - bottom,
                width: right - left,
                height: bottom - top
            )
        } else {
            effectiveScanWindow = self.scanWindow
        }

        let fileUrl = URL(fileURLWithPath: filePath)

        guard let ciImage = CIImage(contentsOf: fileUrl) else {
            result(FlutterError(
                code: MobileScannerErrorCodes.BARCODE_ERROR,
                message: MobileScannerErrorCodes.ANALYZE_IMAGE_NO_VALID_IMAGE_ERROR_MESSAGE,
                details: nil
            ))
            return
        }

        // ---- ISLI decode for static images (sync, before Vision) ----
        // Convert CIImage → CGImage → grayscale bytes for ISLI decoders.
        var isliBarcodeMaps: [[String: Any?]] = []
        let imgWidth = Int(ciImage.extent.width)
        let imgHeight = Int(ciImage.extent.height)
        if analyzeIsli || analyzeIsliLine {
            let context = CIContext(options: nil)
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let grayPixels = extractGrayscaleFromCGImage(cgImage)
                if let gray = grayPixels {
                    defer { gray.data.deallocate() }

                    // 与实时线码解码一致：先 raw 直解，失败再 90° 旋转兜底
                    if analyzeIsliLine {
                        if let lineResult =
                            ISLILineDecoderWrapper.decodeGrayscalePixels(
                                gray.data, width: gray.width, height: gray.height, bytesPerLine: gray.bytesPerLine)
                            ?? ISLILineDecoderWrapper.decodeGrayscalePixelsRotated(
                                gray.data, width: gray.width, height: gray.height, bytesPerLine: gray.bytesPerLine) {
                            if let map = buildISLIBarcodeMap(lineResult, format: 16384,
                                                             imageWidth: imgWidth, imageHeight: imgHeight) {
                                isliBarcodeMaps.append(map)
                            }
                        }
                    }

                    if analyzeIsli {
                        if let iconResult = ISLIDecoderWrapper.decodeGrayscalePixels(
                            gray.data, width: gray.width, height: gray.height, bytesPerLine: gray.bytesPerLine) {
                            if let map = buildISLIBarcodeMap(iconResult, format: 8192,
                                                             imageWidth: imgWidth, imageHeight: imgHeight) {
                                isliBarcodeMaps.append(map)
                            }
                        }
                    }
                }
            }
        }

        let imageRequestHandler = VNImageRequestHandler(ciImage: ciImage, orientation: CGImagePropertyOrientation.up, options: [:])

        do {
            let barcodeRequest: VNDetectBarcodesRequest = VNDetectBarcodesRequest(
                completionHandler: { [isliBarcodeMaps] (request, error) in

                if error != nil {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: MobileScannerErrorCodes.BARCODE_ERROR,
                            message: error?.localizedDescription, details: nil))
                    }
                    return
                }

                let visionBarcodes: [VNBarcodeObservation] = (request.results as? [VNBarcodeObservation]) ?? []
                let visionMaps = visionBarcodes.map({
                    $0.toMap(imageWidth: imgWidth, imageHeight: imgHeight,
                             scanWindow: effectiveScanWindow)
                })

                // Merge ISLI results (prepended) with Vision results
                let allBarcodes = isliBarcodeMaps + visionMaps

                DispatchQueue.main.async {
                    result([
                        "name": "barcode",
                        "data": allBarcodes,
                    ])
                }
            })

            if !symbologies.isEmpty {
                // Add the symbologies the user wishes to support.
                barcodeRequest.symbologies = symbologies
            }

            // Restrict the search region to the scan window if provided.
            if let scanWindow = effectiveScanWindow {
                barcodeRequest.regionOfInterest = scanWindow
            }

            try imageRequestHandler.perform([barcodeRequest])
        } catch let error {
            DispatchQueue.main.async {
                result(FlutterError(
                    code: MobileScannerErrorCodes.BARCODE_ERROR,
                    message: error.localizedDescription, details: nil))
            }
        }
    }

    // Observer for torch state
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        switch keyPath {
        case #keyPath(AVCaptureDevice.torchMode):
            // Off = 0, On = 1, Auto = 2
            let state = change?[.newKey] as? Int
            let event: [String: Any?] = ["name": "torchState", "data": state]
            sink?(event)
#if os(iOS)
        case #keyPath(AVCaptureDevice.videoZoomFactor):
            if let zoomScale = change?[.newKey] as? CGFloat,
               let device = object as? AVCaptureDevice {
                
                let scale = getScaleFromZoomFactor(actualScale: zoomScale)

                let event: [String: Any?] = ["name": "zoomScaleState", "data":scale]
                sink?(event)
            }
#endif
        default:
            break
        }
    }
}

class MapArgumentReader {
    let args: [String: Any]?

    init(_ args: [String: Any]?) {
        self.args = args
    }

    func string(key: String) -> String? {
        return args?[key] as? String
    }

    func int(key: String) -> Int? {
        return (args?[key] as? NSNumber)?.intValue
    }

    func bool(key: String) -> Bool? {
        return (args?[key] as? NSNumber)?.boolValue
    }

    func stringArray(key: String) -> [String]? {
        return args?[key] as? [String]
    }

    func toSymbology() -> [VNBarcodeSymbology] {
        guard let syms:[Int] = args?["formats"] as? [Int] else {
            return []
        }
        if(syms.contains(0)){
            return []
        }
        var barcodeFormats:[VNBarcodeSymbology] = []
        syms.forEach { id in
            if let bc:VNBarcodeSymbology = VNBarcodeSymbology.fromInt(id) {
                barcodeFormats.append(bc)
            }
        }
        return barcodeFormats
    }

    func floatArray(key: String) -> [CGFloat]? {
        return args?[key] as? [CGFloat]
    }

}

extension CGImage {
    public func jpegData(compressionQuality: CGFloat) -> Data? {
        let mutableData = CFDataCreateMutable(nil, 0)

        let formatHint: CFString
        
        if #available(iOS 14.0, macOS 11.0, *) {
            formatHint = UTType.jpeg.identifier as CFString
        } else {
            formatHint = kUTTypeJPEG
        }

        guard let destination = CGImageDestinationCreateWithData(mutableData!, formatHint, 1, nil) else {
            return nil
        }

        let options: NSDictionary = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality,
        ]

        CGImageDestinationAddImage(destination, self, options)

        if !CGImageDestinationFinalize(destination) {
            return nil
        }

        return mutableData as Data?
    }
}

extension VNBarcodeObservation {
    private func distanceBetween(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        return sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }
    
    /// Map this `VNBarcodeObservation` to a dictionary.
    ///
    /// The `imageWidth` and `imageHeight` indicate the width and height of the input image that contains this observation.
    public func toMap(imageWidth: Int, imageHeight: Int, scanWindow: CGRect?) -> [String: Any?] {

        // Calculate adjusted points based on whether scanWindow is set
        let adjustedTopLeft: CGPoint
        let adjustedTopRight: CGPoint
        let adjustedBottomRight: CGPoint
        let adjustedBottomLeft: CGPoint

        if let scanWindow = scanWindow {
            // When a scanWindow is set, adjust the barcode coordinates to the full image
            func adjustPoint(_ point: CGPoint) -> CGPoint {
                let x = scanWindow.minX + point.x * scanWindow.width
                let y = scanWindow.minY + point.y * scanWindow.height
                return CGPoint(x: x, y: y)
            }

            adjustedTopLeft = adjustPoint(topLeft)
            adjustedTopRight = adjustPoint(topRight)
            adjustedBottomRight = adjustPoint(bottomRight)
            adjustedBottomLeft = adjustPoint(bottomLeft)
        } else {
            // If no scanWindow, use original points (already normalized to the full image)
            adjustedTopLeft = topLeft
            adjustedTopRight = topRight
            adjustedBottomRight = bottomRight
            adjustedBottomLeft = bottomLeft
        }

        // Convert adjusted points from normalized coordinates to image pixel coordinates
        let topLeftX = adjustedTopLeft.x * CGFloat(imageWidth)
        let topRightX = adjustedTopRight.x * CGFloat(imageWidth)
        let bottomRightX = adjustedBottomRight.x * CGFloat(imageWidth)
        let bottomLeftX = adjustedBottomLeft.x * CGFloat(imageWidth)
        let topLeftY = (1 - adjustedTopLeft.y) * CGFloat(imageHeight)
        let topRightY = (1 - adjustedTopRight.y) * CGFloat(imageHeight)
        let bottomRightY = (1 - adjustedBottomRight.y) * CGFloat(imageHeight)
        let bottomLeftY = (1 - adjustedBottomLeft.y) * CGFloat(imageHeight)

        // Calculate the width and height of the barcode based on adjusted coordinates
        let width = distanceBetween(adjustedTopLeft, adjustedTopRight) * CGFloat(imageWidth)
        let height = distanceBetween(adjustedTopLeft, adjustedBottomLeft) * CGFloat(imageHeight)
        var rawBytes: FlutterStandardTypedData? = nil
        // Note: `payloadData` (iOS 17+ API) is not available in this SDK version.

        let data = [
            // Clockwise, starting from the top-left corner.
            "corners":  [
                ["x": topLeftX, "y": topLeftY],
                ["x": topRightX, "y": topRightY],
                ["x": bottomRightX, "y": bottomRightY],
                ["x": bottomLeftX, "y": bottomLeftY],
            ],
            "format": symbology.toInt ?? -1,
            "rawBytes": rawBytes,
            "rawValue": payloadStringValue,
            "displayValue": payloadStringValue,
            "size": [
                "width": width,
                "height": height,
            ],
        ] as [String : Any?]
        return data
    }
}

extension VNBarcodeSymbology {
    static func fromInt(_ mapValue:Int) -> VNBarcodeSymbology? {
        if #available(iOS 15.0, macOS 12.0, *) {
            if(mapValue == 8){
                return VNBarcodeSymbology.codabar
            }
        }
        switch(mapValue){
        case 1:
            return VNBarcodeSymbology.code128
        case 2:
            return VNBarcodeSymbology.code39
        case 4:
            return VNBarcodeSymbology.code93
        case 16:
            return VNBarcodeSymbology.dataMatrix
        case 32:
            return VNBarcodeSymbology.ean13
        case 64:
            return VNBarcodeSymbology.ean8
        case 128:
            return VNBarcodeSymbology.itf14
        case 256:
            return VNBarcodeSymbology.qr
        case 1024:
            return VNBarcodeSymbology.upce
        case 2048:
            return VNBarcodeSymbology.pdf417
        case 4096:
            return VNBarcodeSymbology.aztec
        default:
            return nil
        }
    }

    var toInt: Int? {
        if #available(iOS 15.0, macOS 12.0, *) {
            if(self == VNBarcodeSymbology.codabar){
                return 8
            }
        }
        switch(self){
        case VNBarcodeSymbology.code128:
            return 1
        case VNBarcodeSymbology.code39:
            return 2
        case VNBarcodeSymbology.code93:
            return 4
        case VNBarcodeSymbology.dataMatrix:
            return 16
        case VNBarcodeSymbology.ean13:
            return 32
        case VNBarcodeSymbology.ean8:
            return 64
        case VNBarcodeSymbology.itf14:
            return 128
        case VNBarcodeSymbology.qr:
            return 256
        case VNBarcodeSymbology.upce:
            return 1024
        case VNBarcodeSymbology.pdf417:
            return 2048
        case VNBarcodeSymbology.aztec:
            return 4096
        default:
            return -1
        }
    }
}

extension AVCaptureVideoOrientation {
    var toOrientationString: String {
        switch self {
        case .portrait:
            return "PORTRAIT_UP"
        case .portraitUpsideDown:
            return "PORTRAIT_DOWN"
        case .landscapeLeft:
            return "LANDSCAPE_LEFT"
        case .landscapeRight:
            return "LANDSCAPE_RIGHT"
        default:
            return "PORTRAIT_UP"
        }
    }
}

#if os(iOS)
extension UIDeviceOrientation {
    var toOrientationString: String {
        switch self {
        case .portrait:
            return "PORTRAIT_UP"
        case .portraitUpsideDown:
            return "PORTRAIT_DOWN"
        case .landscapeLeft:
            return "LANDSCAPE_LEFT"
        case .landscapeRight:
            return "LANDSCAPE_RIGHT"
        case .faceUp:
            return "PORTRAIT_UP"
        case .faceDown:
            return "PORTRAIT_DOWN"
        default:
            return "PORTRAIT_UP"
        }
    }
    
    /// Converts UIDeviceOrientation to correct VideoOrientation
    var videoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .portrait:
            return .portrait
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        case .portraitUpsideDown:
            return .portraitUpsideDown
        default:
            return .portrait
        }
    }
}
#endif
