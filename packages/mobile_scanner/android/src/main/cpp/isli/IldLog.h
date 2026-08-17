// IldLog.h - ISLI icon decoder unified logging (isliicon tag)
//
// Debug 构建：运行期级别门控，默认 INFO（阶段级日志，DEBUG 细节关闭避免刷屏）。
//   islii_set_log_level(0..4): 0=OFF 1=ERROR 2=WARN 3=INFO(默认) 4=DEBUG
//   Android: __android_log_print -> logcat（adb logcat -s isliicon）
//   其它平台: fprintf(stderr)
// Release 构建（NDEBUG）：日志编译期完全关闭（零输出、零运行期开销，参数也不求值）。
//   需要真机日志排查时打 Debug APK（CMAKE_BUILD_TYPE=Debug，无 NDEBUG）。
//   级别 API（islii_set/get_log_level）仍编译以保持调用方兼容，但宏为 no-op 故无输出。
#ifndef __ISLI_ICON_LOG_H__
#define __ISLI_ICON_LOG_H__

// ---- 平台输出后端 ----
#if defined(__ANDROID__)
#include <android/log.h>
#define ISLII_LOG_TAG "isliicon"
#else
#include <cstdio>
#endif

// ---- 日志级别（与平台无关，始终编译）----
#define ISLII_LOG_LEVEL_OFF   0
#define ISLII_LOG_LEVEL_ERROR 1
#define ISLII_LOG_LEVEL_WARN  2
#define ISLII_LOG_LEVEL_INFO  3
#define ISLII_LOG_LEVEL_DEBUG 4

// 运行时级别（Debug 默认 INFO；Release 下宏为 no-op，此值不影响输出）。
inline int& islii_log_level_ref() { static int lvl = ISLII_LOG_LEVEL_WARN; return lvl; }
inline void islii_set_log_level(int level) {
    if (level < ISLII_LOG_LEVEL_OFF) level = ISLII_LOG_LEVEL_OFF;
    if (level > ISLII_LOG_LEVEL_DEBUG) level = ISLII_LOG_LEVEL_DEBUG;
    islii_log_level_ref() = level;
}
inline int islii_get_log_level() { return islii_log_level_ref(); }

// ---- 日志宏 ----
#if defined(NDEBUG)
// Release：编译期关闭，零输出零开销，参数不求值
#define ISLII_LOGE(fmt, ...) do {} while (0)
#define ISLII_LOGW(fmt, ...) do {} while (0)
#define ISLII_LOGI(fmt, ...) do {} while (0)
#define ISLII_LOGD(fmt, ...) do {} while (0)
#elif defined(__ANDROID__)
// Debug + Android：logcat（级别门控，cheap 整型比较先于格式化）
#define ISLII_LOGE(fmt, ...) do { if (islii_get_log_level() >= ISLII_LOG_LEVEL_ERROR) __android_log_print(ANDROID_LOG_ERROR, ISLII_LOG_TAG, fmt, ##__VA_ARGS__); } while (0)
#define ISLII_LOGW(fmt, ...) do { if (islii_get_log_level() >= ISLII_LOG_LEVEL_WARN)  __android_log_print(ANDROID_LOG_WARN,  ISLII_LOG_TAG, fmt, ##__VA_ARGS__); } while (0)
#define ISLII_LOGI(fmt, ...) do { if (islii_get_log_level() >= ISLII_LOG_LEVEL_INFO)  __android_log_print(ANDROID_LOG_INFO,  ISLII_LOG_TAG, fmt, ##__VA_ARGS__); } while (0)
#define ISLII_LOGD(fmt, ...) do { if (islii_get_log_level() >= ISLII_LOG_LEVEL_DEBUG) __android_log_print(ANDROID_LOG_DEBUG, ISLII_LOG_TAG, fmt, ##__VA_ARGS__); } while (0)
#else
// Debug + PC：stderr（级别门控）
#define ISLII_LOGE(fmt, ...) do { if (islii_get_log_level() >= ISLII_LOG_LEVEL_ERROR) std::fprintf(stderr, "isliicon:E: " fmt "\n", ##__VA_ARGS__); } while (0)
#define ISLII_LOGW(fmt, ...) do { if (islii_get_log_level() >= ISLII_LOG_LEVEL_WARN)  std::fprintf(stderr, "isliicon:W: " fmt "\n", ##__VA_ARGS__); } while (0)
#define ISLII_LOGI(fmt, ...) do { if (islii_get_log_level() >= ISLII_LOG_LEVEL_INFO)  std::fprintf(stderr, "isliicon:I: " fmt "\n", ##__VA_ARGS__); } while (0)
#define ISLII_LOGD(fmt, ...) do { if (islii_get_log_level() >= ISLII_LOG_LEVEL_DEBUG) std::fprintf(stderr, "isliicon:D: " fmt "\n", ##__VA_ARGS__); } while (0)
#endif

#endif // __ISLI_ICON_LOG_H__
