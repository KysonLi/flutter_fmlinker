#include "CornerFinetuner.h"
#include "CircleArea.h"
#include "DecoderMemoryPool.h"
#include <string.h>
#include <math.h>
#include <stdlib.h>
#include <unordered_map>

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

//预计算 3×3 均值区域 S（与原 smooth() bit-exact：(sum+4)/9 截断）。
//覆盖图像 [ox, ox+sw-1] × [oy, oy+sh-1]，调用者确保该区域在 [1,w-2]×[1,h-2] 内。
static void precompute_smooth(const IMAGE* image, int ox, int oy, int sw, int sh, unsigned char* S)
{
    int bpl = image->bpl;
    const unsigned char* px = image->pixel;
    for (int j = 0; j < sh; j++) {
        int y = oy + j;
        const unsigned char* prow = px + y * bpl + ox;  // 行 y 起点（中心行）
        unsigned char* Srow = S + j * sw;
        for (int i = 0; i < sw; i++) {
            const unsigned char* p = prow + i;  // 中心 (ox+i, y)
            int v = p[0] + p[-1] + p[1] +
                    p[-bpl] + p[-bpl - 1] + p[-bpl + 1] +
                    p[bpl] + p[bpl - 1] + p[bpl + 1];
            Srow[i] = (unsigned char)((v + 4) / 9);
        }
    }
}

//corner_score 的预计算版本：用 S 查表代替 4×smooth() 调用（bit-exact，整数算术）。
//S: precompute_smooth 输出，原点 (ox,oy)，步长 sw。候选 (cx,cy) 为图像坐标。
//窗口越界（= 越出图像有效区）返回 0，与原 corner_score 边界语义一致。
//
//高斯核有效支持半径远小于 r2：核 m=exp(-(u²+v²))（无 sigma），S 为 8 位故 |Ix|≤255，
//round(Ix·m)≠0 要求 |Ix|·m≥0.5，最坏 |Ix|=255 时 u²+v²≤ln(510)≈6.23，即所有非零贡献
//点都在切比雪夫半径 2 内。r2≈0.5*frame_width（~20-26）时，(2r2+1)²≈2601 次迭代中仅 ~21
//次非零，98% 为恒零。核循环用 r_kern=min(r2, CORNER_KERN_EFF) 跳过恒零项 = bit-exact；
//边界检查仍用原 r2（保持哪些候选返回 0 不变）。
//高斯核 m=exp(-(u²+v²))，S 为 8 位故 |Ix|≤255。round(Ix·m)=(int)(Ix·m+0.5)≠0 要求 |Ix|·m≥0.5，
//最坏 |Ix|=255 时 m≥0.5/255≈0.00196，即 u²+v²≤ln(510)≈6.23。切比雪夫半径 2（5×5）覆盖全部
//非零点：(2,1)/(1,2) u²+v²=5<6.23 非零；(2,2) u²+v²=8>6.23，m=exp(-8)=3.35e-4，255·3.35e-4=0.085<0.5 → 0。
//半径 ≥3 的点 m≤exp(-9)=1.23e-4，255·1.23e-4=0.031<0.5 → 恒零。故 r_kern=min(r2,2) 与 r2 完整核 bit-exact。
static const int CORNER_KERN_EFF = 2;  // 高斯有效支持半径（切比雪夫半径2，覆盖全部非零贡献）

static long long corner_score_S(const unsigned char* S, int sw, int sh, int ox, int oy,
                                 int cx, int cy, double* guass_kernel, int r_kern, int r_bounds)
{
    int sx = cx - ox, sy = cy - oy;
    //smooth 偏移 ±2，窗口 ±r_bounds，故需 [sx-r_bounds-2, sx+r_bounds+2] ⊂ [0, sw-1]
    if (sx - r_bounds - 2 < 0 || sx + r_bounds + 2 >= sw || sy - r_bounds - 2 < 0 || sy + r_bounds + 2 >= sh) {
        return 0;
    }

    int sumIx2 = 0;
    int sumIy2 = 0;
    int sumIxy = 0;
    double* gk = guass_kernel;
    for (int v = -r_kern; v <= r_kern; v++){
        const unsigned char* Srow = S + (sy + v) * sw + sx;
        for (int u = -r_kern; u <= r_kern; u++){
            int Ix = Srow[u + 2] - Srow[u - 2];                    // smooth(cx+u+2,cy+v) - smooth(cx+u-2,cy+v)
            int Iy = S[(sy + v + 2) * sw + (sx + u)] - S[(sy + v - 2) * sw + (sx + u)];  // smooth(cx+u,cy+v+2) - smooth(cx+u,cy+v-2)
            double m = *gk++;

            Ix = (int)(Ix * m + 0.5);
            Iy = (int)(Iy * m + 0.5);

            sumIx2 += Ix * Ix;
            sumIy2 += Iy * Iy;
            int t = Ix*Iy;
            sumIxy += (t >= 0 ? t : -t);
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

//高斯核缓存 — 同一帧内4个角点通常用相同半径，避免重复计算exp()
static std::unordered_map<int, double*> g_kernel_cache;

static double* get_or_create_gauss_kernel(int r)
{
    auto it = g_kernel_cache.find(r);
    if (it != g_kernel_cache.end()) {
        return it->second;
    }

    int e = 2 * r + 1;
    double* kernel = new double[(size_t)(e * e)];
    for (int y = -r; y <= r; y++) {
        for (int x = -r; x <= r; x++) {
            kernel[(r + y) * e + (r + x)] = exp(-double(x * x + y * y));
        }
    }
    g_kernel_cache[r] = kernel;
    return kernel;
}

static void clear_gauss_kernel_cache()
{
    for (auto& kv : g_kernel_cache) {
        delete[] kv.second;
    }
    g_kernel_cache.clear();
}

//保留原函数名兼容
static double* create_guass_kernel(int r)
{
    return get_or_create_gauss_kernel(r);
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
    //使用内存池中的预分配缓冲区
    unsigned char* bw = g_pool ? g_pool->bw_patch : new unsigned char[(size_t)(e * e)];
    long long*  score = g_pool ? g_pool->score_patch : new long long[(size_t)(e * e)];

    //裁剪一个圆形区域图像并对其做二值化，
    CircleArea ca;
    init_CircleArea(&ca, r);
    clip(image, corner_x, corner_y, &ca, bw);
    uninit_CircleArea(&ca);

#if REMOTE_DRAW
    __canvas.DrawImage("bw", "Gray", e, e, bw, e*e);
#endif

    //在二值图像的边界上计算corner得分
    //高斯窗口半径（减半=~4×加速，A/B无回归；倾斜容错由透视校正+宽同步覆盖）
    int r2 = (int)(frame_width * 0.5);
    if (r2 < 2) r2 = 2;
    //高斯核有效支持半径远小于 r2（exp(-r²) 衰减极快，详见 corner_score_S 注释）。
    //核循环用 r_kern=min(r2, CORNER_KERN_EFF) 跳过恒零项，bit-exact；边界检查仍用 r2。
    int r_kern = (r2 > CORNER_KERN_EFF) ? CORNER_KERN_EFF : r2;
    double* guass_kernel = create_guass_kernel(r_kern);

    //预计算平滑区域 S（覆盖所有候选窗口 + smooth ±2 偏移），corner_score_S 查表代替 4×smooth()。
    //bit-exact：S 即 smooth() 的 (sum+4)/9；整数算术，与原 corner_score 结果逐位一致。
    int Rg = r + r2 + 3;
    int ox = corner_x - Rg; if (ox < 1) ox = 1;
    int oy = corner_y - Rg; if (oy < 1) oy = 1;
    int ex = corner_x + Rg; if (ex > image->w - 2) ex = image->w - 2;
    int ey = corner_y + Rg; if (ey > image->h - 2) ey = image->h - 2;
    int sw = ex - ox + 1; if (sw < 1) sw = 1;
    int sh = ey - oy + 1; if (sh < 1) sh = 1;
    unsigned char* S = g_pool ? g_pool->smooth_patch : new unsigned char[(size_t)(sw * sh)];
    precompute_smooth(image, ox, oy, sw, sh, S);

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
                    score[y * e + x] = corner_score_S(S, sw, sh, ox, oy, corner_x + x - r, corner_y + y - r, guass_kernel, r_kern, r2);
                }
            }
        }
    }
    if (!g_pool) delete[] S;
    // guass_kernel 由缓存管理，不需要手动释放

    //找到两个最大峰值点，峰峰连线中心坐标即fine tune后的角点坐标
    int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
    find_2peaks(score, e, (int)(frame_width*0.75), &x0, &y0, &x1, &y1);
    *ft_x = (short)(corner_x + (x0 + x1 + 1) / 2 - r);
    *ft_y = (short)(corner_y + (y0 + y1 + 1) / 2 - r);

    if (!g_pool) {
        delete[] bw;
        delete[] score;
    }
}

