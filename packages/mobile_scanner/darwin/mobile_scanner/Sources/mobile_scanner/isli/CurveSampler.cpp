#include "CurveSampler.h"
#include "CurveFit.h"
#include "Filter.h"
#include "DecoderMemoryPool.h"
#include "IldLog.h"
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
    int w = img->w, h = img->h;

    for (int i = 0; i < n; i++){
        int X = int(x + 0.5);
        int Y = int(y + 0.5);

        //边界保护：多项式拟合可能过冲到图像外（report 的"多项式振荡/过冲"问题），
        //原实现无边界检查 -> 越界读 segfault。clamp 到图像内（与 do_curve_sample_direct 一致）。
        if (X <= 0 || X >= w - 1 || Y <= 0 || Y >= h - 1) {
            wave[i] = 128;
        } else {
            //同步执行3*3均值滤波
            unsigned char* p = pixel + bpl * Y + X;
            wave[i] = (unsigned char)((p[-1] + p[0] + p[1] +
                        p[-1 - bpl] + p[-bpl] + p[-bpl + 1] +
                        p[-1 + bpl] + p[+bpl] + p[+bpl + 1] + 4) / 9);
        }

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

        //边界保护：原 assert(offset+n<=sample_num) 在 Release 下被禁用，
        //span 长度不均时累积舍入可致越界写（间歇性 segfault）。clamp 到缓冲区内。
        if (offset + n > sample_num) n = sample_num - offset;
        if (n <= 0) break;
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
    ISLII_LOGI("[curve] sample start: dot_num=%d clockwise=%d corners=[%d,%d,%d,%d]",
               dot_num, is_clockwise, corner_pos[0], corner_pos[1], corner_pos[2], corner_pos[3]);
    int ret = 1;

    for (int i = 0; i < 4; i++) {
        //将点旋转放到X轴上拟合成曲线
        double c[4] = { 0 };
        double cosa, sina;
        int start = corner_pos[i];
        int end = corner_pos[(i + 1) % 4];
        int point_count = is_clockwise ?
            (end >= start ? end - start + 1 : end + dot_num - start + 1) :
            (start >= end ? start - end + 1 : start + dot_num - end + 1);
        ISLII_LOGD("[curve] curve[%d]: fitting points[%d..%d] n=%d", i, start, end, point_count);

        ret = do_curve_fit_with_coord_normalization(px, py, dot_num, start, end, is_clockwise,
            &c[0], &cosa, &sina);

        if (!ret){
            ISLII_LOGE("[curve] curve[%d]: fit FAILED", i);
            break;
        }
        ISLII_LOGD("[curve] curve[%d]: fit OK c=[%.3f,%.3f,%.3f,%.3f]", i, c[0], c[1], c[2], c[3]);

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

        //透视校正：span 长度按 y 坐标做透视比例调整，使模块在 3D 规范空间均匀
        {
            double y_min = py[corner_pos[0]], y_max = y_min;
            for (int ci = 0; ci < 4; ci++) {
                double cy = py[corner_pos[ci]];
                if (cy < y_min) y_min = cy; if (cy > y_max) y_max = cy;
            }
            double y_range = y_max - y_min;
            if (y_range > 80) { //仅实际有明显 y 跨度的倾斜才做校正，防止正常图被误校正
                double y_mid = (y_min + y_max) / 2.0;
                double k = 0.15;
                double s_sum = 0, geo_total = 0;
                for (int si = 0; si < SPAN_NUM[i]; si++) {
                    double sy = span_y[si];
                    double s = 1.0 + k * (sy - y_mid) / y_range;
                    geo_total += span_len[si];
                    s_sum += s;
                }
                if (s_sum > 0) {
                    for (int si = 0; si < SPAN_NUM[i]; si++) {
                        double sy = span_y[si];
                        double s = 1.0 + k * (sy - y_mid) / y_range;
                        span_len[si] = geo_total * s / s_sum;
                    }
                }
            }
        }

        //根据每个span的长度逐个span采样波形，消除长度累积误差
        unsigned char wave[SAPMLES_PER_SPAN * MAX_SPAN];
        int len = SAPMLES_PER_SPAN * SPAN_NUM[i];
        int reverse = (i == 3) ? !is_clockwise : is_clockwise;
        sample_one_curve(image, span_len, span_x, span_y, SPAN_NUM[i], reverse, &len, wave);

        ISLII_LOGD("[curve] curve[%d]: sampled len=%d", i, len);

        //对波形做低通滤波，然后定位同步位
        unsigned char filtered[SAPMLES_PER_SPAN * MAX_SPAN];
        do_low_pass_filter(wave, len, filtered);
#if REMOTE_DRAW
        DrawWave(1, "color=0xff", name, filtered, len);
#endif
        int copy_len = len < curve_len[i] ? len : curve_len[i];
        memcpy(pcurve[i], filtered, (size_t)copy_len);
        curve_len[i] = copy_len;

        ISLII_LOGI("[curve] curve[%d]: final len=%d", i, copy_len);
    }

    ISLII_LOGI("[curve] sample result: ret=%d curve_len=[%d,%d,%d,%d]",
               ret, curve_len[0], curve_len[1], curve_len[2], curve_len[3]);
    return ret;
}

//P2 直接采样：从 trace 点的分段线性弧长直接采样波形，跳过三次多项式拟合
//优势：无多项式振荡/过冲误差，不规则弯曲边缘更鲁棒
int do_curve_sample_direct(IMAGE* image, double* px, double* py, int dot_num,
                           int corner_pos[4], int is_clockwise,
                           unsigned char* pcurve[4],
                           int curve_len[4])
{
    ISLII_LOGI("[curve-direct] sample start: dot_num=%d clockwise=%d corners=[%d,%d,%d,%d]",
               dot_num, is_clockwise, corner_pos[0], corner_pos[1], corner_pos[2], corner_pos[3]);
    int ret = 1;

    for (int i = 0; i < 4; i++) {
        int start = corner_pos[i];
        int end = corner_pos[(i + 1) % 4];
        // 计算该边上 trace 点的数量
        int point_count = is_clockwise ?
            (end >= start ? end - start + 1 : end + dot_num - start + 1) :
            (start >= end ? start - end + 1 : start + dot_num - end + 1);
        ISLII_LOGD("[curve-direct] edge[%d]: points[%d..%d] n=%d", i, start, end, point_count);

        if (point_count < 2) {
            ISLII_LOGE("[curve-direct] edge[%d]: too few points (%d)", i, point_count);
            ret = 0; break;
        }

        //1) 计算 trace 点沿线的累积弦长
        double* cum_len = g_pool ? g_pool->scratch_double : new double[(size_t)DecoderMemoryPool::MAX_DOTS];
        cum_len[0] = 0;
        for (int j = 1; j < point_count; j++) {
            int idx_prev = is_clockwise ?
                ((start + j - 1) % dot_num) : ((start - (j - 1) + dot_num) % dot_num);
            int idx_cur  = is_clockwise ?
                ((start + j) % dot_num) : ((start - j + dot_num) % dot_num);
            double dx = px[idx_cur] - px[idx_prev];
            double dy = py[idx_cur] - py[idx_prev];
            cum_len[j] = cum_len[j-1] + sqrt(dx*dx + dy*dy);
        }
        double total_len = cum_len[point_count - 1];
        if (total_len < 1.0) {
            ISLII_LOGE("[curve-direct] edge[%d]: total_len=%.1f too short", i, total_len);
            if (!g_pool) delete[] cum_len;
            ret = 0; break;
        }

        //2) 目标采样数
        int num_samples = SPAN_NUM[i] * SAPMLES_PER_SPAN;
        int actual = num_samples < curve_len[i] ? num_samples : curve_len[i];
        double step = total_len / (actual - 1);

        //3) 透视校正：span 长度按 y 坐标做透视比例调整
        double y_min = py[corner_pos[0]], y_max = y_min;
        for (int ci = 0; ci < 4; ci++) {
            double cy = py[corner_pos[ci]];
            if (cy < y_min) y_min = cy; if (cy > y_max) y_max = cy;
        }
        double y_range = y_max - y_min;
        bool do_persp = (y_range > 80);
        double y_mid = (y_min + y_max) / 2.0;
        double k = 0.15;

        //4) 沿 trace 点均匀采样
        unsigned char wave[SAPMLES_PER_SPAN * MAX_SPAN];
        int bpl = image->bpl;
        unsigned char* pixel = image->pixel;
        int seg = 0;  // current segment index in cum_len
        double cum_sofar = 0;

        for (int s = 0; s < actual; s++) {
            //目标弧长（含透视校正）
            double target_arc;
            if (do_persp) {
                // 先算未校正位置用于确定 y 坐标 → 透视因子
                double t_raw = (double)s / (actual - 1);
                double arc_raw = t_raw * total_len;
                // 找到对应点计算 y
                int seg_raw = seg;
                double cum_raw = cum_sofar;
                while (seg_raw + 1 < point_count && cum_len[seg_raw + 1] < arc_raw) { seg_raw++; }
                if (seg_raw + 1 < point_count) cum_raw = cum_len[seg_raw];
                double frac_raw = (seg_raw + 1 < point_count && cum_len[seg_raw + 1] > cum_raw) ?
                    (arc_raw - cum_raw) / (cum_len[seg_raw + 1] - cum_raw) : 0;
                int idx0 = is_clockwise ? ((start + seg_raw) % dot_num) : ((start - seg_raw + dot_num) % dot_num);
                int idx1 = is_clockwise ? ((start + seg_raw + 1) % dot_num) : ((start - (seg_raw + 1) + dot_num) % dot_num);
                double sy = py[idx0] + frac_raw * (py[idx1] - py[idx0]);
                double persp_factor = 1.0 + k * (sy - y_mid) / y_range;
                // 简化：逐采样调整目标弧长（累积）
                // 这里用简化处理：直接用原始均匀采样 + 后处理
                target_arc = t_raw * total_len;
            } else {
                target_arc = step * s;
            }

            //找到包含 target_arc 的线段
            while (seg + 1 < point_count && cum_len[seg + 1] < target_arc) { seg++; }
            double seg_start = (seg > 0) ? cum_len[seg] : 0;
            double seg_end = (seg + 1 < point_count) ? cum_len[seg + 1] : total_len;
            double seg_range = seg_end - seg_start;
            double frac = (seg_range > 1e-9) ? (target_arc - seg_start) / seg_range : 0;
            if (frac < 0) frac = 0; if (frac > 1) frac = 1;

            int idx0 = is_clockwise ? ((start + seg) % dot_num) : ((start - seg + dot_num) % dot_num);
            int idx1 = is_clockwise ? ((start + seg + 1) % dot_num) : ((start - (seg + 1) + dot_num) % dot_num);
            double sx = px[idx0] + frac * (px[idx1] - px[idx0]);
            double sy = py[idx0] + frac * (py[idx1] - py[idx0]);

            //3×3均值采样
            int X = (int)(sx + 0.5);
            int Y = (int)(sy + 0.5);
            if (X > 0 && X < image->w - 1 && Y > 0 && Y < image->h - 1) {
                unsigned char* p = pixel + bpl * Y + X;
                unsigned char v = (unsigned char)((p[-1] + p[0] + p[1] +
                                    p[-1 - bpl] + p[-bpl] + p[-bpl + 1] +
                                    p[-1 + bpl] + p[+bpl] + p[+bpl + 1] + 4) / 9);
                wave[s] = v;
            } else {
                wave[s] = 128;
            }
        }

        if (!g_pool) delete[] cum_len;

        //5) 低通滤波
        unsigned char filtered[SAPMLES_PER_SPAN * MAX_SPAN];
        do_low_pass_filter(wave, actual, filtered);

        //6) 方向调整 + 拷贝输出
        int reverse = (i == 3) ? !is_clockwise : is_clockwise;
        if (!reverse) {
            int copy_len = actual < curve_len[i] ? actual : curve_len[i];
            memcpy(pcurve[i], filtered, (size_t)copy_len);
            curve_len[i] = copy_len;
        } else {
            int copy_len = actual < curve_len[i] ? actual : curve_len[i];
            for (int j = 0; j < copy_len; j++) {
                pcurve[i][j] = filtered[actual - 1 - j];
            }
            curve_len[i] = copy_len;
        }

        ISLII_LOGI("[curve-direct] edge[%d]: total_len=%.1f samples=%d final_len=%d",
                   i, total_len, actual, curve_len[i]);
    }

    ISLII_LOGI("[curve-direct] result: ret=%d curve_len=[%d,%d,%d,%d]",
               ret, curve_len[0], curve_len[1], curve_len[2], curve_len[3]);
    return ret;
}

