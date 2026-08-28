#ifndef __FRAMETRACER_H__
#define __FRAMETRACER_H__

#include "ImageType.h"

int do_trace_frame(IMAGE* image, int sx0, int sy0, int sx1, int sy1, double frame_width,
                   double* px, double* py, int* dot_num);

// Trace mode switch (A/B):
//   0 = centroid tracking (original)
//   1 = normal-direction matched filter (P0 optimization)
void islii_set_trace_mode(int mode);
int  islii_get_trace_mode();

// 追踪圆盘采样步长（默认1=逐像素，2=隔点~2×加速）
void islii_set_trace_subsample(int stride);
int  islii_get_trace_subsample();

// calc_center_shift SIMD 开关（默认开；A/B 对比用）
void islii_set_ccs_simd_enable(int e);
int  islii_get_ccs_simd_enable();

// 最近一次 do_trace_frame 在失败前走过的最大点数（衡量"追踪走了多远才脱轨"）
int islii_get_last_trace_progress();

#endif
