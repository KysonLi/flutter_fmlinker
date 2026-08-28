#include "FrameTracer.h"
#include "CircleArea.h"
#include "ISLIIconDecoder.h"
#include "IldLog.h"
#include <math.h>
#include <memory.h>
#include <limits.h>

// SIMD 加速 calc_center_shift 质心内循环（subsample=2 时）。
// x86_64 用 SSE2/SSSE3，arm64-v8a 用 NEON(A64)，armeabi-v7a(arm32)/其他走标量回退。
// bit-exact：处理完全相同的像素集（每 16 字节取偶字节 = subsample=2 的同样像素）、
// 相同的整数累加（掩码点积）。A64 专用内建(vaddvq/vqtbl1q)故仅 arm64 启用。
#if defined(__aarch64__)
#include <arm_neon.h>
#define ISLII_HAVE_SIMD 1
#elif defined(__SSE2__) || defined(_M_X64) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2)
#include <emmintrin.h>   // SSE2
#include <tmmintrin.h>   // SSSE3 (_mm_shuffle_epi8)
#define ISLII_HAVE_SIMD 1
#endif

#define REMOTE_DRAW 0
#if REMOTE_DRAW
#include "canvas.h"
#endif

#define ROUND2INT(x) ((x) >= 0 ? int((x) + 0.5) : int((x) - 0.5))

// Trace mode: 0=centroid (default, best on 101-image A/B), 1=directional centroid (opt-in)
static int g_trace_mode = 0;
void islii_set_trace_mode(int mode) { g_trace_mode = mode; }
int  islii_get_trace_mode() { return g_trace_mode; }

// 追踪圆盘采样步长（2=隔点~2×加速，A/B 实测 7>5 解码且更快，已设为默认）
static int g_trace_subsample = 2;
void islii_set_trace_subsample(int s) { g_trace_subsample = (s > 0) ? s : 1; }
int  islii_get_trace_subsample() { return g_trace_subsample; }

// SIMD 加速开关（默认开；A/B 对比用）
static int g_ccs_simd_enable = 1;
void islii_set_ccs_simd_enable(int e) { g_ccs_simd_enable = e; }
int  islii_get_ccs_simd_enable() { return g_ccs_simd_enable; }

// 最近一次追踪失败前走过的最大点数（跨参数集取最大）
static int g_last_trace_progress = 0;
int islii_get_last_trace_progress() { return g_last_trace_progress; }

#if defined(ISLII_HAVE_SIMD)
// SIMD 加速一行 [xstart,xend) 的质心累加（仅 subsample=2 调用）。
// bit-exact 等价标量：for(xx=xstart;xx<xend;xx+=2) if(ppixel[xx]<=th){cx+=xx-ox;cy+=y;cnt++;}
// 每 16 字节取偶字节 = subsample=2 的同样像素集；掩码点积(madd)累加 -> 相同整数结果。
static inline void ccs_row_simd(const unsigned char* ppixel, int xstart, int xend,
                                int ox, int y, int th,
                                int* cx, int* cy, int* cnt)
{
#if defined(__aarch64__)
    // ---- NEON (arm64-v8a, A64 内建) ----
    static const uint8_t even_tbl[16] = {0,2,4,6,8,10,12,14, 16,16,16,16,16,16,16,16};
    const int16x8_t step_i16 = {0,2,4,6,8,10,12,14};
    const uint8x16_t even_v = vld1q_u8(even_tbl);
    const uint8x16_t th_v   = vdupq_n_u8((uint8_t)th);
    int xx = xstart;
    for (; xx + 16 <= xend; xx += 16) {
        uint8x16_t px   = vld1q_u8(ppixel + xx);
        uint8x16_t ev   = vqtbl1q_u8(px, even_v);          // 偶字节 -> low 8
        uint8x16_t dark = vcleq_u8(ev, th_v);              // 0xFF where <= th
        uint8x8_t  d8   = vget_low_u8(dark);
        uint16x8_t d01  = vmovl_u8(vshr_n_u8(d8, 7));      // 8x u16: 1(dark)/0
        int16x8_t  idx  = vaddq_s16(vdupq_n_s16((short)(xx - ox)), step_i16);
        int16x8_t  prod = vmulq_s16(idx, vreinterpretq_s16_u16(d01));   // idx where dark
        int group_cx   = vaddvq_s32(vpaddlq_s16(prod));   // 水平求和 -> int
        int group_cnt  = (int)vaddvq_u32(vpaddlq_u16(d01));
        *cx  += group_cx;
        *cnt += group_cnt;
        *cy  += y * group_cnt;
    }
    for (; xx < xend; xx += 2) {                            // 标量尾部
        if (ppixel[xx] <= th) { *cx += (xx - ox); *cy += y; (*cnt)++; }
    }
#else
    // ---- SSE2/SSSE3 (x86) ----
    const __m128i even_mask = _mm_setr_epi8(0,2,4,6,8,10,12,14, -1,-1,-1,-1,-1,-1,-1,-1);
    const __m128i idx_step  = _mm_setr_epi16(0,2,4,6,8,10,12,14);
    const __m128i bias      = _mm_set1_epi8((char)0x80);
    const __m128i all_ff    = _mm_set1_epi8((char)0xFF);
    const __m128i th_v      = _mm_set1_epi8((char)(unsigned char)th);
    int xx = xstart;
    for (; xx + 16 <= xend; xx += 16) {
        __m128i px  = _mm_loadu_si128((const __m128i*)(ppixel + xx));
        __m128i ev  = _mm_shuffle_epi8(px, even_mask);      // bytes0-7 = 偶像素, 8-15 = 0
        // 无符号 ev<=th：偏置 0x80 转有符号比较
        __m128i evb = _mm_xor_si128(ev, bias);
        __m128i thb = _mm_xor_si128(th_v, bias);
        __m128i light = _mm_cmpgt_epi8(evb, thb);           // 0xFF where ev>th
        __m128i dark  = _mm_xor_si128(light, all_ff);       // 0xFF where ev<=th (low 8 有效)
        // dark 8x int16 (符号扩展 low 8 字节)：unpack 后算术右移
        __m128i dark16 = _mm_srai_epi16(_mm_unpacklo_epi8(dark, dark), 8);  // 0xFFFF/0x0000
        __m128i dark01 = _mm_srli_epi16(dark16, 15);        // 0x0001/0x0000
        __m128i idx    = _mm_add_epi16(_mm_set1_epi16((short)(xx - ox)), idx_step);
        __m128i prod   = _mm_madd_epi16(idx, dark01);       // 4x int32: 配对求和
        __m128i s = _mm_add_epi32(prod, _mm_shuffle_epi32(prod, _MM_SHUFFLE(0,0,3,2)));
        s = _mm_add_epi32(s, _mm_shuffle_epi32(s, _MM_SHUFFLE(0,0,0,1)));
        int group_cx = _mm_cvtsi128_si32(s);
        __m128i cp = _mm_madd_epi16(dark01, dark01);        // 4x int32: 配对计数
        __m128i cs = _mm_add_epi32(cp, _mm_shuffle_epi32(cp, _MM_SHUFFLE(0,0,3,2)));
        cs = _mm_add_epi32(cs, _mm_shuffle_epi32(cs, _MM_SHUFFLE(0,0,0,1)));
        int group_cnt = _mm_cvtsi128_si32(cs);
        *cx  += group_cx;
        *cnt += group_cnt;
        *cy  += y * group_cnt;
    }
    for (; xx < xend; xx += 2) {                            // 标量尾部
        if (ppixel[xx] <= th) { *cx += (xx - ox); *cy += y; (*cnt)++; }
    }
#endif
}
#endif  // ISLII_HAVE_SIMD

//优化：用十字线子采样快速估计阈值，单次遍历完成质心计算，消除原两次遍历
//边界保护：盾牌靠近图像边缘时（如白色背景拍摄偏移）CircleArea 会越界，
//原实现假设调用者保证不越界（实际未保证）-> 越界读 garbage -> 质心错 -> trace 脱轨。
static void calc_center_shift(IMAGE* img,
                              double ini_cx, double ini_cy, CircleArea* ca,
                              double* dx, double* dy)
{
    int ox = ROUND2INT(ini_cx);
    int oy = ROUND2INT(ini_cy);
    int W = img->w, H = img->h, bpl = img->bpl;

    //快速阈值估计：采样圆形的中心行+中心列（每隔2像素采样）
    long sum_sample = 0;
    int  cnt_sample = 0;
    //中心行
    if (oy >= 0 && oy < H) {
        int i = ca->r;
        int x = ca->x0[i];
        int len = ca->len[i];
        int xstart = ox + x, xend = ox + x + len;
        if (xstart < 0) xstart = 0;
        if (xend > W) xend = W;
        unsigned char* ppixel = img->pixel + oy * bpl;
        for (int xx = xstart; xx < xend; xx += 3){
            sum_sample += ppixel[xx];
            cnt_sample++;
        }
    }
    //中心列
    if (ox >= 0 && ox < W) {
        int ystart = oy - ca->r, yend = oy + ca->r + 1;
        if (ystart < 0) ystart = 0;
        if (yend > H) yend = H;
        for (int yy = ystart; yy < yend; yy += 3){
            sum_sample += img->pixel[yy * bpl + ox];
            cnt_sample++;
        }
    }

    long th = 0;
    if (cnt_sample > 0){
        th = ROUND2INT((double)sum_sample / cnt_sample * 1.2);
    }

    //单次遍历：同时完成暗像素判定与质心累加（含边界裁剪）
    int cx = 0;
    int cy = 0;
    int cnt = 0;
    for (int y = -ca->r, i = 0; y <= ca->r; y++, i++) {
        int yy = oy + y;
        if (yy < 0 || yy >= H) continue;  // 行越界，跳过
        int x = ca->x0[i];
        int len = ca->len[i];
        int xstart = ox + x;
        int xend = ox + x + len;
        if (xstart < 0) xstart = 0;
        if (xend > W) xend = W;
        if (xstart >= xend) continue;  // 本行完全越界
        unsigned char* ppixel = img->pixel + yy * bpl;
        int j_off = xstart - (ox + x);  // 裁剪后起始偏移
#if defined(ISLII_HAVE_SIMD)
        if (g_trace_subsample == 2 && g_ccs_simd_enable) {
            ccs_row_simd(ppixel, xstart, xend, ox, y, th, &cx, &cy, &cnt);
            continue;
        }
#endif
        for (int xx = xstart; xx < xend; xx += g_trace_subsample){
            if (ppixel[xx] <= th) {
                cx += (xx - ox);  // 用绝对坐标减 ox 得磁盘相对坐标
                cy += y;
                cnt++;
            }
        }
    }

    if (cnt > 0){
        *dx = (double)cx / cnt;
        *dy = (double)cy / cnt;
    } else {
        *dx = 0;
        *dy = 0;
    }
}

static int amend_center(IMAGE* image,
    double ini_cx, double ini_cy, CircleArea* ca,
    double* out_cx, double* out_cy)
{
    double dx, dy;

    int MAX_TRY = islii_get_fast_mode() ? 2 : 3;
    double T = ca->r / 8;

    if (T < 1) {
        T = 1;
    }

    for (int i = 0; i < MAX_TRY; i++) {
        //原边缘检查（中心距图像边 < ca->r 即 break）已移除：
        //calc_center_shift 现自带边界裁剪，可安全处理边缘附近盾牌（白色背景拍摄偏移场景）。
        //原检查导致 x=8 等近边缘起点直接失败 -> trace derail@0。

        calc_center_shift(image, ini_cx, ini_cy, ca, &dx, &dy);

        if (dx <= T && dx >= -T &&
            dy <= T && dy >= -T) {
            *out_cx = ini_cx + dx;
            *out_cy = ini_cy + dy;
#if REMOTE_DRAW
            __canvas.DrawDot("source", "color=0xff00", ROUND2INT(*out_cx), ROUND2INT(*out_cy));
#endif
            return 1;
        }
        else {
            ini_cx += dx;
            ini_cy += dy;
#if REMOTE_DRAW
            __canvas.DrawDot("source", "color=0xff", ROUND2INT(ini_cx), ROUND2INT(ini_cy));
#endif
        }
    }

    return 0;
}

static void calc_step(int x0, int y0, int x1, int y1, double step, double* dx, double *dy)
{
    int xx = x1 - x0;
    int yy = y1 - y0;

    double r = sqrt((double)(xx*xx + yy * yy));
    *dx = step * yy / r;
    *dy = step * xx / r;

    if (xx >= 0) {
        if (yy > 0) {
            *dx = -*dx;
        }
    }
    else {
        if (yy < 0){
            *dx = -*dx;
        }
    }
}

//=========================================================================
// 方向性质心 (strip-masked centroid) — P0 优化，A/B 替代全质心法
//
// 原理：保留质心法的圆盘（各向同性 → 能跟随曲率，不会因切向预测误差脱轨），
// 但把圆盘按"切向投影"掩码成一条垂直于切向的窄带（strip）。这样：
//   - 直边/曲边段：窄带覆盖整条法向范围，行为≈全质心，稳定跟线；
//   - 角点/盾尖：另一条边在当前边的切向上投影较大 → 被掩码排除 → 质心不被
//     另一条边拉偏 → 角点处仍能收敛（全质心在此会跳动不收敛而脱轨）。
//
// tan_half = 窄带的切向半宽；=r 时退化为全质心（用于对照）。
//=========================================================================
static int calc_center_shift_dir(IMAGE* img,
                                 double ini_cx, double ini_cy, CircleArea* ca,
                                 double ux, double uy, double tan_half,
                                 double* dx, double* dy)
{
    int ox = ROUND2INT(ini_cx);
    int oy = ROUND2INT(ini_cy);

    //阈值估计：采样圆形的中心行+中心列（每3像素采样1个）
    long sum_sample = 0;
    int  cnt_sample = 0;
    {
        int i = ca->r;
        int x = ca->x0[i];
        int len = ca->len[i];
        unsigned char* ppixel = img->pixel + oy * img->bpl + (ox + x);
        for (int j = 0; j < len; j += 3){ sum_sample += ppixel[j]; cnt_sample++; }
    }
    {
        for (int y = -ca->r; y <= ca->r; y += 3){
            sum_sample += img->pixel[(oy + y) * img->bpl + ox];
            cnt_sample++;
        }
    }
    long th = (cnt_sample > 0) ? ROUND2INT((double)sum_sample / cnt_sample * 1.2) : 0;

    //strip-masked 质心：只统计切向投影 |tang| <= tan_half 的暗像素
    long cx = 0, cy = 0;
    int  cnt = 0;
    for (int y = -ca->r, i = 0; y <= ca->r; y++, i++) {
        int x = ca->x0[i];
        int len = ca->len[i];
        unsigned char* ppixel = img->pixel + (oy + y) * img->bpl + (ox + x);
        for (int j = 0; j < len; j++) {
            int offx = x + j;          // 相对圆心的列偏移
            int offy = y;              // 相对圆心的行偏移
            double tang = offx * ux + offy * uy;
            if (tang < -tan_half || tang > tan_half)
                continue;              // 切向越界 → 排除
            if (ppixel[j] <= th) {
                cx += offx;
                cy += offy;
                cnt++;
            }
        }
    }

    if (cnt > 0) {
        *dx = (double)cx / cnt;
        *dy = (double)cy / cnt;
        return 1;
    }
    *dx = 0;
    *dy = 0;
    return 0;
}

//方向性质心版 amend_center：最多迭代 MAX_TRY 次收敛到框线中心
static int amend_center_dir(IMAGE* image,
    double ini_cx, double ini_cy, CircleArea* ca,
    double ux, double uy, double tan_half,
    double* out_cx, double* out_cy)
{
    double dx, dy;
    int MAX_TRY = islii_get_fast_mode() ? 2 : 3;
    double T = ca->r / 8;
    if (T < 1) T = 1;

    for (int i = 0; i < MAX_TRY; i++) {
        if (ROUND2INT(ini_cx) < ca->r || ROUND2INT(ini_cx) + ca->r >= image->w ||
            ROUND2INT(ini_cy) < ca->r || ROUND2INT(ini_cy) + ca->r >= image->h)
            break;

        if (!calc_center_shift_dir(image, ini_cx, ini_cy, ca, ux, uy, tan_half, &dx, &dy))
            break;

        if (dx <= T && dx >= -T && dy <= T && dy >= -T) {
            *out_cx = ini_cx + dx;
            *out_cy = ini_cy + dy;
            return 1;
        }
        ini_cx += dx;
        ini_cy += dy;
    }
    return 0;
}

//兼容别名（旧名保留，内部指向方向性质心）
static int amend_center_mf(IMAGE* image,
    double ini_cx, double ini_cy,
    double tan_dx, double tan_dy,
    double frame_width, CircleArea* ca,
    double* out_cx, double* out_cy)
{
    double tl = sqrt(tan_dx * tan_dx + tan_dy * tan_dy);
    double ux = (tl > 1e-6) ? tan_dx / tl : 1.0;
    double uy = (tl > 1e-6) ? tan_dy / tl : 0.0;
    //切向半宽：方向性质心实验参数（A/B 显示不优于全质心，默认不启用）
    double tan_half = frame_width * 2.0;
    if (tan_half > ca->r) tan_half = ca->r;
    return amend_center_dir(image, ini_cx, ini_cy, ca, ux, uy, tan_half, out_cx, out_cy);
}

//单次追踪尝试（给定圆盘半径系数 radius_mult 与步长系数 step_mult）
//allow_jump: stage-3 角点跳跃——脱轨时沿预测方向跨过角点，在下一条边上续追
static int trace_once(IMAGE* image, int sx0, int sy0, int sx1, int sy1, double frame_width,
                      double radius_mult, double step_mult, int use_mf, int allow_jump,
                      double* px, double* py, int* dot_num)
{
    CircleArea ca;
    init_CircleArea(&ca, (short)ROUND2INT(frame_width * radius_mult));

    // 初始切向：calc_step 给出沿框线的步进方向（垂直于 pos1->pos2 连线）
    double step = frame_width * step_mult;
    double step_dx = 0, step_dy = 0;
    calc_step(sx0, sy0, sx1, sy1, step, &step_dx, &step_dy);
    double ini_tan_x = step_dx, ini_tan_y = step_dy;
    double sl = sqrt(ini_tan_x * ini_tan_x + ini_tan_y * ini_tan_y);
    if (sl < 1e-6) { ini_tan_x = 1; ini_tan_y = 0; }
    else { ini_tan_x /= sl; ini_tan_y /= sl; }

    double amended_cx = 0, amended_cy = 0;
    double ini_cx = sx0, ini_cy = sy0;
    int ok;
    if (use_mf)
        ok = amend_center_mf(image, ini_cx, ini_cy, ini_tan_x, ini_tan_y, frame_width, &ca, &amended_cx, &amended_cy);
    else
        ok = amend_center(image, ini_cx, ini_cy, &ca, &amended_cx, &amended_cy);

    if (!ok) { uninit_CircleArea(&ca); return 0; }
    ini_cx = amended_cx; ini_cy = amended_cy;

    double last_cx = ini_cx, last_cy = ini_cy;
    double cur_cx = ini_cx + step_dx, cur_cy = ini_cy + step_dy;
    double dx = step_dx, dy = step_dy;
    int succ = 1, cnt = 1;
    px[0] = ini_cx; py[0] = ini_cy;

    //stage-3 角点跳跃参数
    static const int   MAX_JUMPS    = 6;    // 最多跳过6个角点（盾牌4角 + 容错）
    static const double JUMP_FACTOR  = 2.5; // 跳跃距离 = JUMP_FACTOR * step
    int jumps = 0;

    for (;;) {
        //当前切向 = 移动方向单位化
        double ml = sqrt(dx * dx + dy * dy);
        double tan_x = (ml > 1e-6) ? dx / ml : ini_tan_x;
        double tan_y = (ml > 1e-6) ? dy / ml : ini_tan_y;

        int ok2;
        if (use_mf)
            ok2 = amend_center_mf(image, cur_cx, cur_cy, tan_x, tan_y, frame_width, &ca, &amended_cx, &amended_cy);
        else
            ok2 = amend_center(image, cur_cx, cur_cy, &ca, &amended_cx, &amended_cy);

        //P1 角点恢复：mode 0 脱轨时先试半距步（温和处理角点区域）
        if (!ok2 && !allow_jump && !use_mf) {
            cur_cx = last_cx + tan_x * step * 0.5;
            cur_cy = last_cy + tan_y * step * 0.5;
            ok2 = amend_center(image, cur_cx, cur_cy, &ca, &amended_cx, &amended_cy);
        }
        //stage-3：脱轨时沿切向跨过角点，在下一条边续追
        if (!ok2 && allow_jump && jumps < MAX_JUMPS) {
            jumps++;
            cur_cx = last_cx + tan_x * step * JUMP_FACTOR;
            cur_cy = last_cy + tan_y * step * JUMP_FACTOR;
            if (use_mf)
                ok2 = amend_center_mf(image, cur_cx, cur_cy, tan_x, tan_y, frame_width, &ca, &amended_cx, &amended_cy);
            else
                ok2 = amend_center(image, cur_cx, cur_cy, &ca, &amended_cx, &amended_cy);
        }
        if (!ok2) { succ = 0; break; }

        px[cnt] = amended_cx; py[cnt] = amended_cy; cnt++;
        if (cnt >= *dot_num) { succ = 0; break; }

        dx = amended_cx - last_cx; dy = amended_cy - last_cy;
        if (0 == dx && 0 == dy) { succ = 0; break; }
        double L = dx * dx + dy * dy;
        dx = dx * step / sqrt(L); dy = dy * step / sqrt(L);
        cur_cx = amended_cx + dx; cur_cy = amended_cy + dy;
        last_cx = amended_cx; last_cy = amended_cy;

        double a = ini_cx - cur_cx, b = ini_cy - cur_cy;
        if (cnt > 10 && -step < a && a < step && -step < b && b < step) {
            *dot_num = cnt; break;
        }
    }
    uninit_CircleArea(&ca);
    int got = cnt - 1;
    if (got > g_last_trace_progress) g_last_trace_progress = got;
    //实验：脱轨但已走过足够长（>= PARTIAL_MIN）的部分弧也接受，
    //交由 corner_finder 处理近乎闭合的弧（盾牌周长约167点）。
    if (succ) return 1;
    static const int PARTIAL_MIN = 100;
    if (got >= PARTIAL_MIN) { *dot_num = got; return 1; }
    return 0;
}

int do_trace_frame(IMAGE* image, int sx0, int sy0, int sx1, int sy1, double frame_width,
                   double* px, double* py, int* dot_num)
{
    ISLII_LOGI("[trace] start: start=(%d,%d) end=(%d,%d) frame_width=%.1f max_dots=%d mode=%d",
               sx0, sy0, sx1, sy1, frame_width, *dot_num, g_trace_mode);

    g_last_trace_progress = 0;
    int use_mf = (g_trace_mode != 0);
    //stage-3：mode 2 启用角点跳跃
    int allow_jump = (g_trace_mode == 2);
    int max_dots = *dot_num;

    //单次追踪（原始参数 r=1.1fw, step=0.5fw）
    int dn = max_dots;
    int ok = trace_once(image, sx0, sy0, sx1, sy1, frame_width, 1.1, 0.50, use_mf, allow_jump, px, py, &dn);
    if (ok && dn >= 88 && dn <= max_dots - 4) {
        *dot_num = dn;
        ISLII_LOGI("[trace] OK: dot_num=%d jump=%d", dn, allow_jump);
        return 1;
    }

    ISLII_LOGE("[trace] FAILED: derailed (best progress=%d dots)", g_last_trace_progress);
    return 0;
}
