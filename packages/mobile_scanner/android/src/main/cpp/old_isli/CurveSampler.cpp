#include "CurveSampler.h"
#include "CurveFit.h"
#include "Filter.h"
#include <math.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

#define REMOTE_DRAW 0
#if REMOTE_DRAW
#include "canvas.h"
#include <QDebug>
#endif


void split_curve_into_span(double c[4], double a, double b,
                           double shift_x, double shift_y,
                           double cosa,    double sina,
                           double span_len[],
                           double span_x[],
                           double span_y[],
                           int    span_num)
{
    double det = (b - a) / span_num;

    /*double x0 = a + det * 0;
    double deriv0 = (c[1] + 2 * c[2] * x0 + 3 * c[3] * x0 * x0);
    double f0 = sqrt(1 + deriv0 * deriv0);
    
    for (int i = 0; i < span_num; i++) {   
        double x1 = x0 + det;
        double deriv1 = (c[1] + 2 * c[2] * x1 + 3 * c[3] * x1 * x1);
        double f1 = sqrt(1 + deriv1 * deriv1);
        
        double xm = (x0 + x1) / 2;
        double derivm = (c[1] + 2 * c[2] * xm + 3 * c[3] * xm * xm);
        double fm = sqrt(1 + derivm * derivm);

        span_len[i] = det / 6 * (f0 + 4 * fm + f1);

        x0 = x1;
        f0 = f1;
    }*/
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

void sample_line(IMAGE* img, double sx, double sy, double ex, double ey, int n, unsigned char* wave)
{
    double dx = (ex - sx) / n;
    double dy = (ey - sy) / n;

    double x = sx;
    double y = sy;
    int bpl = img->bpl;
    unsigned char* pixel = img->pixel;
    
    unsigned char *max_pixel = img->pixel + img->bpl * img->h;
    for (int i = 0; i < n; i++){
        int X = int(x + 0.5);
        int Y = int(y + 0.5);

        //同步执行3*3均值滤波
        unsigned char* p = pixel + bpl * Y + X;
        if (p + bpl + 1 >= max_pixel || p < pixel) return;
        unsigned char v = (unsigned char)((p[-1] + p[0] + p[1] +
                            p[-1 - bpl] + p[-bpl] + p[-bpl + 1] +
                            p[-1 + bpl] + p[+bpl] + p[+bpl + 1] + 4) / 9);

        wave[i] = v;

        x += dx;
        y += dy;
    }
}

void sample_one_curve(IMAGE* img,
                      double span_len[],
                      double span_x[],
                      double span_y[],
                      int    span_num,
                      int    is_clockwise,
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
        sample_line(img, span_x[i], span_y[i], span_x[i + 1], span_y[i + 1], n, out_wave + offset);
        offset += n;
    }
    *out_len = offset;//remained部分可能会丢弃一个采样

    if (!is_clockwise) {
        for (int i = 0; i < offset / 2; i++) {
            unsigned char t = out_wave[i];
            out_wave[i] = out_wave[offset - 1 - i];
            out_wave[offset - 1 - i] = t;
        }
    }
}

///////////////////////////////////////////////////////////////////////////////

#if REMOTE_DRAW
static void DrawWave(int clear, const char* style, const char* wave_name, unsigned char* wave, int len)
{
    if (clear) {
        __canvas.DrawImage(wave_name, "null", (short)len, 256, 0, 0);
    }

    for (int i = 0; i < len - 1; i++){
        __canvas.DrawLine(wave_name, style, (short)i, 256 - wave[i], (short)(i + 1), 256 - wave[i + 1]);
    }
}
#endif

//最长曲线的分段数
static const int MAX_SPAN = 128;

//每段曲线的分段数
static const int SPAN_NUM[4] = { 48, 48, 128, 128 };

//每个比特位的采样点数
static const int SAPMLES_PER_SPAN = 9;

//曲线最大采样点数，
//调用fit_frame_into_4curves之前先调用此函数获得曲线最大长度并分配内存
int max_curve_length()
{
    return MAX_SPAN * SAPMLES_PER_SPAN;
}

int do_curve_sample(IMAGE* image, double* px, double* py, int dot_num,
                    int corner_pos[4], int is_clockwise,
                    unsigned char* pcurve[4],
                    int curve_len[4])
{
    int ret = 1;

    for (int i = 0; i < 4; i++) {
        
        //将点旋转放到X轴上拟合成曲线
        double c[4] = { 0 };
        double cosa, sina;
        int start = corner_pos[i];
        int end = corner_pos[(i + 1) % 4];
        ret = do_curve_fit_with_coord_normalization(px, py, dot_num, start, end, is_clockwise,
            &c[0], &cosa, &sina);

        if (!ret){
            break;
        }

        //将曲线分割成span，并计算每个span的长度
        double span_len[MAX_SPAN];
        double shift_x = is_clockwise ? px[start] : px[end];
        double shift_y = is_clockwise ? py[start] : py[end];
        double span_x[MAX_SPAN + 1];
        double span_y[MAX_SPAN + 1];
        double x_len = (px[end] - px[start]) * cosa - (py[end] - py[start]) * sina;
        if (!is_clockwise){
            x_len = -x_len;
        }
        split_curve_into_span(c, 0, x_len, shift_x, shift_y, cosa, sina, span_len, span_x, span_y, SPAN_NUM[i]);
#if REMOTE_DRAW
        for (int s = 0; s < SPAN_NUM[i]; s++) {
            //qDebug() << span_len[s];
            __canvas.DrawLine("source", "color=0xff",
                (short)(span_x[s] + 0.5), (short)(span_y[s] + 0.5),
                (short)(span_x[s + 1] + 0.5), (short)(span_y[s + 1] + 0.5));
        }
#endif
        //根据每个span的长度逐个span采样波形，消除长度累积误差
        unsigned char wave[SAPMLES_PER_SPAN * MAX_SPAN];
        int len = SAPMLES_PER_SPAN * SPAN_NUM[i];
        int reverse = (i == 3) ? !is_clockwise : is_clockwise;
        sample_one_curve(image, span_len, span_x, span_y, SPAN_NUM[i], reverse, &len, wave);

        char name[128];
        sprintf(name, "Curve%d", i);
#if REMOTE_DRAW
        //DrawWave(1, "color=0xff0000", name, wave, len);
#endif
        //对波形做低通滤波，然后定位同步位
        //以同步位附近的波形平均值作为阈值对波形二值化，采样波形得到bit
        unsigned char filtered[SAPMLES_PER_SPAN * MAX_SPAN];
        do_low_pass_filter(wave, len, filtered);
#if REMOTE_DRAW
        DrawWave(1, "color=0xff", name, filtered, len);
#endif
        int copy_len = len < curve_len[i] ? len : curve_len[i];
        memcpy(pcurve[i], filtered, (size_t)copy_len);
        curve_len[i] = copy_len;
    }

    return ret;
}

