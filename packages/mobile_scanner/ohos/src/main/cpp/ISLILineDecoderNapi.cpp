#include <napi/native_api.h>
#include <hilog/log.h>
#include <cstring>
#include "linecode/ISLILineDecoder.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "ISLILineDecoder"

// ---- nativeInit ----
static napi_value NativeInit(napi_env env, napi_callback_info info) {
    int ret = isli_line_decoder_init();
    OH_LOG_INFO(LOG_APP, "nativeInit: ret=%{public}d (1=ok, 0=already/failed)", ret);
    if (ret == 0) {
        OH_LOG_ERROR(LOG_APP, "ISLI line decoder already initialized or init failed");
    }
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ---- nativeUninit ----
static napi_value NativeUninit(napi_env env, napi_callback_info info) {
    int ret = isli_line_decoder_uninit();
    OH_LOG_INFO(LOG_APP, "nativeUninit: ret=%{public}d (1=ok, 0=not-init/failed)", ret);
    if (ret == 0) {
        OH_LOG_ERROR(LOG_APP, "ISLI line decoder not initialized or uninit failed");
    }
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// ---- nativeSetLogLevel ----
// level: 0=OFF 1=ERROR 2=WARN 3=INFO 4=DEBUG
static napi_value NativeSetLogLevel(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc >= 1) {
        int level;
        napi_get_value_int32(env, args[0], &level);
        ild_set_log_level(level);
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// Build result object:
// { isliCode: string, featurePoints: [{x,y} x2], brightness: number, isBlur: boolean }
static napi_value BuildResult(napi_env env, const char* isli_code,
                               const short* feax, const short* feay,
                               int brightness, int is_blur) {
    napi_value result;
    napi_create_object(env, &result);

    // isliCode
    napi_value codeValue;
    napi_create_string_utf8(env, isli_code, NAPI_AUTO_LENGTH, &codeValue);
    napi_set_named_property(env, result, "isliCode", codeValue);

    // featurePoints: [{x, y} x 2]
    napi_value pointsArray;
    napi_create_array(env, &pointsArray);

    for (int i = 0; i < 2; i++) {
        napi_value point;
        napi_create_object(env, &point);

        napi_value xVal, yVal;
        napi_create_int32(env, (int)feax[i], &xVal);
        napi_create_int32(env, (int)feay[i], &yVal);
        napi_set_named_property(env, point, "x", xVal);
        napi_set_named_property(env, point, "y", yVal);

        napi_set_element(env, pointsArray, i, point);
    }

    napi_set_named_property(env, result, "featurePoints", pointsArray);

    // brightness
    napi_value brightnessVal;
    napi_create_int32(env, brightness, &brightnessVal);
    napi_set_named_property(env, result, "brightness", brightnessVal);

    // isBlur
    napi_value blurVal;
    napi_get_boolean(env, is_blur != 0, &blurVal);
    napi_set_named_property(env, result, "isBlur", blurVal);

    return result;
}

// nativeDecode(buf: Uint8Array, w: number, h: number, bpl: number) -> object | null
static napi_value NativeDecode(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 4) {
        OH_LOG_WARN(LOG_APP, "nativeDecode: bad argc=%{public}zu (need 4)", argc);
        napi_value result;
        napi_get_null(env, &result);
        return result;
    }

    // Extract Uint8Array buffer
    void* data = nullptr;
    size_t byteLength = 0;
    napi_value arrayBuffer;
    napi_get_typedarray_info(env, args[0], nullptr, &byteLength, &data, &arrayBuffer, nullptr);

    if (!data || byteLength == 0) {
        OH_LOG_WARN(LOG_APP, "nativeDecode: empty/null pixel buffer (data=%{public}d byteLen=%{public}zu)", data != nullptr, byteLength);
        napi_value result;
        napi_get_null(env, &result);
        return result;
    }

    // Extract int params
    int w, h, bpl;
    napi_get_value_int32(env, args[1], &w);
    napi_get_value_int32(env, args[2], &h);
    napi_get_value_int32(env, args[3], &bpl);

    IMAGE image((unsigned char*)data, w, h, bpl);
    char isli_code[20] = {0};
    short feax[2] = {0};
    short feay[2] = {0};
    int brightness = 0;
    int is_blur = 0;

    int ret = isli_line_decoder_do_image_decode(&image, isli_code, feax, feay, &brightness, &is_blur);

    if (ret != 1) {
        OH_LOG_INFO(LOG_APP, "nativeDecode: FAIL ret=%{public}d (no line code / rejected) brightness=%{public}d isBlur=%{public}d", ret, brightness, is_blur);
        napi_value result;
        napi_get_null(env, &result);
        return result;
    }

    OH_LOG_INFO(LOG_APP, "nativeDecode: OK code=%{public}s brightness=%{public}d isBlur=%{public}d", isli_code, brightness, is_blur);
    return BuildResult(env, isli_code, feax, feay, brightness, is_blur);
}

// Rotate a grayscale plane 90° clockwise: src (w x h, row stride bpl) -> dst (h x w).
// dst must hold w*h bytes; new row stride = h. ~0.5ms in C (vs ~3.7s for the same
// loop in ArkTS on a taskpool worker, which was the decode-cycle bottleneck).
static void rotate_y90_cw(const unsigned char* src, int w, int h, int bpl, unsigned char* dst) {
    int nw = h;
    for (int y = 0; y < h; y++) {
        const unsigned char* srow = src + (size_t)y * bpl;
        for (int x = 0; x < w; x++) {
            dst[(size_t)x * nw + (h - 1 - y)] = srow[x];
        }
    }
}

// nativeDecodeRotated(buf, w, h, bpl): rotate the image 90° CW then decode.
// Used for the line decoder's +90 retry (it only reads landscape). Feature points
// are back-rotated to the original (un-rotated) coordinate space before returning.
static napi_value NativeDecodeRotated(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4];
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    if (argc < 4) {
        OH_LOG_WARN(LOG_APP, "nativeDecodeRotated: bad argc=%{public}zu (need 4)", argc);
        napi_value result;
        napi_get_null(env, &result);
        return result;
    }

    void* data = nullptr;
    size_t byteLength = 0;
    napi_value arrayBuffer;
    napi_get_typedarray_info(env, args[0], nullptr, &byteLength, &data, &arrayBuffer, nullptr);

    if (!data || byteLength == 0) {
        napi_value result;
        napi_get_null(env, &result);
        return result;
    }

    int w, h, bpl;
    napi_get_value_int32(env, args[1], &w);
    napi_get_value_int32(env, args[2], &h);
    napi_get_value_int32(env, args[3], &bpl);

    // Rotate 90° CW into a scratch buffer. New image: width=h, height=w, bpl=h.
    int nw = h;
    int nh = w;
    unsigned char* rotated = new unsigned char[(size_t)nw * nh];
    rotate_y90_cw((const unsigned char*)data, w, h, bpl, rotated);

    IMAGE image(rotated, nw, nh, nw);
    char isli_code[20] = {0};
    short feax[2] = {0};
    short feay[2] = {0};
    int brightness = 0;
    int is_blur = 0;

    int ret = isli_line_decoder_do_image_decode(&image, isli_code, feax, feay, &brightness, &is_blur);
    delete[] rotated;

    if (ret != 1) {
        OH_LOG_INFO(LOG_APP, "nativeDecodeRotated: FAIL ret=%{public}d brightness=%{public}d isBlur=%{public}d", ret, brightness, is_blur);
        napi_value result;
        napi_get_null(env, &result);
        return result;
    }

    // Back-rotate feature points from rotated (nw x nh) to original (w x h) space:
    // 90° CW sent orig(x,y) -> rot(col=h-1-y, row=x), so inverse: rot(Rx,Ry) -> orig(Ry, h-1-Rx).
    for (int i = 0; i < 2; i++) {
        short rx = feax[i];
        short ry = feay[i];
        feax[i] = ry;
        feay[i] = (short)(h - 1 - rx);
    }

    OH_LOG_INFO(LOG_APP, "nativeDecodeRotated: OK code=%{public}s brightness=%{public}d", isli_code, brightness);
    return BuildResult(env, isli_code, feax, feay, brightness, is_blur);
}

// Module registration
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"nativeInit", nullptr, NativeInit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"nativeUninit", nullptr, NativeUninit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"nativeDecode", nullptr, NativeDecode, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"nativeDecodeRotated", nullptr, NativeDecodeRotated, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"nativeSetLogLevel", nullptr, NativeSetLogLevel, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

static napi_module module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "isli_line_decoder",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterISLILineDecoderModule(void) {
    napi_module_register(&module);
}
