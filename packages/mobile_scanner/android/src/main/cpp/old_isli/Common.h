#ifndef __ILD_COMMON_H__
#define __ILD_COMMON_H__

#ifdef ILD_DEBUG

#include "canvas.h"
#include <QDebug>
#include <QImage>
#include <vld.h>

#define REMOTE_DRAW 0
#define ILDLOG(...) ild_printf(__FILE__, __LINE__, __VA_ARGS__)

#else
#define REMOTE_DRAW 0

#define ILDLOG(...) 

#endif

#ifndef UNREFERENCED_PARAMETER
#define UNREFERENCED_PARAMETER(P)          (P)
#endif

void ild_printf(const char *file_name, int line_num, const char *format, ...);

const unsigned int ILD_BIT_COUNT = 112;
const unsigned int ILD_GAUSSIAN_KERNEL = 15;
const unsigned int ILD_MAX_PATTERN_SIZE = 200;
const unsigned int ILD_MIN_BRIGHTNESS = 40;
const float ILD_BLUR_THRESHOLD = 40.0f;
const double ILD_CLIP_RATIO_X = 0.8;
const double ILD_CLIP_RATIO_Y = 0.5;

typedef unsigned char Byte;

#endif