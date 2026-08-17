#ifndef __CURVESAMPLER_H__
#define __CURVESAMPLER_H__

#include "ImageType.h"

int max_curve_length();
int do_curve_sample(IMAGE* image, double* px, double* py, int dot_num,
                    int corner_pos[4], int is_clockwise,
                    unsigned char* pcurve[4],
                    int curve_len[4]);

//P2 直接采样：跳过三次多项式曲线拟合，直接从 trace 点分段线性弧长参数化
//消除了多项式振荡误差，对不规则弯曲边缘更鲁棒
int do_curve_sample_direct(IMAGE* image, double* px, double* py, int dot_num,
                           int corner_pos[4], int is_clockwise,
                           unsigned char* pcurve[4],
                           int curve_len[4]);

#endif

