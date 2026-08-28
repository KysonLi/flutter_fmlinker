// IldLog.h - ISLI line decoder unified logging (isliline tag).
//
// 始终编译（Release 也生效），解决真机无解码日志问题。
// Android: 走 __android_log_print -> logcat（adb logcat -s isliline）。
// 其它平台: fprintf(stderr)。
// 运行时级别门控：默认 INFO（阶段计时 + 解码结果 + 拒绝可见，DEBUG 细节关闭避免刷屏）。
//   ild_set_log_level(0..4): 0=OFF 1=ERROR 2=WARN 3=INFO(默认) 4=DEBUG
#ifndef __ILD_LOG_H__
#define __ILD_LOG_H__

#include <cstdio>
#include <cstdarg>
#include <chrono>

#if defined(__ANDROID__)
#include <android/log.h>
#endif

#define ILD_LOG_TAG "isliline"

// 日志级别（门控：ild_get_log_level() >= 级别 才输出）
#define ILD_LOG_LEVEL_OFF    0
#define ILD_LOG_LEVEL_ERROR  1
#define ILD_LOG_LEVEL_WARN   2
#define ILD_LOG_LEVEL_INFO   3
#define ILD_LOG_LEVEL_DEBUG  4

// 运行时级别（函数局部 static，C++11 线程安全初始化；解码单线程访问）。
inline int& ild_log_level_ref() { static int lvl = ILD_LOG_LEVEL_INFO; return lvl; }
inline void ild_set_log_level(int level) {
    if (level < ILD_LOG_LEVEL_OFF) level = ILD_LOG_LEVEL_OFF;
    if (level > ILD_LOG_LEVEL_DEBUG) level = ILD_LOG_LEVEL_DEBUG;
    ild_log_level_ref() = level;
}
inline int ild_get_log_level() { return ild_log_level_ref(); }

// Stub for mobile project's DebugInfo（BarLocator 在 #ifdef ILD_DEBUG 下引用）。
struct ild_debug_info_t { size_t pattern2; double diviation; };
inline ild_debug_info_t* ild_get_debug_info() { static ild_debug_info_t d; return &d; }
inline void ild_free_debug_info() {}

// 核心输出。level 用 ILD_LOG_LEVEL_* 常量（跨平台），内部映射到 Android prio。
inline void ild_log(int level, const char* lvlstr, const char* fmt, ...) {
    char buf[1024];
    va_list args;
    va_start(args, fmt);
    std::vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
#if defined(__ANDROID__)
    int prio = (level >= ILD_LOG_LEVEL_DEBUG) ? ANDROID_LOG_DEBUG :
               (level == ILD_LOG_LEVEL_INFO)  ? ANDROID_LOG_INFO  :
               (level == ILD_LOG_LEVEL_WARN)  ? ANDROID_LOG_WARN  : ANDROID_LOG_ERROR;
    __android_log_print(prio, ILD_LOG_TAG, "[%s] %s", lvlstr, buf);
#else
    std::fprintf(stderr, "%s: [%s] %s\n", ILD_LOG_TAG, lvlstr, buf);
    std::fflush(stderr);
#endif
}

// 级别门控宏：先做 cheap 整型比较，不达标不格式化、不调 ild_log。
// Release（NDEBUG）：编译期关闭，零输出零开销，参数不求值。
//   需要真机日志排查时打 Debug APK（CMAKE_BUILD_TYPE=Debug，无 NDEBUG）。
#if defined(NDEBUG)
#define ILD_LOGE(fmt, ...) do {} while (0)
#define ILD_LOGW(fmt, ...) do {} while (0)
#define ILD_LOGI(fmt, ...) do {} while (0)
#define ILD_LOGD(fmt, ...) do {} while (0)
#else
#define ILD_LOGE(fmt, ...) do { if (ild_get_log_level() >= ILD_LOG_LEVEL_ERROR) ild_log(ILD_LOG_LEVEL_ERROR, "E", fmt, ##__VA_ARGS__); } while (0)
#define ILD_LOGW(fmt, ...) do { if (ild_get_log_level() >= ILD_LOG_LEVEL_WARN)  ild_log(ILD_LOG_LEVEL_WARN,  "W", fmt, ##__VA_ARGS__); } while (0)
#define ILD_LOGI(fmt, ...) do { if (ild_get_log_level() >= ILD_LOG_LEVEL_INFO)  ild_log(ILD_LOG_LEVEL_INFO,  "I", fmt, ##__VA_ARGS__); } while (0)
#define ILD_LOGD(fmt, ...) do { if (ild_get_log_level() >= ILD_LOG_LEVEL_DEBUG) ild_log(ILD_LOG_LEVEL_DEBUG, "D", fmt, ##__VA_ARGS__); } while (0)
#endif

// 计时块宏（保留兼容；body 总是执行，仅日志按 INFO 门控）。用法: ILD_TIMING("name") { ... }
#define ILD_TIMING(msg) \
    for (auto _ild_t0 = std::chrono::steady_clock::now(), *_ild_p = &_ild_t0; \
         _ild_p; \
         _ild_p = 0, (void)(ild_get_log_level() >= ILD_LOG_LEVEL_INFO ? \
            ild_log(ILD_LOG_LEVEL_INFO, "TIME", "%s took %lldms", msg, \
                (long long)std::chrono::duration_cast<std::chrono::milliseconds>( \
                    std::chrono::steady_clock::now() - _ild_t0).count()) : 0))

#endif // __ILD_LOG_H__
