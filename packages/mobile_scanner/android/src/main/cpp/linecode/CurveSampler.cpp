#include "Common.h"
#include "CurveSampler.h"
#include "CurveFit.h"
#include "Filter.h"
#include <math.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "buffer.h"

void ild_split_curve_into_span(double c[4], double a, double b,
                           double shift_x, double shift_y,
                           double cosa,    double sina,
                           double span_len[],
                           double span_x[],
                           double span_y[],
                           int    span_num)
{
    double det = (b - a) / span_num;

    double det2 = det * det;
    double x0 = a + det * 0;
    double y0 = c[0] + c[1] * x0 + c[2] * x0 * x0 + c[3] * x0 * x0 * x0;
    for (int i = 0; i < span_num; i++){
        double x1 = x0 + det;
        double y1 = c[0] + c[1] * x1 + c[2] * x1 * x1 + c[3] * x1 * x1 * x1;
        double dy = y1 - y0;
        span_len[i] = sqrt(dy * dy + det2);
        x0 = x1;
        y0 = y1;
    }

    for (int i = 0; i <= span_num; i++) {
        double x = a + det * i;
        double y = c[0] + c[1] * x + c[2] * x * x + c[3] * x * x * x;

        double xx = x * cosa + y * sina;
        double yy = -x * sina + y * cosa;

        span_x[i] = xx + shift_x;
        span_y[i] = yy + shift_y;
    }
}

void ild_split_curve_into_span2(double c[4], double a, double b,
                           double shift_x, double shift_y,
                           double cosa,    double sina,
                           tl::buffer<double>& span_len,
                           tl::buffer<double>& span_x,
                           tl::buffer<double>& span_y,
                           int    span_num)
{
    double det = (b - a) / span_num;

    double det2 = det * det;
    double x0 = a + det * 0;
    double y0 = c[0] + c[1] * x0 + c[2] * x0 * x0 + c[3] * x0 * x0 * x0;
    for (int i = 0; i < span_num; i++){
        double x1 = x0 + det;
        double y1 = c[0] + c[1] * x1 + c[2] * x1 * x1 + c[3] * x1 * x1 * x1;
        double dy = y1 - y0;
        span_len[i] = sqrt(dy * dy + det2);
        x0 = x1;
        y0 = y1;
    }

    for (int i = 0; i <= span_num; i++) {
        double x = a + det * i;
        double y = c[0] + c[1] * x + c[2] * x * x + c[3] * x * x * x;

        double xx = x * cosa + y * sina;
        double yy = -x * sina + y * cosa;

        span_x[i] = xx + shift_x;
        span_y[i] = yy + shift_y;
    }
}

unsigned char ild_bilinear_filter(TImage *img, double x, double y)
{
    if (!(x >= 0.0 && y >= 0.0 && x < img->w - 1 && y < img->h - 1))
        return 0xff;

    int x1 = (int)x;
    int y1 = (int)y;
    int x2 = x1 + 1;
    int y2 = y1 + 1;
    int bpl = img->bpl;
    unsigned char* p = img->pixel + bpl * y1 + x1;
    double x_x1 = x - x1;
    double y_y1 = y - y1;
    double x2_x = x2 - x;
    double y2_y = y2 - y;
    return (unsigned char)((p[0] * x2_x + p[1] * x_x1) * y2_y +
        (p[bpl] * x2_x + p[bpl + 1] * x_x1) * y_y1);
}

void sample_line(TImage* img, double sx, double sy, double ex, double ey, int n, unsigned char* wave)
{
    double dx = (ex - sx) / n;
    double dy = (ey - sy) / n;

    double x = sx;
    double y = sy;
    
    for (int i = 0; i < n; i++){
        int X = int(x + 0.5);
        int Y = int(y + 0.5);
        X = X;
        Y = Y;
#if REMOTE_DRAW
        //__canvas.DrawDot("source", "shape=dot;size=1;color=0xffcccc", X, Y);
#endif

        // 这里是为了能克服空心码样式
        //  x
        //  x
        // xxx
        //  x
        //  x
        unsigned char v = (unsigned char)((
            ild_bilinear_filter(img, x - 1.0, y) +
            ild_bilinear_filter(img, x, y) +
            ild_bilinear_filter(img, x + 1.0, y) +

            ild_bilinear_filter(img, x, y - 1.0) +
            ild_bilinear_filter(img, x, y + 1.0) +

            ild_bilinear_filter(img, x, y - 2.0) +
            ild_bilinear_filter(img, x, y + 2.0)
        ) / 7);

        wave[i] = v;

        x += dx;
        y += dy;
    }
}

void ild_sample_one_curve(TImage* img,
                      double span_len[],
                      double span_x[],
                      double span_y[],
                      int    span_num,
                      int*   out_len,
                      unsigned char* out_wave)
{
    double curve_len = 0;
    int    sample_num = *out_len;
    double unit_len_per_sample = 0;

    for (int i = 0; i < span_num; i++) {
        curve_len += span_len[i];
    }
    unit_len_per_sample = curve_len / sample_num;

    int offset = 0;
    double remained = 0;
    for (int i = 0; i < span_num; i++){
        int n = int((span_len[i] + remained) / unit_len_per_sample);
        remained = (span_len[i] + remained) - n * unit_len_per_sample;

        assert(offset + n <= sample_num);
        sample_line(img, span_x[i], span_y[i], span_x[i + 1], span_y[i + 1],
             n, out_wave + offset);
        offset += n;
    }
    *out_len = offset;//remained部分可能会丢弃一个采样
}

void ild_sample_one_curve2(
    TImage* img,
    tl::buffer<double>& span_len,
    tl::buffer<double>& span_x,
    tl::buffer<double>& span_y,
    int    span_num,
    int*   out_len,
    unsigned char* out_wave)
{
    double curve_len = 0;
    int    sample_num = *out_len;
    double unit_len_per_sample = 0;

    for (int i = 0; i < span_num; i++) {
        curve_len += span_len[i];
    }
    unit_len_per_sample = curve_len / sample_num;

    int offset = 0;
    double remained = 0;
    for (int i = 0; i < span_num; i++){
        int n = int((span_len[i] + remained) / unit_len_per_sample);
        remained = (span_len[i] + remained) - n * unit_len_per_sample;

        assert(offset + n <= sample_num);
        sample_line(img, span_x[i], span_y[i], span_x[i + 1], span_y[i + 1],
            n, out_wave + offset);
        offset += n;
    }
    *out_len = offset;//remained部分可能会丢弃一个采样
}
