#ifndef __ILD_CURVESAMPLER_H__
#define __ILD_CURVESAMPLER_H__

#include "TImage.h"
#include "Common.h"
#include "buffer.h"

void ild_split_curve_into_span(double c[4], double a, double b, double shift_x, double shift_y, double cosa, double sina, double span_len[], double span_x[], double span_y[], int span_num);
void ild_split_curve_into_span2(double c[4], double a, double b, double shift_x, double shift_y, double cosa, double sina, tl::buffer<double>& span_len, tl::buffer<double>& span_x, tl::buffer<double>& span_y, int span_num);

void ild_sample_one_curve(TImage* img, double span_len[], double span_x[], double span_y[], int span_num, int* out_len, unsigned char* out_wave);
void ild_sample_one_curve2(TImage* img, tl::buffer<double>& span_len, tl::buffer<double>& span_x, tl::buffer<double>& span_y, int span_num, int* out_len, unsigned char* out_wave);

unsigned char ild_bilinear_filter(TImage *img, double x, double y);

#endif

