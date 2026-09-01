/*
* Copyright (c) 2023 Shenzhen Kaihong Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import MethodChannel, {
  MethodCallHandler,
  MethodResult
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import HiLog from '@ohos.hilog';
import { AbilityAware, AbilityPluginBinding, ByteBuffer } from '@ohos/flutter_ohos/index';
import { UIAbility } from '@kit.AbilityKit';
import { cameraPermission, checkPermissions, requestPermissions } from './CameraPermissions';
import { customScan, scanBarcode, scanCore, detectBarcode } from '@kit.ScanKit';
import EventChannel, { EventSink } from '@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel';
import { Barcode, BarcodeFormat, BarcodeType } from './Barcode';
import { ISLIDecoder, ISLIIconResult } from './ISLIDecoder';
import { ISLILineDecoder, ISLILineResult } from './ISLILineDecoder';
import { runIsliCascade, IsliCascadeHit } from './ISLICascade';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { display } from '@kit.ArkUI';
import { Point } from '@ohos.UiTest';
import { hasFlashUnit, getCameraManager } from './CameraUtil';
import { image } from '@kit.ImageKit';
import { camera } from '@kit.CameraKit';
import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';

const TAG: string = "MobileScannerPlugin";

enum TorchState {
  off = 0,
  on = 1
}

/** A grayscale (8bpp) image plus its dimensions. */
interface GrayImage {
  pixels: Uint8Array;
  w: number;
  h: number;
}

/** A cropped Y-plane plus the full-frame offset to remap feature points. */
interface CroppedYPlane {
  buf: Uint8Array;
  w: number;
  h: number;
  offX: number;
  offY: number;
}

export class MobileScannerPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  getUniqueClassName(): string {
    return "MobileScannerPlugin";
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    Log.i(TAG, "onAttachedToAbility");
    this.ability = binding.getAbility()
  }

  onDetachedFromAbility(): void {
    Log.i(TAG, "onDetachedFromAbility");
    this.ability = null;
  }

  private methodChannel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private eventSink: EventSink | null = null
  private applicationContext: Context | null = null;
  private ability: UIAbility | null = null;
  private textureId: number | null = null;
  private surfaceId: string | null = null;
  private binding: FlutterPluginBinding | null = null;
  private isStart = false;
  private scanWidth: number = 1080 // 单位px
  private scanHeight: number = 1080 // 单位px
  private returnImage: boolean = false;
  private cameraResolutionValues: number[] | undefined = undefined;
  private resolutionRatio = [16/9,4/3,1];   //分辨率比例
  private torch: boolean = false
  private facing: number = 0
  private formats: number[] | undefined = undefined
  private speed: number = 1
  private timeout: number = 250
  private useNewCameraSelector: boolean = false
  private options: scanBarcode.ScanOptions = {};
  private retryScanTimes: number = 0;

  private scanWindow: Array<number> | null = null; // scanWindow，扫描区域
  private imageBuffer: Uint8Array | null = null;
  private isPaused:boolean = false

  // ---- ISLI custom decoder support ----
  private isliDecoder: ISLIDecoder = new ISLIDecoder();
  private isliLineDecoder: ISLILineDecoder = new ISLILineDecoder();
  private readonly isliInstanceId: string = "mobile_scanner";
  private shouldDecodeIsli: boolean = false;
  private shouldDecodeIsliLine: boolean = false;
  /// Serial decode guard: only one ISLI decode frame at a time.
  /// Line code is ~2s; new frames are dropped while busy.
  private isliDecodeBusy: boolean = false;
  /// Frame counter for throttling (decode every Nth frame; 0 = every frame).
  private isliFrameCount: number = 0;
  /// Decode every (skip + 1) frames. 0 = no skip, 1 = every other, etc.
  private isliFrameSkip: number = 0;

  private deviceOrientationChannel: EventChannel | null = null;
  private deviceOrientationEventSink: EventSink | null = null;
  private lastOrientation: string | null = null;

  publishEvent(event: ESObject) {
    this.eventSink?.success(event)
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.binding = binding;
    this.applicationContext = binding.getApplicationContext();
    this.methodChannel =
      new MethodChannel(binding.getBinaryMessenger(), "dev.steenbakker.mobile_scanner/scanner/method");
    this.methodChannel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), "dev.steenbakker.mobile_scanner/scanner/event");
    this.eventChannel.setStreamHandler({
      onListen: (args: Object, eventSink: EventSink) => {
        this.eventSink = eventSink;
      },
      onCancel: () => {
      }
    });
    this.deviceOrientationChannel = new EventChannel(binding.getBinaryMessenger(),
      "dev.steenbakker.mobile_scanner/scanner/deviceOrientation");
    this.deviceOrientationChannel.setStreamHandler({
      onListen: (args: Object, eventSink: EventSink) => {
        this.deviceOrientationEventSink = eventSink;
      },
      onCancel: () => {
        this.deviceOrientationEventSink = null;
      }
    });
    // texture
    const textureRegistry = this.binding!.getTextureRegistry();
    this.textureId = textureRegistry.getTextureId();
    const surfaceTextureEntry = textureRegistry.registerTexture(this.textureId);
    this.surfaceId = surfaceTextureEntry.getSurfaceId().toString();
    Log.i(TAG, `surfaceId: ${this.surfaceId}`)
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.applicationContext = null;
    this.methodChannel?.setMethodCallHandler(null);
    this.methodChannel = null;
    this.eventChannel?.setStreamHandler(null);
    this.eventChannel = null;
    this.stopOrientationListening();
    this.deviceOrientationChannel?.setStreamHandler(null);
    this.deviceOrientationChannel = null;
    this.deviceOrientationEventSink = null;
    this.isStart = false;
    this.scanWindow = null;
    this.imageBuffer = null;
    binding.getTextureRegistry().unregisterTexture(this.textureId);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    try {
      if (call.method === "state") {
        checkPermissions(cameraPermission).then(hasCameraPermission => {
          if (hasCameraPermission) {
            result.success(1)
          } else {
            result.success(2)
          }
        }).catch((error: BusinessError) => {
          result.error(String(error.code), error.message, null);
        });
      } else if (call.method === "request") {
        requestPermissions(this.ability!.context, (err, msg) => {
          if (err) {
            result.success(false)
          } else {
            result.success(true)
          }
        });
      } else if (call.method === "start") {
        this.start(call, result)
      } else if (call.method === "toggleTorch") {
        this.toggleTorch(call, result)
      } else if (call.method === "stop") {
        this.stop(result)
      } else if (call.method === "analyzeImage") {
        this.analyzeImage(call, result)
      } else if (call.method === "setScale") {
        this.setScale(call, result)
      } else if (call.method === "resetScale") {
        this.resetScale(result)
      } else if (call.method === "updateScanWindow") {
        this.updateScanWindow(call, result)
      } else if (call.method === "pause") {
        this.pause(call, result)
      } else if (call.method === "setISLIMode") {
        this.setISLIMode(call, result)
      } else if (call.method === "playScanSound") {
        this.playScanSound(result)
      } else {
        result.notImplemented()
      }
    } catch (err) {
      result.error("Name not found", err.message, null)
    }
  }

  async start(call: MethodCall, result: MethodResult) {
    this.torch = call.argument("torch") ?? false
    this.facing = call.argument("facing") ?? 0
    this.formats = call.argument("formats")
    this.returnImage = call.argument("returnImage") ?? false
    this.speed = call.argument("speed") ?? 1
    this.timeout = call.argument("timeout") ?? 250
    this.cameraResolutionValues = call.argument("cameraResolution")
    this.useNewCameraSelector = call.argument("useNewCameraSelector") ?? false

    // Read scanWindow from start arguments (matching Android's pattern).
    // scanWindow coordinates are relative (0.0 to 1.0), same format as updateScanWindow.
    const scanWindowArg: number[] | null = call.argument("scanWindow")
    if (scanWindowArg && scanWindowArg.length >= 4) {
      this.scanWindow = scanWindowArg;
    } else {
      this.scanWindow = null;
    }
    // ---- ISLI format gating ----
    // null/empty/contains-0 → all formats (including ISLI).
    // Otherwise enable only if the specific ISLI format ID is present.
    if (!this.formats || this.formats.length === 0 || this.formats.indexOf(0) >= 0) {
      this.shouldDecodeIsli = true;
      this.shouldDecodeIsliLine = true;
    } else {
      this.shouldDecodeIsli = this.formats.indexOf(BarcodeFormat.isli) >= 0 || this.formats.indexOf(BarcodeFormat.all) >= 0;
      this.shouldDecodeIsliLine = this.formats.indexOf(BarcodeFormat.isli_line_code) >= 0 || this.formats.indexOf(BarcodeFormat.all) >= 0;
    }
    if (this.shouldDecodeIsli || this.shouldDecodeIsliLine) {
      Log.setLogLevel(HiLog.LogLevel.INFO);
    }
    if (this.shouldDecodeIsli) {
      this.isliDecoder.init(this.isliInstanceId);
      // Native icon decoder log level: 2=WARN (errors only; use 3=INFO or 4=DEBUG for diagnostics).
      this.isliDecoder.setLogLevel(2);
    }
    if (this.shouldDecodeIsliLine) {
      this.isliLineDecoder.init(this.isliInstanceId);
      this.isliLineDecoder.setLogLevel(2);
    }

    this.retryScanTimes = 0;
    this.isStart = true;
    let scanTypes = [scanCore.ScanType.ALL]
    if (this.formats) {
      scanTypes = []
      this.formats.forEach((format: number) => {
        let type = Barcode.convertToScanType(format)
        if (type != scanCore.ScanType.FORMAT_UNKNOWN) {
          scanTypes.push(type)
        }
      })
      // All requested formats were custom ISLI types ScanKit doesn't know →
      // scanTypes would be empty, which makes customScan not run/deliver
      // (scanTypes empty -> no ScanKit NN detection; ISLI decode uses frameCallback.)
      // so the camera runs and frames reach frameCallback (the native ISLI
      // decoder runs there, independent of ScanKit's scan types).
      if (scanTypes.length === 0) {
        // Only custom ISLI formats: scanTypes stays empty (ScanKit detection off).
      }
    }
    this.options = {
      scanTypes: scanTypes,
      enableMultiMode: true,
      enableAlbum: true
    }
    this.startCamera();
    this.startOrientationListening();
    // dart 中接收的 width 和 height 会转换为 double 类型，返回整数会导致异常
    result.success({
      "textureId": this.textureId,
      "size": {
        "width": this.scanWidth,
        "height": this.scanHeight
      },
      "naturalDeviceOrientation": this.getUIOrientation(),
      "sensorOrientation": this.facing === 1 ? 90 : 270,
      "handlesCropAndRotation": true,
      "currentTorchState": this.torch ? TorchState.on : TorchState.off,
      "numberOfCameras": getCameraManager(this.applicationContext!)?.getSupportedCameras()?.length ?? 1,
      "cameraDirection": this.facing
    });
  }

  // 重启相机流
  retryCamera(error: BusinessError) {
    if (this.retryScanTimes < 3 && error.code === scanCore.ScanErrorCode.INTERNAL_ERROR) {
      this.retryScanTimes++;
      let timeId = setTimeout(async () => {
        // 先暂停并释放相机流
        await this.stop(null);
        // 重启相机流
        this.startCamera();
        clearTimeout(timeId);
      }, 100)
    }
  }
  // 启动相机流
  startCamera() {
    customScan.init(this.options);
    this.setDisplay()
    this.startScan()
    if (this.torch) {
      customScan.openFlashLight()
    } else {
      customScan.closeFlashLight()
    }
    this.publishEvent({
      name: 'torchState',
      data: customScan.getFlashLightStatus() ? TorchState.on : TorchState.off
    });
  }

  // 返回自定义扫描结果的回调
  private scanCallback: AsyncCallback<scanBarcode.ScanResult[]> =
    async (error: BusinessError, result: scanBarcode.ScanResult[]) => {
      if (error && error.code) {
        Log.e(TAG, `Failed to get ScanResult by callback. Code: ${error.code}, message: ${error.message}`);
        this.retryCamera(error);
        return;
      }
      // 解析码值结果跳转应用服务页
      const _r: Barcode[] = result.map(item => {
        let size:ESObject = {
          width:this.toDoubleType(item.scanCodeRect!.right - item.scanCodeRect!.left),
          height:this.toDoubleType(item.scanCodeRect!.bottom - item.scanCodeRect!.top)
        };

        return {
          displayValue: item.originalValue,
          rawValue: item.originalValue,
          format: Barcode.convertScanType(item.scanType),
          type: BarcodeType.unknown,
          corners: [
            { x: this.toDoubleType(item.scanCodeRect!.left),  y: this.toDoubleType(item.scanCodeRect!.top) } as Point,
            { x: this.toDoubleType(item.scanCodeRect!.right),  y: this.toDoubleType(item.scanCodeRect!.top) } as Point,
            { x: this.toDoubleType(item.scanCodeRect!.right),  y: this.toDoubleType(item.scanCodeRect!.bottom) } as Point,
            { x: this.toDoubleType(item.scanCodeRect!.left),  y: this.toDoubleType(item.scanCodeRect!.bottom) } as Point,
          ],
          size:size
        } as Barcode;
      })
      this.callback(_r, this.imageBuffer, this.scanWidth, this.scanHeight);
    }
  // 返回相机帧的回调
  private frameCallback: AsyncCallback<customScan.ScanFrame> =
    async (error: BusinessError, frameResult: customScan.ScanFrame) => {
      this.imageBuffer = null;
      if (error) {
        Log.e(TAG, `Failed to get ScanFrame by callback. Code: ${error.code}, message: ${error.message}`);
        return;
      }

      // ---- ISLI: extract Y-plane from NV21 frame and dispatch decode ----
      // NV21 format: the first width*height bytes are the Y (luma) plane (8bpp grayscale).
      // Decode is dispatched asynchronously; the busy flag prevents concurrent decodes.
      if (this.shouldDecodeIsli || this.shouldDecodeIsliLine) {
        if (this.isliDecodeBusy) {
          // Drop frame.
        } else if (frameResult) {
          this.isliFrameCount++;
          if (this.isliFrameSkip > 0 && (this.isliFrameCount % (this.isliFrameSkip + 1)) !== 0) {
            // Throttled: skip this frame (reduce CPU load; enough time for better focus).
          } else {
            const ySize = frameResult.width * frameResult.height;
          const bufLen = frameResult.byteBuffer ? frameResult.byteBuffer.byteLength : 0;
          if (frameResult.byteBuffer && bufLen >= ySize) {
            const yPlane = new Uint8Array(frameResult.byteBuffer.slice(0, ySize));
            const fw = frameResult.width;
            const fh = frameResult.height;
            this.isliDecodeBusy = true;
            this.runISLIDecode(yPlane, fw, fh);
          } else {
            Log.w(TAG, `frame: buffer too small for Y-plane ${frameResult.width}x${frameResult.height} ySize=${ySize} bufLen=${bufLen}`);
          }
          } // throttle else
        }
      }

      if (frameResult && this.returnImage) {
        try {
          const EventWidth = frameResult.width;
          const EventHeight = frameResult.height;

          let sourcePotions: image.SourceOptions = {
            sourceDensity: 120,
            sourcePixelFormat: image.PixelMapFormat.NV21,
            sourceSize: { height: EventHeight, width: EventWidth }
          }
          let imageResource = image.createImageSource(frameResult.byteBuffer, sourcePotions)
          let opts: image.InitializationOptions = {
            editable: true,
            pixelFormat: image.PixelMapFormat.RGBA_8888,
            size: { height: EventHeight, width: EventWidth }
          }
          let pixelMap: image.PixelMap = await imageResource.createPixelMap(opts)
          // 修正相机预览流方向
          pixelMap.rotateSync(camera.ImageRotation.ROTATION_90)
          let packer: image.ImagePacker = image.createImagePacker()
          let packingOpt: image.PackingOption = { format: "image/jpeg", quality: 100 }
          let imgBuffer = await packer.packing(pixelMap, packingOpt);
          this.imageBuffer = new Uint8Array(imgBuffer)
        } catch (e) {
          Log.e(TAG, `Failed to create imageBuffer`);
        }
      }
    }

  startScan() {
    try {
      const viewControl: customScan.ViewControl = {
        width: this.scanWidth,
        height: this.scanHeight,
        surfaceId: this.surfaceId!,
      };
      customScan.start(viewControl, this.scanCallback, this.frameCallback)
    } catch (err) {
      Log.e(TAG, `Failed to start scan: ${err.message}`)
    }
  }

  // 竖屏时获取屏幕尺寸，设置预览流全屏示例
  setDisplay() {
    // 以手机为例计算宽高
    let displayClass = display.getDefaultDisplaySync();
    if (displayClass !== null) {
      let orientation = displayClass.orientation.valueOf()
      if (!!this.cameraResolutionValues && this.cameraResolutionValues.length >= 2) {
        let width = this.cameraResolutionValues[0];
        let height = this.cameraResolutionValues[1];
        if (orientation === 0 || orientation === 2) {
          let radio = height / width;
          this.scanWidth = this.toDoubleType(px2vp(displayClass.width));
          if (radio <= this.resolutionRatio[2]) {
            this.scanHeight = this.scanWidth;
          }else if (radio <= this.resolutionRatio[1]) {
            this.scanHeight = this.scanWidth * this.resolutionRatio[1];
          }else {
            this.scanHeight = this.scanWidth * this.resolutionRatio[0];
          }
        }else {
          let radio = width / height;
          this.scanHeight = this.toDoubleType(px2vp(displayClass.height));
          if (radio <= this.resolutionRatio[2]) {
            this.scanWidth = this.scanHeight;
          }else if (radio <= this.resolutionRatio[1]) {
            this.scanWidth = this.scanHeight * this.resolutionRatio[1];
          }else {
            this.scanWidth = this.scanHeight * this.resolutionRatio[0];
          }
        }
      }else {
        if (orientation === 0 || orientation === 2) {
          this.scanWidth = this.toDoubleType(px2vp(displayClass.width));
          this.scanHeight = this.scanWidth;
        }else {
          this.scanHeight = this.toDoubleType(px2vp(displayClass.height));
          this.scanWidth = this.scanHeight;
        }
      }
    }
  }

  toDoubleType(number: number): number {
    if (Number.isInteger(number)){
      number += 0.00000000001
    }
    return number;
  }

  private getUIOrientation(): string {
    let displayClass = display.getDefaultDisplaySync();
    let rotation = displayClass.rotation;
    switch (rotation) {
      case 0:
        return "PORTRAIT_UP";
      case 1:
        return "LANDSCAPE_LEFT";
      case 2:
        return "PORTRAIT_DOWN";
      case 3:
        return "LANDSCAPE_RIGHT";
      default:
        return "PORTRAIT_UP";
    }
  }

  private displayChangeCallback = (data: number) => {
    let orientation = this.getUIOrientation();
    if (orientation !== this.lastOrientation) {
      this.lastOrientation = orientation;
      this.deviceOrientationEventSink?.success(orientation);
    }
  }

  private startOrientationListening() {
    try {
      display.on("change", this.displayChangeCallback);
    } catch (e) {
      Log.e(TAG, `Failed to register display change listener: ${e.message}`);
    }
    // Push initial orientation immediately, matching Android's behavior
    let initialOrientation = this.getUIOrientation();
    this.lastOrientation = initialOrientation;
    this.deviceOrientationEventSink?.success(initialOrientation);
  }

  private stopOrientationListening() {
    try {
      display.off("change", this.displayChangeCallback);
    } catch (e) {
      Log.e(TAG, `Failed to unregister display change listener: ${e.message}`);
    }
    this.lastOrientation = null;
  }

  async pause(call: MethodCall, result: MethodResult) {
    let force: boolean = call.argument("force") ?? false

    if (this.isStart || force) {
      await customScan.stop();
      await customScan.release();
      this.isPaused = true;
      this.stopOrientationListening();
    }

    result?.success(null)
  }

  async stop(result: MethodResult | null) {
    if (this.isStart || this.isPaused) {
      this.isPaused = false;
      this.stopOrientationListening();
      try {
        this.isStart = false;
        await customScan.stop();
        await customScan.release();
      } catch (e) {
        try {
          await customScan.release();
        } catch (e) {
          this.isStart = true;
        }
      }
    }

    // Cleanup ISLI decoders. The native BCH tables are global and must be
    // freed behind any in-flight decode (the busy flag acts as a lock).
    if (this.shouldDecodeIsli || this.shouldDecodeIsliLine) {
      // Wait for any in-flight decode to complete
      while (this.isliDecodeBusy) {
        await new Promise<void>(resolve => setTimeout(resolve, 50));
      }
      if (this.shouldDecodeIsli) {
        this.isliDecoder.close(this.isliInstanceId);
        this.shouldDecodeIsli = false;
      }
      if (this.shouldDecodeIsliLine) {
        this.isliLineDecoder.close(this.isliInstanceId);
        this.shouldDecodeIsliLine = false;
      }
    }

    result?.success(null)
  }

  toggleTorch(call: MethodCall, result: MethodResult) {
    try {
      const light = customScan.getFlashLightStatus();
      if (light) {
        customScan.closeFlashLight()
      } else {
        customScan.openFlashLight()
      }
      const desired = !light;
      const plugin = this;
      setTimeout(() => {
        plugin.publishEvent({
          name: 'torchState',
          data: desired ? TorchState.on : TorchState.off
        });
      }, 50);
    } catch (e) {
      Log.e(TAG, `toggleTorch error: ${e}`);
    }
    result.success(null)
  }

  async analyzeImage(call: MethodCall, result: MethodResult) {
    let formats:number[] = call.argument("formats")
    let filePath: string = call.argument("filePath")
    let scanWindow: number[] | null = call.argument("scanWindow")

    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.ALL],
      enableMultiMode: true,
      enableAlbum: true
    }

    // ---- ISLI still-image decode (Android parity) ----
    // Runs on the calling thread behind isliDecodeBusy so it can't race the live
    // frame decoder's native BCH tables. Decodes the FULL image (no scanWindow
    // crop), matching Android's tryDecodeIsliFromFile.
    let isliBarcodes: Barcode[] = [];
    const wantIsli: boolean = !formats || formats.length === 0 || formats.indexOf(0) >= 0
      || formats.indexOf(BarcodeFormat.isli) >= 0
      || formats.indexOf(BarcodeFormat.isli_line_code) >= 0;
    if (wantIsli && filePath) {
      while (this.isliDecodeBusy) {
        await new Promise<void>(resolve => setTimeout(resolve, 30));
      }
      const gray = await this.fileToGrayscale(filePath);
      if (gray) {
        this.isliDecodeBusy = true;
        try {
          const wantAllAi: boolean = !formats || formats.length === 0 || formats.indexOf(0) >= 0;
          const wantLineAi: boolean = wantAllAi || (formats ? formats.indexOf(BarcodeFormat.isli_line_code) >= 0 : false);
          const wantIconAi: boolean = wantAllAi || (formats ? formats.indexOf(BarcodeFormat.isli) >= 0 : false);
          const aiHit: IsliCascadeHit | null = await runIsliCascade(gray.pixels, gray.w, gray.h, wantLineAi, wantIconAi);
          if (aiHit) isliBarcodes.push(this.buildBarcodeFromHit(aiHit, gray.w, gray.h, 0, 0));
        } finally {
          this.isliDecodeBusy = false;
        }
        Log.i(TAG, `analyzeImage: ISLI -> ${isliBarcodes.length} hit(s)`);
      }
    }

    // Helper to decode with the given InputImage; merges ISLI hits into the result.
    const doDecode = (inputImage: detectBarcode.InputImage) => {
      detectBarcode.decode(inputImage, options, (error: BusinessError, scanResult: Array<scanBarcode.ScanResult>) => {
        if (error && error.code) {
          // ScanKit failed — still return ISLI hits if any (Android fallback parity).
          if (isliBarcodes.length > 0) {
            result.success({ name: 'barcode', data: isliBarcodes })
          } else {
            result.error("MOBILE_SCANNER_BARCODE_ERROR", JSON.stringify(error) , null)
          }
          return
        }
        if (scanResult.length == 0) {
          result.success({
            name: 'barcode',
            data: isliBarcodes.length > 0 ? isliBarcodes : null
          })
          return
        }
        const barcodes: Barcode[] = scanResult.map(item => {
          let cornerPoints = item.cornerPoints;
          let corners: Array<Point> = []
          if (cornerPoints != undefined && cornerPoints != null) {
            corners = [
              { x: this.toDoubleType(this.scanWidth - cornerPoints[0].y), y: this.toDoubleType(cornerPoints[0].x)},
              { x: this.toDoubleType(this.scanWidth - cornerPoints[1].y), y: this.toDoubleType(cornerPoints[1].x)},
              { x: this.toDoubleType(this.scanWidth - cornerPoints[2].y), y: this.toDoubleType(cornerPoints[2].x)},
              { x: this.toDoubleType(this.scanWidth - cornerPoints[3].y), y: this.toDoubleType(cornerPoints[3].x)},
            ]
          }

          let size:ESObject = {
            width:this.toDoubleType(item.scanCodeRect!.right - item.scanCodeRect!.left),
            height:this.toDoubleType(item.scanCodeRect!.bottom - item.scanCodeRect!.top)
          }
          return {
            displayValue: item.originalValue,
            rawValue: item.originalValue,
            format: Barcode.convertScanType(item.scanType),
            type: BarcodeType.unknown,
            corners: corners,
            size: size
          } as Barcode;
        });
        result.success({
          name: 'barcode',
          data: isliBarcodes.length > 0 ? isliBarcodes.concat(barcodes) : barcodes
        })
      })
    }

    // If no scan window, decode the entire image
    if (!scanWindow || scanWindow.length < 4) {
      let inputImage: detectBarcode.InputImage = { uri: filePath }
      doDecode(inputImage)
      return
    }

    // Crop the image to the scan window region before decoding (ScanKit only;
    // ISLI already decoded the full image above, matching Android).
    try {
      let imageSource = image.createImageSource(filePath)
      let imageInfo = await imageSource.getImageInfo()
      let imgWidth = imageInfo.size.width
      let imgHeight = imageInfo.size.height

      // scanWindow coordinates are relative (0.0 to 1.0)
      let cropLeft = Math.round(scanWindow[0] * imgWidth)
      let cropTop = Math.round(scanWindow[1] * imgHeight)
      let cropRight = Math.round(scanWindow[2] * imgWidth)
      let cropBottom = Math.round(scanWindow[3] * imgHeight)

      // Clamp crop region to image bounds
      cropLeft = Math.max(0, cropLeft)
      cropTop = Math.max(0, cropTop)
      cropRight = Math.min(imgWidth, cropRight)
      cropBottom = Math.min(imgHeight, cropBottom)

      let cropWidth = cropRight - cropLeft
      let cropHeight = cropBottom - cropTop

      if (cropWidth <= 0 || cropHeight <= 0) {
        // Invalid crop region, fall back to full image
        let inputImage: detectBarcode.InputImage = { uri: filePath }
        doDecode(inputImage)
        return
      }

      let decodeOpts: image.DecodingOptions = {
        desiredSize: { width: cropWidth, height: cropHeight },
        desiredRegion: {
          x: cropLeft,
          y: cropTop,
          size: { width: cropWidth, height: cropHeight }
        }
      }
      let croppedPixelMap = await imageSource.createPixelMap(decodeOpts)
      let inputImage: ESObject = { pixelMap: croppedPixelMap }
      doDecode(inputImage as detectBarcode.InputImage)
      // Release the image source when done
      imageSource.release()
    } catch (e) {
      Log.e(TAG, `Failed to crop image for scanWindow: ${e.message}`)
      // Fall back to full image decoding
      let inputImage: detectBarcode.InputImage = { uri: filePath }
      doDecode(inputImage)
    }
  }

  setScale(call: MethodCall, result: MethodResult) {
    let zoomValue: number = call.args as number;
    try {
      customScan.setZoom(zoomValue);
      result.success(true);
    } catch (error) {
      result.success(false);
    }
  }

  resetScale(result: MethodResult) {
    try {
      customScan.setZoom(1);
      result.success(true);
    } catch (error) {
      result.success(false);
    }
  }

  updateScanWindow(call: MethodCall, result: MethodResult) {
    this.scanWindow = call.argument("rect")
    result.success(null)
  }

  /// 切换 ISLI 解码模式（与 iOS/Android 对齐）：只开图标码 / 只开线码 / 全开。
  /// 直接覆盖 start() 时按 formats 推导的 shouldDecodeIsli/shouldDecodeIsliLine；
  /// 目标解码器若尚未初始化（start 时按 formats 只初始化了部分）则在此补 init。
  private setISLIMode(call: MethodCall, result: MethodResult) {
    const iconRaw: ESObject = call.argument("icon");
    const lineRaw: ESObject = call.argument("line");
    const icon = typeof iconRaw === 'boolean' ? iconRaw : this.shouldDecodeIsli;
    const line = typeof lineRaw === 'boolean' ? lineRaw : this.shouldDecodeIsliLine;
    if (icon && !this.shouldDecodeIsli) {
      this.isliDecoder.init(this.isliInstanceId);
      this.isliDecoder.setLogLevel(2);
    }
    if (line && !this.shouldDecodeIsliLine) {
      this.isliLineDecoder.init(this.isliInstanceId);
      this.isliLineDecoder.setLogLevel(2);
    }
    this.shouldDecodeIsli = icon;
    this.shouldDecodeIsliLine = line;
    result.success(null);
  }

  /// 播放扫码成功提示音（与 iOS 对齐）。SDK 无公共"播系统音"API（playNotificationSound
  /// 不存在、systemSoundManager 需 API 23），故用 SoundPool 播放内置 beep.wav 资源。
  private soundPool: media.SoundPool | null = null;
  private beepSoundId: number = -1;

  private async playScanSound(result: MethodResult) {
    try {
      if (this.soundPool === null) {
        const renderInfo: audio.AudioRendererInfo = {
          usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
          rendererFlags: 0
        };
        this.soundPool = await media.createSoundPool(3, renderInfo);
      }
      if (this.beepSoundId < 0) {
        const fd = this.applicationContext!.resourceManager.getRawFdSync("beep.wav");
        this.beepSoundId = await this.soundPool.load(fd.fd, fd.offset, fd.length);
      }
      await this.soundPool.play(this.beepSoundId);
      result.success(null);
    } catch (e) {
      Log.e(TAG, `playScanSound failed: ${e.message}`);
      result.error("playScanSound", e.message, null);
    }
  }

  callback(barcodes: Barcode[], image: Uint8Array | null, width: number, height: number) {
    barcodes = barcodes.filter(barcode => {
      if (this.scanWindow) {
        return this.isBarcodeInScanWindow(barcode);
      } else {
        return true;
      }
    });
    if (barcodes.length == 0) {
      customScan.rescan();
    }

    if(!this.returnImage) {
      image = null
    }

    let imageinfo:ESObject = {
      bytes:image,
      width: width,
      height: height
    }

    this.publishEvent({
      "name": "barcode",
      "data": barcodes,
      "image": imageinfo
    })

    // 扫描完成后需要调用重新扫描继续识别
    setTimeout(() => {
      if (this.isStart && !this.isPaused) {
        try {
          customScan.rescan();
        } catch (err) {
          Log.e(TAG, `Failed to rescan: ${err.message}`)
        }
      }
    }, this.returnImage ? 250 : 100);
  }

  // ---- ISLI Decode Pipeline ----

  /**
   * Crop a tightly-packed grayscale Y-plane to the scanWindow region.
   *
   * The raw ScanKit frame is rotated 90° CW relative to the display (evidence:
   * `returnImage` does `rotateSync(ROTATION_90)`). The scanWindow is display-
   * normalized [left, top, right, bottom] in [0,1], so it must be mapped through
   * that rotation to get the frame-space rect:
   * frameX ∈ [left, right]·fw ,  frameY ∈ [top, bottom]·fh
   * offX/offY let decoded feature points be translated back to full-frame coords.
   * Returns null if the rect is too small.
   */
  private cropYToWindow(src: Uint8Array, fw: number, fh: number, sw: number[]): CroppedYPlane | null {
    // sw = [left, top, right, bottom]（Dart 侧统一语义，display 归一化坐标，y 向下）。
    // display = sensor 顺时针旋转 90°：display(x,y) → sensor(y, fh-1-x)。
    // 故 scanWindow 在 sensor 帧上的区域：
    //   frameX ∈ [top, bottom]·fw ，frameY ∈ [1-right, 1-left]·fh
    const cL = Math.max(0, Math.round(sw[1] * fw));
    const cR = Math.min(fw, Math.round(sw[3] * fw));
    const cT = Math.max(0, Math.round((1 - sw[2]) * fh));
    const cB = Math.min(fh, Math.round((1 - sw[0]) * fh));
    const cw = cR - cL;
    const ch = cB - cT;
    if (cw < 32 || ch < 32) return null;
    const dst = new Uint8Array(cw * ch);
    for (let r = 0; r < ch; r++) {
      const srcOff = (cT + r) * fw + cL;
      dst.set(src.subarray(srcOff, srcOff + cw), r * cw);
    }
    return { buf: dst, w: cw, h: ch, offX: cL, offY: cT };
  }

  /**
   * Build a Barcode from a cascade hit. offX/offY translate the hit feature points
   * (in the DECODED buffer coords - possibly a scanWindow crop) back to full-frame
   * pixel coords so the Dart overlay lines up with the preview.
   */
  private buildBarcodeFromHit(
    hit: IsliCascadeHit, imageWidth: number, imageHeight: number, offX: number, offY: number
  ): Barcode {
    const format: BarcodeFormat = hit.format === BarcodeFormat.isli ? BarcodeFormat.isli : BarcodeFormat.isli_line_code;
    // frameCallback 的 Y 平面是 sensor 方向（横），预览为顺时针旋转 90° 后的显示方向。
    // 特征点先加 off 得 sensor 全帧坐标，再旋转到显示坐标，Dart 黄点才能与预览对齐。
    const corners: Array<ESObject> = [];
    for (const pt of hit.featurePoints) {
      const sx = pt.x + offX;
      const sy = pt.y + offY;
      const dx = imageHeight - 1 - sy;
      const dy = sx;
      corners.push({ x: this.toDoubleType(dx), y: this.toDoubleType(dy) });
    }
    return {
      displayValue: hit.isliCode,
      rawValue: hit.isliCode,
      format: format,
      type: BarcodeType.text,
      corners: corners,
      size: {
        width: this.toDoubleType(imageHeight),
        height: this.toDoubleType(imageWidth)
      }
    } as Barcode;
  }

  /**
   * Build + emit an ISLI Barcode via the event channel (live path).
   */
  private emitCascadeHit(
    hit: IsliCascadeHit, imageWidth: number, imageHeight: number, offX: number, offY: number
  ): void {
    const barcode = this.buildBarcodeFromHit(hit, imageWidth, imageHeight, offX, offY);
    Log.i(TAG, `emitISLI: format=${barcode.format} code=${hit.isliCode} points=${hit.featurePoints.length} off=(${offX},${offY})`);
    // 携带显示方向图像尺寸（Dart 黄点/坐标映射依赖 capture.size），结构与 Android/iOS 一致。
    const imageinfo: ESObject = {
      bytes: null,
      width: this.toDoubleType(imageHeight),
      height: this.toDoubleType(imageWidth)
    };
    this.publishEvent({
      "name": "barcode",
      "data": [barcode],
      "image": imageinfo
    });
  }

  /**
   * Run ISLI decode on a TaskPool worker thread (non-blocking).
   *
   * Pipeline: crop to scanWindow (if set, rotation-aware) → cascade
   * (line 0°/+90°, then icon) on the cropped buffer. A miss returns immediately —
   * no full-frame fallback — so only the viewfinder region is decoded (matches
   * Android strict cropped decode). The next frame retries.
   *
   * IMPORTANT: taskpool.execute TRANSFERS (detaches) the Uint8Array argument's
   * ArrayBuffer to the worker. `yPlane` is the pristine master and is NEVER passed
   * directly; each dispatch gets a cloneU8() copy (or a fresh rotate/crop buffer).
   */
  private async runISLIDecode(yPlane: Uint8Array, width: number, height: number): Promise<void> {
    const tTotal = Date.now();
    try {
      // 1) Crop to scanWindow (rotation-aware) if active — zooms into the
      //    viewfinder so the shield fills more of the decoded image (bigger
      //    frame_size → more reliable locate) and skips decoding outside it.
      let decBuf: Uint8Array = yPlane;
      let decW = width;
      let decH = height;
      let offX = 0;
      let offY = 0;
      let cropped = false;
      if (this.scanWindow && this.scanWindow.length >= 4) {
        const c = this.cropYToWindow(yPlane, width, height, this.scanWindow);
        if (c) {
          decBuf = c.buf; decW = c.w; decH = c.h; offX = c.offX; offY = c.offY; cropped = true;
          Log.i(TAG, `runISLIDecode: crop scanWindow -> ${decW}x${decH} off=(${offX},${offY})`);
        }
      }

      // 2) Cascade on the (cropped) buffer. No full-frame fallback — a miss means
      //    the shield isn't in the viewfinder (or the crop mapping is off); the
      //    next frame retries. Matches Android's strict cropped decode.
      const hit: IsliCascadeHit | null = await runIsliCascade(decBuf, decW, decH, this.shouldDecodeIsliLine, this.shouldDecodeIsli);
      if (hit) {
        this.emitCascadeHit(hit, width, height, offX, offY);
        Log.i(TAG, `runISLIDecode: HIT ${cropped ? '(cropped)' : '(full)'} ${decW}x${decH} total ${Date.now() - tTotal}ms`);
        return;
      }

      Log.i(TAG, `runISLIDecode: NO HIT total ${Date.now() - tTotal}ms ${width}x${height}`);
    } catch (e) {
      Log.e(TAG, `runISLIDecode: exception: ${e.message}`);
    } finally {
      this.isliDecodeBusy = false;
    }
  }

  /**
   * Build an ISLI decode result as a Barcode. offX/offY translate the native
   * feature points (which are in the DECODED buffer's coords — possibly a
   * scanWindow crop) back to full-frame pixel coords, so Dart's overlay lines up
   * with the preview regardless of whether cropping was applied.
   */
  /**
   * Load an image file and convert to 8bpp grayscale (BT.601 luma) for the native
   * ISLI decoders. Mirrors Android's convertFileToGrayscale + convertJpegToGrayscale.
   * Used by analyzeImage (still-image ISLI decode).
   */
  private async fileToGrayscale(filePath: string): Promise<GrayImage | null> {
    let imageSource: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    try {
      imageSource = image.createImageSource(filePath);
      const info = await imageSource.getImageInfo();
      const w = info.size.width;
      const h = info.size.height;
      const opts: image.InitializationOptions = {
        editable: false,
        pixelFormat: image.PixelMapFormat.RGBA_8888,
        size: { width: w, height: h }
      };
      pixelMap = await imageSource.createPixelMap(opts);
      const rgbaBuf = new ArrayBuffer(w * h * 4);
      await pixelMap.readPixelsToBuffer(rgbaBuf);
      const rgba = new Uint8Array(rgbaBuf);
      const gray = new Uint8Array(w * h);
      const n = w * h;
      for (let i = 0; i < n; i++) {
        const r = rgba[i * 4];
        const g = rgba[i * 4 + 1];
        const b = rgba[i * 4 + 2];
        gray[i] = (r * 77 + g * 150 + b * 29) >> 8;  // BT.601 luma
      }
      return { pixels: gray, w: w, h: h };
    } catch (e) {
      Log.e(TAG, `fileToGrayscale failed: ${e.message}`);
      return null;
    } finally {
      if (pixelMap) {
        try { pixelMap.release(); } catch (e) { }
      }
      if (imageSource) {
        try { imageSource.release(); } catch (e) { }
      }
    }
  }

  /**
   * Synchronously decode ISLI (line then icon, first-success-wins) from a grayscale
   * buffer. Used by analyzeImage. Does NOT apply the scanWindow gate (Android also
   * decodes the full still image). Lazily inits the native decoders.
   * Caller MUST hold isliDecodeBusy — native BCH tables are global/non-thread-safe.
   */
  private isBarcodeInScanWindow(barcode: Barcode): boolean {
    const corners = barcode.corners;
    const left = Math.round(this.scanWindow![0] * this.scanWidth);
    const top = Math.round(this.scanWindow![1] * this.scanHeight);
    const right = Math.round(this.scanWindow![2] * this.scanWidth);
    const bottom = Math.round(this.scanWindow![3] * this.scanHeight);
    return corners.reduce((r, item) => r && item.x >= left && item.x <= right && item.y >= top && item.y <= bottom,
      true)
  }

  errorCallback(error: string) {
    this.publishEvent({
      "name": "error",
      "data": error
    })
  }

  torchCallback(error: BusinessError, bool: boolean) {
    if (error) {
      return;
    }
    this.publishEvent({
      name: 'torchState',
      data: customScan.getFlashLightStatus() ? TorchState.on : TorchState.off
    });
  }
}
