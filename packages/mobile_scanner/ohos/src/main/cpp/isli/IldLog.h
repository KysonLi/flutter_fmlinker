// IldLog.h - ISLI icon decoder unified logging (isliicon tag)
//
// 运行期级别门控，默认 INFO（[summary]/[frame]/[model] 等阶段诊断默认可见）。
//   islii_set_log_level(0..4): 0=OFF 1=ERROR 2=WARN 3=INFO(默认) 4=DEBUG
//   Android: __android_log_print -> logcat（adb logcat -s isliicon）
//   OHOS:    OH_LOG_Print -> hilog（hdc shell hilog | grep isliicon，domain 0x3200）
//   其它平台: fprintf(stderr)
// Release 构建（NDEBUG）：Android/PC 编译期关闭（零输出零开销）；OHOS 例外——
//   真机默认即 Release，且需诊断"无法解码"，故 OHOS 下即使 NDEBUG 也保留日志。
//   实参先 vsnprintf 到 buffer 再以 %{public}s 输出，规避 hilog <private> 脱敏。
#ifndef __ISLI_ICON_LOG_H__
#define __ISLI_ICON_LOG_H__

// ---- 平台输出后端 ----
#if defined(__ANDROID__)
#include <android/log.h>
#elif defined(ISLI_PLATFORM_OHOS)
#include <hilog/log.h>
#endif
#include <cstdio>
#include <cstdarg>

#define ISLII_LOG_TAG "isliicon"

// ---- 日志级别（与平台无关，始终编译）----
#define ISLII_LOG_LEVEL_OFF   0
#define ISLII_LOG_LEVEL_ERROR 1
#define ISLII_LOG_LEVEL_WARN  2
#define ISLII_LOG_LEVEL_INFO  3
#define ISLII_LOG_LEVEL_DEBUG 4

// 运行时级别（默认 INFO：[summary]/[frame]/[model] 等阶段诊断默认可见；
// Release+非OHOS 下宏为 no-op，此值不影响输出）。
inline int& islii_log_level_ref() { static int lvl = ISLII_LOG_LEVEL_INFO; return lvl; }
inline void islii_set_log_level(int level) {
    if (level < ISLII_LOG_LEVEL_OFF) level = ISLII_LOG_LEVEL_OFF;
    if (level > ISLII_LOG_LEVEL_DEBUG) level = ISLII_LOG_LEVEL_DEBUG;
    islii_log_level_ref() = level;
}
inline int islii_get_log_level() { return islii_log_level_ref(); }

// 核心输出：先 vsnprintf 到 buffer（规避 OHOS hilog 对 %d/%s 的 <private> 脱敏，
// 与 line decoder 的 ild_log 同模式），再按平台输出。级别用 ISLII_LOG_LEVEL_* 常量。
inline void islii_log(int level, const char* lvlstr, const char* fmt, ...) {
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    std::vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
#if defined(__ANDROID__)
    int prio = (level >= ISLII_LOG_LEVEL_DEBUG) ? ANDROID_LOG_DEBUG :
               (level == ISLII_LOG_LEVEL_INFO)  ? ANDROID_LOG_INFO  :
               (level == ISLII_LOG_LEVEL_WARN)  ? ANDROID_LOG_WARN  : ANDROID_LOG_ERROR;
    __android_log_print(prio, ISLII_LOG_TAG, "[%s] %s", lvlstr, buf);
#elif defined(ISLI_PLATFORM_OHOS)
    // OHOS hilog：buf 已预格式化，以 %{public}s 输出避免实参被脱敏。domain 0x3200 同 NAPI。
    LogLevel lvl = (level >= ISLII_LOG_LEVEL_DEBUG) ? LOG_DEBUG :
                   (level == ISLII_LOG_LEVEL_INFO)  ? LOG_INFO  :
                   (level == ISLII_LOG_LEVEL_WARN)  ? LOG_WARN  : LOG_ERROR;
    OH_LOG_Print(LOG_APP, lvl, 0x3200, ISLII_LOG_TAG, "[%{public}s] %{public}s", lvlstr, buf);
#else
    std::fprintf(stderr, "%s: [%s] %s\n", ISLII_LOG_TAG, lvlstr, buf);
    std::fflush(stderr);
#endif
}

// ---- 日志宏 ----
// 级别门控：cheap 整型比较先于格式化，不达标不调 islii_log。
// Release（NDEBUG）：编译期关闭，零输出零开销，参数不求值。
//   需要真机日志排查时打 Debug APK（CMAKE_BUILD_TYPE=Debug，无 NDEBUG）。
//   OHOS 例外：真机默认即 Release，且需要诊断"无法解码"，故 OHOS 下即使
//   NDEBUG 也保留日志（见 linecode/IldLog.h 同款处理与 ild_log 注释）。
#if defined(NDEBUG) && !defined(ISLI_PLATFORM_OHOS)
#define ISLII_LOGE(fmt, ...) do {} while (0)
#define ISLII_LOGW(fmt, ...) do {} while (0)
#define ISLII_LOGI(fmt, ...) do {} while (0)
#define ISLII_LOGD(fmt, ...) do {} while (0)
#else
#define ISLII_LOGE(fmt, ...) do { if (islii_get_log_level() >= ISLII_LOG_LEVEL_ERROR) islii_log(ISLII_LOG_LEVEL_ERROR, "E", fmt, ##__VA_ARGS__); } while (0)
#define ISLII_LOGW(fmt, ...) do { if (islii_get_log_level() >= ISLII_LOG_LEVEL_WARN)  islii_log(ISLII_LOG_LEVEL_WARN,  "W", fmt, ##__VA_ARGS__); } while (0)
#define ISLII_LOGI(fmt, ...) do { if (islii_get_log_level() >= ISLII_LOG_LEVEL_INFO)  islii_log(ISLII_LOG_LEVEL_INFO,  "I", fmt, ##__VA_ARGS__); } while (0)
#define ISLII_LOGD(fmt, ...) do { if (islii_get_log_level() >= ISLII_LOG_LEVEL_DEBUG) islii_log(ISLII_LOG_LEVEL_DEBUG, "D", fmt, ##__VA_ARGS__); } while (0)
#endif

#endif // __ISLI_ICON_LOG_H__
