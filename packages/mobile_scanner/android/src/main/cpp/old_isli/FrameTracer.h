#ifndef __CIRCLEAREASAMPLER_H__
#define __CIRCLEAREASAMPLER_H__

#include "ImageType.h"

int do_trace_frame(IMAGE* image, int sx0, int sy0, int sx1, int sy1, double frame_width,
                   double* px, double* py, int* dot_num);
int do_trace_frame2(IMAGE* image, int sx0, int sy0, int sx1, int sy1, double frame_width, double* px, double* py, int* dot_num);

#endif

