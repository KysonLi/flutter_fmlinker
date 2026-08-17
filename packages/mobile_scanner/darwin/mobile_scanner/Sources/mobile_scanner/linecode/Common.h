#ifndef __ILD_COMMON_H__
#define __ILD_COMMON_H__

#include "IldLog.h"

#ifdef ILD_DEBUG
#define REMOTE_DRAW 0
#define ILDLOG(...)  ILD_LOGI(__VA_ARGS__)
#else
#define REMOTE_DRAW 0
#define ILDLOG(...)  ((void)0)
#endif

#ifndef UNREFERENCED_PARAMETER
#define UNREFERENCED_PARAMETER(P)          (P)
#endif

void ild_printf(const char *file_name, int line_num, const char *format, ...);

const unsigned int ILD_BIT_COUNT = 112;
const unsigned int ILD_BIT_COUNT2 = 64;
const unsigned int ILD_GAUSSIAN_KERNEL = 15;
const unsigned int ILD_MAX_PATTERN_SIZE = 200;
const unsigned int ILD_MIN_BRIGHTNESS = 20;  // lowered for dark camera-simulated images
const float ILD_BLUR_THRESHOLD = 40.0f;
const double ILD_CYCLE_CODE_ASPECT_RATIO = 1.0;

typedef unsigned char Byte;

#endif