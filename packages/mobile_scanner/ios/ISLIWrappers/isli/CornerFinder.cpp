#include "CornerFinder.h"
#include "CornerFinetuner.h"
#include "DecoderMemoryPool.h"
#include "IldLog.h"
#include <math.h>
#include <string.h>

#define REMOTE_DRAW 0
#if REMOTE_DRAW
#include "canvas.h"
#endif

#define A2D(x) (int)(((x)*180/3.1415926+0.5))

//优化：用atan2替代手动8分支象限判断+atan，调用一次函数完成
static int deriv2angle(double x0, double y0, double x1, double y1)
{
    double dx = x1 - x0;
    double dy = y1 - y0;
    //atan2返回[-π, π]，转换为[0, 360)
    int alpha = A2D(atan2(dy, dx));
    if (alpha < 0) alpha += 360;
    return alpha;
}

static void sort(int* a, int* b)
{
    if (*a > *b) {
        int t = *a;
        *a = *b;
        *b = t;
    }
}

static void split_by_local_max(int* value, int len, int peak_pos[4])
{
    static const int PEAK_SIZE = 10;
    int peak_count = 0;

    for (int k = 0; k < 4; k++) {
        int max = 0;
        int pos = 0;
        for (int i = 0; i < len; i++) {
            if (value[i] > max) {
                int near_peak = 0;
                
                for (int j = 0; j < peak_count; j++){
                    int d = i - peak_pos[j];
                    if (-PEAK_SIZE < d && d < PEAK_SIZE) {
                        near_peak = 1;
                        break;
                    }
                }
                
                if (!near_peak) {
                    max = value[i];
                    pos = i;
                }
            }
        }
        peak_pos[k] = pos;
        peak_count = k + 1;
    }

    sort(peak_pos + 0, peak_pos + 1);
    sort(peak_pos + 2, peak_pos + 3);
    sort(peak_pos + 0, peak_pos + 2);//0最小
    sort(peak_pos + 1, peak_pos + 3);//3最大
    sort(peak_pos + 1, peak_pos + 2);
}

//返回值指示px,py是否为顺时针方向排列
static int normalize_corners_sequence(double* px, double* py, int corner_pos[4])
{
    double cx = 0;
    double cy = 0;
    
    //计算四角的中心
    for (int i = 0; i < 4; i++) {
        int pos = corner_pos[i];
        cx += px[pos];
        cy += py[pos];
    }
    cx /= 4;
    cy /= 4;
    
    //计算四角相对中心的角度
    int angle[4];
    for (int i = 0; i < 4; i++){
        int pos = corner_pos[i];
        angle[i] = deriv2angle(cx, cy, px[pos], py[pos]);
    }
    
    //判断旋转角度
    int is_clockwise = 0;
    if (((angle[0] < angle[1]) && ((angle[1] - angle[0]) < 180)) ||
        ((angle[1] - angle[0] + 360) < 180)){
        //顺时针
        is_clockwise = 1;
    }
    
    //计算角度差
    int det_angle[4];
    for (int i = 0; i < 4; i++) {
        det_angle[i] = is_clockwise ? (angle[(i + 1) % 4] - angle[i])
                                    : (angle[i] - angle[(i + 1) % 4]);
        if (det_angle[i] < 0) {
            det_angle[i] += 360;
        }
    }  
    
    //找到最大的角度差，并根据最大角确定角的编号
    int max = det_angle[0];
    int k = 0;
    for (int i = 1; i < 4; i++) {
        if (det_angle[i] > max) {
            max = det_angle[i];
            k = i;
        }
    }
    int normalized_corner[4];
    if (is_clockwise) {
        if (det_angle[(k + 1) % 4] < det_angle[(k - 1 + 4) % 4]) {
            normalized_corner[0] = (k + 1) % 4;
            normalized_corner[1] = (k + 2) % 4;
            normalized_corner[2] = (k + 3) % 4;
            normalized_corner[3] = (k + 4) % 4;
        }
        else {
            normalized_corner[0] = (k + 2) % 4;
            normalized_corner[1] = (k + 3) % 4;
            normalized_corner[2] = (k + 4) % 4;
            normalized_corner[3] = (k + 5) % 4;
        }
    }
    else {
        if (det_angle[(k - 1 + 4) % 4] < det_angle[(k + 1) % 4]) {
            normalized_corner[0] = (k + 4) % 4;
            normalized_corner[1] = (k + 3) % 4;
            normalized_corner[2] = (k + 2) % 4;
            normalized_corner[3] = (k + 1) % 4;
        }
        else {
            normalized_corner[0] = (k + 3) % 4;
            normalized_corner[1] = (k + 2) % 4;
            normalized_corner[2] = (k + 1) % 4;
            normalized_corner[3] = (k + 0) % 4;
        }
    }
    
    //调整编号
    int t[4];
    t[0] = corner_pos[normalized_corner[0]];
    t[1] = corner_pos[normalized_corner[1]];
    t[2] = corner_pos[normalized_corner[2]];
    t[3] = corner_pos[normalized_corner[3]];
    corner_pos[0] = t[0];
    corner_pos[1] = t[1];
    corner_pos[2] = t[2];
    corner_pos[3] = t[3];

    return is_clockwise;
}

void finetune_corners(IMAGE* image, double* px, double* py, int dot_num, int corner_pos[4], double frame_width, int is_clockwise)
{
    ISLII_LOGI("[corner] finetune start: frame_width=%.1f clockwise=%d", frame_width, is_clockwise);
    //长弧头尾剔除7个点，短弧头尾剔除3个点
    static const int SKIP[2][4][2] = { { { 7, 3 }, { 3, 3 }, { 3, 7 }, { 7, 7 } },
                                       { { 3, 7 }, { 3, 3 }, { 7, 3 }, { 7, 7 } } };
    int orient = is_clockwise ? 0 : 1;

    for (int i = 0; i < 4; i++){
        int k = corner_pos[i];
        short sx = (short)(px[k] + 0.5);
        short sy = (short)(py[k] + 0.5);
        short tx = 0;
        short ty = 0;

        fine_tune_corner_coord(image, sx, sy, (short)(frame_width+0.5), &tx, &ty);
        ISLII_LOGI("[corner] corner[%d]: raw=(%d,%d) -> fine=(%d,%d) skip=[%d,%d]",
                   i, sx, sy, tx, ty, SKIP[orient][i][0], SKIP[orient][i][1]);

        //剔除低精度的点对曲线拟合的贡献
        for (int j = k - SKIP[orient][i][0]; j <= k + SKIP[orient][i][1]; j++) {
            int m = (j + dot_num) % dot_num;
            px[m] = tx;
            py[m] = ty;
        }
    }
#if REMOTE_DRAW
    for (int i = 0; i < dot_num; i++){
        __canvas.DrawDot("source", "color=0xff00", (short)(px[i]+0.5), (short)(py[i]+0.5));
    }
#endif
}

//返回值指示px,py是否为顺时针方向排列
int do_corner_finder(double* px, double* py, int dot_num, int corner_pos[4])
{
    ISLII_LOGI("[corner] finding corners: dot_num=%d", dot_num);
    int* angle = g_pool ? g_pool->angle_buf : new int[(size_t)dot_num];

    for (int i = 0; i < dot_num; i++) {
        int m = i - 4;
        if (m < 0)
            m += dot_num;
        int n = i + 4;
        if (n >= dot_num)
            n -= dot_num;
        int alpha_back = deriv2angle(px[i], py[i], px[m], py[m]);
        int alpha_fore = deriv2angle(px[i], py[i], px[n], py[n]);
        int diff = alpha_back > alpha_fore ? alpha_back - alpha_fore : alpha_fore - alpha_back;
        if (diff > 90 && diff <= 180) {
            diff = 180 - diff;
        }
        else if (diff > 180 && diff <= 270) {
            diff = diff - 180;
        }
        else if (diff > 270){
            diff = 360 - diff;
        }
        angle[i] = diff;
    }

    split_by_local_max(angle, dot_num, corner_pos);

    //部分弧 gap 假角点检测：部分弧的环形回绕（px[N-1]→px[0]）会
    //在 gap 附近产生人工角度极值，被误判为角点。检测并替换之。
    static const int GAP_MARGIN = 8;
    bool is_partial = (dot_num < 155);  // 完整闭环约167点，<155为部分弧
    if (is_partial) {
        for (int i = 0; i < 4; i++) {
            int k = corner_pos[i];
            if (k < GAP_MARGIN || k > dot_num - GAP_MARGIN) {
                // gap 附近的疑似假角点 → 搜索下一个最佳角度峰
                static const int PK = 10;
                int max_v = 0, max_p = 0;
                for (int m = 0; m < dot_num; m++) {
                    if (angle[m] > max_v) {
                        int near = 0;
                        for (int j = 0; j < 4; j++) {
                            int d = m - corner_pos[j];
                            if (j != i && -PK < d && d < PK) { near = 1; break; }
                        }
                        if (!near) { max_v = angle[m]; max_p = m; }
                    }
                }
                ISLII_LOGD("[corner] gap-artifact corner[%d]=%d replaced by %d", i, k, max_p);
                corner_pos[i] = max_p;
            }
        }
        //更新排序
        sort(corner_pos + 0, corner_pos + 1);
        sort(corner_pos + 2, corner_pos + 3);
        sort(corner_pos + 0, corner_pos + 2);
        sort(corner_pos + 1, corner_pos + 3);
        sort(corner_pos + 1, corner_pos + 2);
    }

    if (!g_pool) delete[] angle;

    int is_clockwise = normalize_corners_sequence(px, py, corner_pos);

    ISLII_LOGI("[corner] found: pos=(%d,%d,%d,%d) coords=(%.1f,%.1f)-(%.1f,%.1f)-(%.1f,%.1f)-(%.1f,%.1f) clockwise=%d",
               corner_pos[0], corner_pos[1], corner_pos[2], corner_pos[3],
               px[corner_pos[0]], py[corner_pos[0]],
               px[corner_pos[1]], py[corner_pos[1]],
               px[corner_pos[2]], py[corner_pos[2]],
               px[corner_pos[3]], py[corner_pos[3]],
               is_clockwise);

    return is_clockwise;
}

