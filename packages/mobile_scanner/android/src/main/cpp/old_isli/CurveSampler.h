#ifndef __CURVESAMPLER_H__
#define __CURVESAMPLER_H__

#include "ImageType.h"

int max_curve_length();
int do_curve_sample(IMAGE* image, double* px, double* py, int dot_num,
                    int corner_pos[4], int is_clockwise,
                    unsigned char* pcurve[4],
                    int curve_len[4]);

#endif

