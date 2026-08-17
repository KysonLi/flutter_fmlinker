#include <stdarg.h>
#include <stdio.h>

#if defined(_WIN32) || defined(_WIN64)
#include <strsafe.h>
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

void ild_printf(const char *file_name, int line_num, const char *format, ...)
{
    va_list args;
    va_start(args, format);

#if defined(_WIN32) || defined(_WIN64)
    char buf1[1024];
    char buf2[1024];
    StringCchVPrintfA(buf1, 1024, format, args);
    StringCchPrintfA(buf2, 1024, "%s(%d)\r\n\t%s\r\n", file_name, line_num, buf1);
    OutputDebugStringA(buf2);

#elif defined(__APPLE__)
#include "TargetConditionals.h"
#if defined(TARGET_OS_IPHONE) || defined(TARGET_IPHONE_SIMULATOR)
    char buf1[1024];
    vsnprintf(buf1, 1024, format, args);
    fprintf(stderr, "%s(%d)\r\n\t%s\r\n", file_name, line_num, buf1);
#endif
#endif
    va_end(args);
}

