#include "CornerFinetuner.h"
#include "CircleArea.h"
#include <string.h>
#include <math.h>
#include <stdlib.h>

#define REMOTE_DRAW 0

#if REMOTE_DRAW
#include "canvas.h"
#endif

#define CIRCLE_EDGE_MARK  0x7f

static void clip(IMAGE* image, short x, short y, CircleArea* ca, unsigned char* patch)
{
    int sum = 0;
    for (int v = -ca->r; v <= ca->r; v++){
        unsigned char* psrc = image->pixel + ((y + v) * image->bpl + x + ca->x0[ca->r + v]);
        for (int u = 0; u < ca->len[ca->r + v]; u++){
            sum += *psrc++;
        }
    }
    int avg = (int)(sum * 1.2 / ca->area);

    int e = ca->r * 2 + 1;
    memset(patch, 0xff, (size_t)(e * e));
    for (int v = -ca->r; v <= ca->r; v++){
        unsigned char* psrc = image->pixel + ((y + v) * image->bpl + x + ca->x0[ca->r + v]);
        unsigned char* pline = patch + (v + ca->r) * e + (ca->x0[v + ca->r] + ca->r);
        int len = ca->len[ca->r + v];
        for (int u = 0; u < len; u++){
            if (u == 0 || u == len - 1 || v == -ca->r || v == ca->r){
                *pline = CIRCLE_EDGE_MARK;
            }
            else{
                if (*psrc++ < avg) {
                    *pline = 0x00;
                }
            }
            pline++;
        }
    }
}

static inline unsigned char smooth(unsigned char* p, int bpl)
{
    int v = p[0] + p[-1] + p[+1] +
            p[-bpl] + p[-bpl - 1] + p[-bpl + 1] +
            p[+bpl] + p[+bpl - 1] + p[+bpl + 1];

    return (unsigned char)((v + 4) / 9);
}

static long long corner_score(IMAGE* image, int x, int y, double* guass_kernel, int r)
{
    if ((x < r + 3) || ((x + r) >= (image->w - 3)) ||
        (y < r + 3) || ((y + r) >= (image->h - 3))) {
        //guass kernel 的半径为r
        //smooth的半径为1
        //计算Ix和Iy的dx dy为2
        return 0;
    }

    int sumIx2 = 0;
    int sumIy2 = 0;
    int sumIxy = 0;
    int bpl = image->bpl;
    double* gk = guass_kernel;
    for (int v = -r; v <= r; v++){
        unsigned char* pline = image->pixel + (y + v) * image->bpl + x - r;
        for (int u = -r; u <= r; u++){
            //__canvas.DrawDot("source", "color=0xff", ca->x0[v + ca->r] + x + u, (y + v));
            int Ix = smooth(pline + 2, bpl) - smooth(pline - 2, bpl);
            int Iy = smooth(pline + 2*bpl, bpl) - smooth(pline - 2*bpl, bpl);
            double m = *gk++;

            Ix = (int)(Ix * m + 0.5);
            Iy = (int)(Iy * m + 0.5);

            sumIx2 += Ix * Ix;
            sumIy2 += Iy * Iy;
            int t = Ix*Iy;
            sumIxy += (t >= 0 ? t : -t);

            pline++;
        }
    }
    long long t = (long long)sumIx2 * (long long)sumIy2 - (long long)sumIxy * (long long)sumIxy;
    if (t < 0)
        t = -t;

    return t;
}

static void find_2peaks(long long* score, int e, int peak_distant, int* x0, int* y0, int* x1, int* y1)
{
    long long max_v0 = 0;
    int       max_x0 = 0;
    int       max_y0 = 0;

    //先找最大峰值
    long long *p = score;
    for (int y = 0; y < e; y++){
        for (int x = 0; x < e; x++){
            long long t = *p++;
            if (t > max_v0){
                max_v0 = t;
                max_x0 = x;
                max_y0 = y;
            }
        }
    }
    *x0 = max_x0;
    *y0 = max_y0;

#if REMOTE_DRAW
    __canvas.DrawDot("bw", "color=0xff;size=4;shape=cross", max_x0, max_y0);
    {
        unsigned char* img = new unsigned char[e*e];

        for (int i = 0; i < e*e; i++){
            img[i] = (unsigned char)((double)score[i] * 255 / (double)max_v0);
        }
        __canvas.DrawImage("score", "Gray", e, e, img, e*e);

        delete[] img;
    }
#endif
    //再找第二大峰值
    long long max_v1 = 0;
    int       max_x1 = 0;
    int       max_y1 = 0;
    int            D = peak_distant * peak_distant;

    p = score;
    for (int y = 0; y < e; y++){
        for (int x = 0; x < e; x++){
            long long t = *p++;
            if (t > max_v1){
                int dx = x - max_x0;
                int dy = y - max_y0;
                if (dx * dx + dy * dy > D){
                    max_v1 = t;
                    max_x1 = x;
                    max_y1 = y;
                }
            }
        }
    }
    *x1 = max_x1;
    *y1 = max_y1;
#if REMOTE_DRAW
    __canvas.DrawDot("bw", "color=0xff;size=4;shape=cross", max_x1, max_y1);
#endif
}

static double* create_guass_kernel(int r)
{
    int e = 2 * r + 1;
    double* kernel = new double[(size_t)(e * e)];

    for (int y = -r; y <= r; y++) {
        for (int x = -r; x <= r; x++){
            kernel[(r + y)*e + (r + x)] = exp(-double(x * x + y * y));
        }
    }

    return kernel;
}

void fine_tune_corner_coord(IMAGE* image,
                            short  corner_x,
                            short  corner_y,
                            short  frame_width,
                            short* ft_x,
                            short* ft_y)
{
    short r = (short)(frame_width * 1.25);
    
    if (corner_x < r || corner_x + r >= image->w ||
        corner_y < r || corner_y + r >= image->h) {
        *ft_x = corner_x;
        *ft_y = corner_y;
        //图像出界了
        return;
    }

    int             e = 2 * r + 1;                          //黑白图像边长
    unsigned char* bw = new unsigned char[(size_t)(e * e)]; //黑白图像像素
    long long*  score = new long long[(size_t)(e*e)];       //corner得分

    //裁剪一个圆形区域图像并对其做二值化，
    CircleArea ca;
    init_CircleArea(&ca, r);
    clip(image, corner_x, corner_y, &ca, bw);
    uninit_CircleArea(&ca);
    
#if REMOTE_DRAW
    __canvas.DrawImage("bw", "Gray", e, e, bw, e*e);
#endif

    //在二值图像的边界上计算corner得分
    //CircleArea ca2;
    //init_CircleArea(&ca2, (int)(frame_width * 0.85 + 0.5));//计算corner得分的窗口
    int r2 = (int)(frame_width);
    double* guass_kernel = create_guass_kernel(r2);
    memset(score, 0, sizeof(long long)*e*e);
    for (int y = 1; y < e - 1; y++){
        for (int x = 1; x < e - 1; x++){
            unsigned char* p = bw + (y * e + x);
            if ((CIRCLE_EDGE_MARK != *p) &&
                (CIRCLE_EDGE_MARK != p[-1]) &&
                (CIRCLE_EDGE_MARK != p[1]) &&
                (CIRCLE_EDGE_MARK != p[-e]) &&
                (CIRCLE_EDGE_MARK != p[e])){
                if ((0 == *p) && (p[-1] || p[1] || p[-e] || p[e])){
                    //只对黑白边界上的像素点计算corner得分
#if REMOTE_DRAW
                    __canvas.DrawDot("source", "color=0xffff", corner_x + x - r, corner_y + y - r);
#endif
                    //score[y * e + x] = corner_score(image, corner_x + x - r, corner_y + y - r, &ca2);
                    score[y * e + x] = corner_score(image, corner_x + x - r, corner_y + y - r, guass_kernel, r2);
                }
            }
        }
    }
    //uninit_CircleArea(&ca2);
    delete[] guass_kernel;

    //找到两个最大峰值点，峰峰连线中心坐标即fine tune后的角点坐标
    int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    find_2peaks(score, e, (int)(frame_width*0.75), &x0, &y0, &x1, &y1);
    *ft_x = (short)(corner_x + (x0 + x1 + 1) / 2 - r);
    *ft_y = (short)(corner_y + (y0 + y1 + 1) / 2 - r);

    delete[] bw;
    delete[] score;
}

