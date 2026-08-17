import isliIconNative from 'libisli_icon_decoder.so';
import { taskpool } from '@kit.ArkTS';

/**
 * A 2D point in the ISLI feature point array.
 */
export interface ISLIPoint {
  x: number;
  y: number;
}

/**
 * Result from the ISLI icon (2D shield) decoder.
 */
export interface ISLIIconResult {
  isliCode: string;
  featurePoints: Array<ISLIPoint>;
}

/**
 * Native module interface for the ISLI icon decoder shared library.
 */
interface NativeISLIIconDecoder {
  nativeInit(): void;
  nativeUninit(): void;
  nativeDecode(buf: Uint8Array, w: number, h: number, bpl: number): ISLIIconResult | null;
  nativeSetLogLevel(level: number): void;
}

/**
 * @Concurrent decode entry point executed on a TaskPool worker thread.
 *
 * Offloading keeps the synchronous ~70ms native decode off the main thread.
 * The native BCH tables are process-global and non-thread-safe; the caller
 * (MobileScannerPlugin) serializes access via isliDecodeBusy so at most one
 * decode is in flight at any time.
 */
@Concurrent
function decodeIconOnTaskPool(pixels: Uint8Array, w: number, h: number, bpl: number): ISLIIconResult | null {
  const native: NativeISLIIconDecoder = isliIconNative as NativeISLIIconDecoder;
  return native.nativeDecode(pixels, w, h, bpl);
}

/**
 * ArkTS wrapper for the ISLI icon (2D shield) decoder native library.
 *
 * Manages native decoder lifecycle with reference counting — the native
 * BCH tables are global and non-thread-safe, so init/uninit must be
 * called exactly once across all instances.
 *
 * Usage:
 *   const decoder = new ISLIDecoder();
 *   decoder.init("my_instance");
 *   const result = decoder.decode(yPlane, width, height, width);
 *   decoder.close("my_instance");
 */
export class ISLIDecoder {
  private static native: NativeISLIIconDecoder = isliIconNative as NativeISLIIconDecoder;
  private static initialized: boolean = false;
  private static instances: Set<string> = new Set();

  /**
   * Initialize the native decoder. Safe to call multiple times —
   * the native library is loaded once and reference-counted.
   */
  init(id: string): void {
    if (!ISLIDecoder.initialized) {
      ISLIDecoder.native.nativeInit();
      ISLIDecoder.initialized = true;
    }
    ISLIDecoder.instances.add(id);
  }

  /**
   * Release this instance. When the last instance is closed,
   * the native decoder is uninitialized (BCH tables freed).
   */
  close(id: string): void {
    ISLIDecoder.instances.delete(id);
    if (ISLIDecoder.instances.size === 0 && ISLIDecoder.initialized) {
      ISLIDecoder.native.nativeUninit();
      ISLIDecoder.initialized = false;
    }
  }

  /**
   * Decode an ISLI icon code from grayscale (8bpp) pixel data.
   *
   * @param pixels - Uint8Array of grayscale pixels (one byte per pixel).
   * @param w - Image width in pixels.
   * @param h - Image height in pixels.
   * @param bpl - Bytes per line (row stride).
   * @returns Decoded result with ISLI code and 6 feature points, or null on failure.
   */
  decode(pixels: Uint8Array, w: number, h: number, bpl: number): ISLIIconResult | null {
    return ISLIDecoder.native.nativeDecode(pixels, w, h, bpl);
  }

  /**
   * Asynchronously decode on a TaskPool worker thread.
   *
   * Unlike {@link decode}, this does NOT block the calling thread - the native
   * decode runs on a worker, keeping the UI/main thread responsive. The caller
   * MUST ensure only one decode is in flight at a time, because the native BCH
   * tables are not thread-safe (see isliDecodeBusy).
   *
   * @returns Decoded result, or null on failure.
   */
  async decodeAsync(pixels: Uint8Array, w: number, h: number, bpl: number): Promise<ISLIIconResult | null> {
    const task: taskpool.Task = new taskpool.Task(decodeIconOnTaskPool, pixels, w, h, bpl);
    const result: ESObject = await taskpool.execute(task);
    return result ? (result as ISLIIconResult) : null;
  }

  /**
   * Set the native decoder log level for debugging.
   * @param level - 0=OFF, 1=ERROR, 2=WARN, 3=INFO(default), 4=DEBUG
   */
  setLogLevel(level: number): void {
    ISLIDecoder.native.nativeSetLogLevel(level);
  }

  /**
   * Returns true if any instance has initialized the native decoder.
   */
  isInitialized(): boolean {
    return ISLIDecoder.initialized;
  }
}
