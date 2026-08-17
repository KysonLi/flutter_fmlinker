import isliLineNative from 'libisli_line_decoder.so';
import { taskpool } from '@kit.ArkTS';
import { ISLIPoint } from './ISLIDecoder';

/**
 * Result from the ISLI line (1D barcode) decoder.
 */
export interface ISLILineResult {
  isliCode: string;
  featurePoints: Array<ISLIPoint>;
  brightness: number;
  isBlur: boolean;
}

/**
 * Native module interface for the ISLI line decoder shared library.
 */
interface NativeISLILineDecoder {
  nativeInit(): void;
  nativeUninit(): void;
  nativeDecode(buf: Uint8Array, w: number, h: number, bpl: number): ISLILineResult | null;
  nativeSetLogLevel(level: number): void;
}

/**
 * @Concurrent decode entry point executed on a TaskPool worker thread.
 *
 * Offloading is mandatory: nativeDecode is a synchronous ~2s call that would
 * otherwise block the camera frame callback (main) thread and freeze the UI.
 * The native BCH tables are process-global and non-thread-safe; the caller
 * (MobileScannerPlugin) serializes access via isliDecodeBusy so at most one
 * decode is in flight at any time.
 */
@Concurrent
function decodeLineOnTaskPool(pixels: Uint8Array, w: number, h: number, bpl: number): ISLILineResult | null {
  const native: NativeISLILineDecoder = isliLineNative as NativeISLILineDecoder;
  return native.nativeDecode(pixels, w, h, bpl);
}

/**
 * ArkTS wrapper for the ISLI line (1D barcode) decoder native library.
 *
 * Manages native decoder lifecycle with reference counting. The native
 * BCH tables are global and non-thread-safe.
 *
 * The line decoder is compute-bound (~2s per frame) and runs as the
 * first step in the serial decode chain (line → icon, first-success-wins).
 *
 * Usage:
 *   const decoder = new ISLILineDecoder();
 *   decoder.init("my_instance");
 *   const result = decoder.decode(yPlane, width, height, width);
 *   decoder.close("my_instance");
 */
export class ISLILineDecoder {
  private static native: NativeISLILineDecoder = isliLineNative as NativeISLILineDecoder;
  private static initialized: boolean = false;
  private static instances: Set<string> = new Set();

  /**
   * Initialize the native decoder. Safe to call multiple times.
   */
  init(id: string): void {
    if (!ISLILineDecoder.initialized) {
      ISLILineDecoder.native.nativeInit();
      ISLILineDecoder.initialized = true;
    }
    ISLILineDecoder.instances.add(id);
  }

  /**
   * Release this instance. When the last instance is closed,
   * the native decoder is uninitialized.
   */
  close(id: string): void {
    ISLILineDecoder.instances.delete(id);
    if (ISLILineDecoder.instances.size === 0 && ISLILineDecoder.initialized) {
      ISLILineDecoder.native.nativeUninit();
      ISLILineDecoder.initialized = false;
    }
  }

  /**
   * Decode an ISLI line code from grayscale (8bpp) pixel data.
   *
   * @param pixels - Uint8Array of grayscale pixels.
   * @param w - Image width in pixels.
   * @param h - Image height in pixels.
   * @param bpl - Bytes per line (row stride).
   * @returns Decoded result with ISLI code, 2 feature points,
   *          brightness (0-255), and isBlur flag, or null on failure.
   */
  decode(pixels: Uint8Array, w: number, h: number, bpl: number): ISLILineResult | null {
    return ISLILineDecoder.native.nativeDecode(pixels, w, h, bpl);
  }

  /**
   * Asynchronously decode on a TaskPool worker thread.
   *
   * Unlike {@link decode}, this does NOT block the calling thread - the ~2s
   * native decode runs on a worker, keeping the UI/main thread responsive.
   * The caller MUST ensure only one decode is in flight at a time, because
   * the native BCH tables are not thread-safe (see isliDecodeBusy).
   *
   * @returns Decoded result, or null on failure.
   */
  async decodeAsync(pixels: Uint8Array, w: number, h: number, bpl: number): Promise<ISLILineResult | null> {
    const task: taskpool.Task = new taskpool.Task(decodeLineOnTaskPool, pixels, w, h, bpl);
    const result: ESObject = await taskpool.execute(task);
    return result ? (result as ISLILineResult) : null;
  }

  /**
   * Set the native decoder log level for debugging.
   * @param level - 0=OFF, 1=ERROR, 2=WARN, 3=INFO(default), 4=DEBUG
   */
  setLogLevel(level: number): void {
    ISLILineDecoder.native.nativeSetLogLevel(level);
  }

  /**
   * Returns true if any instance has initialized the native decoder.
   */
  isInitialized(): boolean {
    return ISLILineDecoder.initialized;
  }
}
