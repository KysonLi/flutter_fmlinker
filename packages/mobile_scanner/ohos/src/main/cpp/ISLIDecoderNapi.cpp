#include <napi/native_api.h>
#include <hilog/log.h>
#include <cstring>
#include "isli/ImageType.h"
#include "isli/ISLIIconDecoder.h"
#include "isli/IldLog.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "ISLIDecoder"

static napi_value NativeInit(napi_env env, napi_callback_info info) {
    int ret = isli_icon_decoder_init();
    OH_LOG_INFO(LOG_APP, "nativeInit: ret=%{public}d (1=ok, 0=already/failed)", ret);
    if (ret == 0) {
        OH_LOG_ERROR(LOG_APP, "ISLI icon decoder already initialized or init failed");
    }
    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

static napi_value NativeUninit(napi_env env, napi_callback_info info) {
    int ret = isli_icon_decoder_uninit();
    OH_LOG_INFO(LOG_APP, "nativeUninit: ret=%{public}d (1=ok, 0=not-init/failed)", ret);
    if (ret == 0) {
        OH_LOG_ERROR(LOG_APP, "ISLI icon decoder not initialized or uninit failed");
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
        islii_set_log_level(level);
    }

    napi_value result;
    napi_get_undefined(env, &result);
    return result;
}

// Build { isliCode: string, featurePoints: [{x:number, y:number} x6] }
static napi_value BuildResult(napi_env env, const char* isli_code,
                               const short* feax, const short* feay) {
    napi_value result;
    napi_create_object(env, &result);

    // isliCode
    napi_value codeValue;
    napi_create_string_utf8(env, isli_code, NAPI_AUTO_LENGTH, &codeValue);
    napi_set_named_property(env, result, "isliCode", codeValue);

    // featurePoints: [{x, y} x 6]
    napi_value pointsArray;
    napi_create_array(env, &pointsArray);

    for (int i = 0; i < 6; i++) {
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
    short feax[6] = {0};
    short feay[6] = {0};

    int ret = isli_icon_decoder_do_image_decode(&image, isli_code, feax, feay);

    if (ret != 1) {
        OH_LOG_INFO(LOG_APP, "nativeDecode: FAIL ret=%{public}d (no icon / locate or decode failed)", ret);
        napi_value result;
        napi_get_null(env, &result);
        return result;
    }

    OH_LOG_INFO(LOG_APP, "nativeDecode: OK code=%{public}s", isli_code);
    return BuildResult(env, isli_code, feax, feay);
}

// Module registration
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"nativeInit", nullptr, NativeInit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"nativeUninit", nullptr, NativeUninit, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"nativeDecode", nullptr, NativeDecode, nullptr, nullptr, nullptr, napi_default, nullptr},
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
    .nm_modname = "isli_icon_decoder",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterISLIIconDecoderModule(void) {
    napi_module_register(&module);
}
