#include <string.h>
#include <jni.h>
#include <android/log.h>
#include "isli/ImageType.h"
#include "isli/ISLIIconDecoder.h"

#define LOG_TAG "ISLIDecoder"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C"
JNIEXPORT void JNICALL
Java_com_google_1mlkit_1barcode_1scanning_ISLIDecoderHandler_nativeInit(JNIEnv *env, jclass clazz) {
    int ret = isli_icon_decoder_init();
    if (ret == 0) {
        LOGE("ISLI decoder already initialized or init failed");
    }
}

extern "C"
JNIEXPORT jobject JNICALL
Java_com_google_1mlkit_1barcode_1scanning_ISLIDecoderHandler_nativeDecode(
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
    short feax[6] = {0};
    short feay[6] = {0};

    int ret = isli_icon_decoder_do_image_decode(&image, isli_code, feax, feay);

    env->ReleaseByteArrayElements(pixels_, pixels, JNI_ABORT);

    if (ret != 1) {
        return nullptr;
    }

    // Build HashMap: { "isliCode": String, "featurePoints": ArrayList<HashMap> }
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

    for (int i = 0; i < 6; i++) {
        jobject pointMap = env->NewObject(hashMapClass, hashMapInit);

        jstring keyX = env->NewStringUTF("x");
        jobject valX = env->CallStaticObjectMethod(integerClass, integerValueOf, (jint)feax[i]);
        env->CallObjectMethod(pointMap, hashMapPut, keyX, valX);
        env->DeleteLocalRef(keyX);
        env->DeleteLocalRef(valX);

        jstring keyY = env->NewStringUTF("y");
        jobject valY = env->CallStaticObjectMethod(integerClass, integerValueOf, (jint)feay[i]);
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

    return resultMap;
}

extern "C"
JNIEXPORT void JNICALL
Java_com_google_1mlkit_1barcode_1scanning_ISLIDecoderHandler_nativeUninit(JNIEnv *env, jclass clazz) {
    int ret = isli_icon_decoder_uninit();
    if (ret == 0) {
        LOGE("ISLI decoder not initialized or uninit failed");
    }
}
