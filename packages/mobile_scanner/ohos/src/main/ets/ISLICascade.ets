import isliIconNative from 'libisli_icon_decoder.so';
import isliLineNative from 'libisli_line_decoder.so';
import { taskpool } from '@kit.ArkTS';
import { ISLIPoint, ISLIIconResult } from './ISLIDecoder';
import { ISLILineResult } from './ISLILineDecoder';

/** A successful ISLI cascade decode (format id + code + feature points). */
export interface IsliCascadeHit {
  isliCode: string;
  featurePoints: Array<ISLIPoint>;
  format: number; // BarcodeFormat.isli(8192) | isli_line_code(16384)
}

interface NativeIconDecoder {
  nativeInit(): void;
  nativeUninit(): void;
  nativeDecode(buf: Uint8Array, w: number, h: number, bpl: number): ISLIIconResult | null;
  nativeSetLogLevel(level: number): void;
}

interface NativeLineDecoder {
  nativeInit(): void;
  nativeUninit(): void;
  nativeDecode(buf: Uint8Array, w: number, h: number, bpl: number): ISLILineResult | null;
  nativeDecodeRotated(buf: Uint8Array, w: number, h: number, bpl: number): ISLILineResult | null;
  nativeSetLogLevel(level: number): void;
}

/**
 * @Concurrent full ISLI cascade on a TaskPool worker: line(0°) -> line(+90°) -> icon,
 * first-success-wins.
 *
 * Runs entirely inside ONE taskpool task so the main (UI) thread only dispatches +
 * awaits once - no main-thread round-trips between steps (those round-trips were the
 * startup-stall culprit: each `await` continuation had to wait for the main thread,
 * which ScanKit's NN detection / camera warmup was blocking, stretching a ~60ms
 * decode to seconds). Here the steps run back-to-back on the worker.
 *
 * ArkTS @Concurrent functions may only reference imported or local variables, so the
 * per-call clone is inlined here; the +90° rotation is done natively (nativeDecodeRotated)
 * since the ArkTS rotate loop is ~1000x slower on a worker. The buffer is cloned per
 * native call (worker-local) so `pixels` stays clean across the line/icon steps.
 * BCH tables are process-global & non-thread-safe; the caller serializes via
 * isliDecodeBusy so only one cascade is in flight at a time.
 */
@Concurrent
export function decodeIsliCascade(
  pixels: Uint8Array, w: number, h: number, wantLine: boolean, wantIcon: boolean
): IsliCascadeHit | null {
  const icon: NativeIconDecoder = isliIconNative as NativeIconDecoder;
  const line: NativeLineDecoder = isliLineNative as NativeLineDecoder;
  const bpl = w;
  const FMT_ISLI = 8192;
  const FMT_ISLI_LINE = 16384;

  // icon-first: faster path for the common case (icon scanning). icon is
  // 4-way robust and locates quickly (~10-20ms). When it hits we skip the
  // line cascade entirely. Native decoders are read-only (IMAGE only stores
  // the pointer; g_preprocess defaults to 0), so no defensive clone.
  if (wantIcon) {
    const r = icon.nativeDecode(pixels, w, h, bpl);
    if (r) {
      return { isliCode: r.isliCode, featurePoints: r.featurePoints, format: FMT_ISLI };
    }
  }
  if (wantLine) {
    // The cropped buffer is display-oriented (portrait); the line decoder only
    // reads landscape, so we always run the +90° rotated path (native rotate
    // + decode). The 0° attempt is skipped — it predictably misses every frame.
    const r = line.nativeDecodeRotated(pixels, w, h, bpl);
    if (r) {
      return { isliCode: r.isliCode, featurePoints: r.featurePoints, format: FMT_ISLI_LINE };
    }
  }
  return null;
}

/**
 * Dispatch the ISLI cascade to a TaskPool worker and await the hit (or null).
 * `pixels` is transferred (detached) to the worker; the caller must not reuse it.
 */
export async function runIsliCascade(
  pixels: Uint8Array, w: number, h: number, wantLine: boolean, wantIcon: boolean
): Promise<IsliCascadeHit | null> {
  const task: taskpool.Task = new taskpool.Task(decodeIsliCascade, pixels, w, h, wantLine, wantIcon);
  const result: ESObject = await taskpool.execute(task);
  return result ? (result as IsliCascadeHit) : null;
}
