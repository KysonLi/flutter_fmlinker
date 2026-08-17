#include <string.h>
#include <jni.h>
#include <android/log.h>
#include "linecode/ISLILineDecoder.h"

#define LOG_TAG "ISLILineDecoder"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C"
JNIEXPORT void JNICALL
Java_com_google_1mlkit_1barcode_1scanning_ISLILineDecoderHandler_nativeInit(JNIEnv *env, jclass clazz) {
    int ret = isli_line_decoder_init();
    if (ret == 0) {
        LOGE("ISLI line decoder already initialized or init failed");
    }
}

extern "C"
JNIEXPORT void JNICALL
Java_com_google_1mlkit_1barcode_1scanning_ISLILineDecoderHandler_nativeUninit(JNIEnv *env, jclass clazz) {
    int ret = isli_line_decoder_uninit();
    if (ret == 0) {
        LOGE("ISLI line decoder not initialized or uninit failed");
    }
}

// 运行时调整 linecode 解码日志级别（logcat tag = isliline）。
// level: 0=OFF 1=ERROR 2=WARN 3=INFO(默认) 4=DEBUG。
extern "C"
JNIEXPORT void JNICALL
Java_com_google_1mlkit_1barcode_1scanning_ISLILineDecoderHandler_nativeSetLogLevel(JNIEnv *env, jclass clazz, jint level) {
    (void)env; (void)clazz;
    ild_set_log_level((int)level);
    __android_log_print(ANDROID_LOG_INFO, "isliline", "log level set to %d (0=off 1=err 2=warn 3=info 4=debug)", (int)level);
}

//extern "C"
//JNIEXPORT void JNICALL
//Java_com_google_1mlkit_1barcode_1scanning_ISLILineDecoderHandler_nativeClearCache(JNIEnv *env, jclass clazz) {
//    isli_line_decoder_clear_cache();
//}

// Build HashMap<String, Object> result with:
//   "isliCode"      -> String
//   "featurePoints" -> ArrayList<HashMap<String, Integer>>  (2 points: x, y)
//   "brightness"    -> Integer  (0 ~ 255)
//   "isBlur"        -> Boolean
static jobject buildResultMap(JNIEnv *env, const char *isli_code,
                              const short *feax, const short *feay,
                              int brightness, int is_blur) {
    jclass hashMapClass = env->FindClass("java/util/HashMap");
    jmethodID hashMapInit = env->GetMethodID(hashMapClass, "<init>", "()V");
    jmethodID hashMapPut = env->GetMethodID(hashMapClass, "put",
                                             "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");

    jobject resultMap = env->NewObject(hashMapClass, hashMapInit);

    // isliCode
    jstring keyCode = env->NewStringUTF("isliCode");
    jstring valueCode = env->NewStringUTF(isli_code);
    env->CallObjectMethod(resultMap, hashMapPut, keyCode, valueCode);
    env->DeleteLocalRef(keyCode);
    env->DeleteLocalRef(valueCode);

    // featurePoints: ArrayList<HashMap<String, Integer>>
    jclass listClass = env->FindClass("java/util/ArrayList");
    jmethodID listInit = env->GetMethodID(listClass, "<init>", "()V");
    jmethodID listAdd = env->GetMethodID(listClass, "add", "(Ljava/lang/Object;)Z");

    jobject pointsList = env->NewObject(listClass, listInit);

    jclass integerClass = env->FindClass("java/lang/Integer");
    jmethodID integerValueOf = env->GetStaticMethodID(integerClass, "valueOf", "(I)Ljava/lang/Integer;");

    for (int i = 0; i < 2; i++) {
        jobject pointMap = env->NewObject(hashMapClass, hashMapInit);

        jstring keyX = env->NewStringUTF("x");
        jobject valX = env->CallStaticObjectMethod(integerClass, integerValueOf, (jint) feax[i]);
        env->CallObjectMethod(pointMap, hashMapPut, keyX, valX);
        env->DeleteLocalRef(keyX);
        env->DeleteLocalRef(valX);

        jstring keyY = env->NewStringUTF("y");
        jobject valY = env->CallStaticObjectMethod(integerClass, integerValueOf, (jint) feay[i]);
        env->CallObjectMethod(pointMap, hashMapPut, keyY, valY);
        env->DeleteLocalRef(keyY);
        env->DeleteLocalRef(valY);

        env->CallBooleanMethod(pointsList, listAdd, pointMap);
        env->DeleteLocalRef(pointMap);
    }

    jstring keyPoints = env->NewStringUTF("featurePoints");
    env->CallObjectMethod(resultMap, hashMapPut, keyPoints, pointsList);
    env->DeleteLocalRef(keyPoints);
    env->DeleteLocalRef(pointsList);

    // brightness
    jstring keyBrightness = env->NewStringUTF("brightness");
    jobject valBrightness = env->CallStaticObjectMethod(integerClass, integerValueOf, (jint) brightness);
    env->CallObjectMethod(resultMap, hashMapPut, keyBrightness, valBrightness);
    env->DeleteLocalRef(keyBrightness);
    env->DeleteLocalRef(valBrightness);

    // isBlur
    jclass booleanClass = env->FindClass("java/lang/Boolean");
    jmethodID booleanValueOf = env->GetStaticMethodID(booleanClass, "valueOf", "(Z)Ljava/lang/Boolean;");
    jstring keyBlur = env->NewStringUTF("isBlur");
    jobject valBlur = env->CallStaticObjectMethod(booleanClass, booleanValueOf, (jboolean)(is_blur != 0));
    env->CallObjectMethod(resultMap, hashMapPut, keyBlur, valBlur);
    env->DeleteLocalRef(keyBlur);
    env->DeleteLocalRef(valBlur);

    return resultMap;
}

extern "C"
JNIEXPORT jobject JNICALL
Java_com_google_1mlkit_1barcode_1scanning_ISLILineDecoderHandler_nativeDecode(
        JNIEnv *env, jclass clazz,
        jbyteArray pixels_, jint w, jint h, jint bpl) {

    if (!pixels_) {
        return nullptr;
    }

    jbyte *pixels = env->GetByteArrayElements(pixels_, nullptr);
    if (!pixels) {
        return nullptr;
    }

    IMAGE image((unsigned char *) pixels, w, h, bpl);
    char isli_code[20] = {0};
    short feax[2] = {0};
    short feay[2] = {0};
    int brightness = 0;
    int is_blur = 0;

    int ret = isli_line_decoder_do_image_decode(&image, isli_code, feax, feay, &brightness, &is_blur);

    env->ReleaseByteArrayElements(pixels_, pixels, JNI_ABORT);

    if (ret != 1) {
        return nullptr;
    }

    return buildResultMap(env, isli_code, feax, feay, brightness, is_blur);
}

//extern "C"
//JNIEXPORT jobject JNICALL
//Java_com_google_1mlkit_1barcode_1scanning_ISLILineDecoderHandler_nativeDecodeWindowed(
//        JNIEnv *env, jclass clazz,
//        jbyteArray pixels_, jint w, jint h, jint bpl,
//        jint rectX, jint rectY, jint rectW, jint rectH,
//        jint orientation) {
//
//    if (!pixels_) {
//        return nullptr;
//    }
//
//    jbyte *pixels = env->GetByteArrayElements(pixels_, nullptr);
//    if (!pixels) {
//        return nullptr;
//    }
//
//    IMAGE image((unsigned char *) pixels, w, h, bpl);
//    char isli_code[20] = {0};
//    short feax[2] = {0};
//    short feay[2] = {0};
//    int brightness = 0;
//    int is_blur = 0;
//
//    TRect rect;
//    rect.x = rectX;
//    rect.y = rectY;
//    rect.w = rectW;
//    rect.h = rectH;
//
//    int ret = isli_line_decoder_do_windowed_decode(&image, &rect, orientation,
//                                                    isli_code, feax, feay,
//                                                    &brightness, &is_blur);
//
//    env->ReleaseByteArrayElements(pixels_, pixels, JNI_ABORT);
//
//    if (ret != 1) {
//        return nullptr;
//    }
//
//    return buildResultMap(env, isli_code, feax, feay, brightness, is_blur);
//}
