#include "ISLIIconLocator.h"
#include "ISLIIconDecoder.h"
#include "Filter.h"
#include "Binarization.h"
#include "BSPatternMatch.h"
#include "LineScanner.h"
#include "DecoderMemoryPool.h"
#include "IldLog.h"
#include <math.h>
#include <assert.h>

#define REMOTE_DRAW 0
#if REMOTE_DRAW
#include "canvas.h"
#endif

static const int MIN_EDGE = 40;       //标志码中ISLI字符离开图像的最小边界
//快速模式：扫描步长加倍，大幅减少扫描线数（性能优先）
static inline int scan_line_dis() { return islii_get_fast_mode() ? 25 : 15; }
static inline int skew_scan_dis() { return islii_get_fast_mode() ? 20 : 11; }

static int locate_in_line(unsigned char* gray_line, int line_len, int* pos1, int* pos2, double* frame_size)
{
    unsigned short* bs = g_pool ? g_pool->bs_buf : new unsigned short[(size_t)line_len / 4];

    //优化：先用快速全局阈值二值化尝试匹配，90%+场景足够
    //失败时再回退到完整的自适应阈值二值化
    int bs_num = do_binarizaiton_fast(gray_line, line_len, bs, line_len / 4);
    int r = do_bspatternmatch(bs, bs_num, pos1, pos2, frame_size);
    //性能优化：快速路径BS数过少(<8)时跳过完整回退
    if (!r && bs_num >= 8) {
        bs_num = do_binarizaiton(gray_line, line_len, bs, line_len / 4);
        r = do_bspatternmatch(bs, bs_num, pos1, pos2, frame_size);
    }
    //倾斜回退：标准容差(±10%)失败后，用宽容差(±13%)再试一次——覆盖上下倾斜导致的条宽微变形
    if (!r && bs_num >= 8) {
        r = do_bspatternmatch_wide(bs, bs_num, pos1, pos2, frame_size);
    }

    if (!g_pool) delete[] bs;

    return r;
}

static int do_horizontal_locating(IMAGE* image,
                                  int* x1, int* y1, int* x2, int* y2, double* frame_size)
{
    ISLII_LOGI("[locate] horizontal scan start, image w=%d h=%d", image->w, image->h);
    int y = image->h / 2;
    int step = scan_line_dis();
    int scan_count = 0;

    int k = 0;
    while (y >= MIN_EDGE && y < image->h - MIN_EDGE) {
        y = image->h / 2 + k * step;
        if (y >= image->h - MIN_EDGE){
            break;
        }
        scan_count++;
        if (locate_in_line(image->pixel + y * image->bpl, image->w, x1, x2, frame_size)) {
            *y1 = *y2 = y;
            ISLII_LOGI("[locate] horizontal MATCH: y=%d box=(%d,%d)-(%d,%d) frame_size=%.1f scans=%d",
                       y, *x1, *y1, *x2, *y2, *frame_size, scan_count);
            return 1;
        }

        if (0 == k) {
            k++;
            continue; //第一次扫描
        }
        y = image->h / 2 - k * step;
        if (y < MIN_EDGE){
            break;
        }
        scan_count++;
        if (locate_in_line(image->pixel + y * image->bpl, image->w, x1, x2, frame_size)) {
            *y1 = *y2 = y;
            ISLII_LOGI("[locate] horizontal MATCH: y=%d box=(%d,%d)-(%d,%d) frame_size=%.1f scans=%d",
                       y, *x1, *y1, *x2, *y2, *frame_size, scan_count);
            return 1;
        }
        k++;
    }

    ISLII_LOGD("[locate] horizontal: no match after %d scans", scan_count);
    return 0;
}


static int do_vertical_locating(IMAGE* image,
                                int* x1, int* y1, int* x2, int* y2, double* frame_size)
{
    ISLII_LOGI("[locate] vertical scan start");
    unsigned char* pline = g_pool ? g_pool->vert_scan_buf : new unsigned char[(size_t)image->h];

    int ret = 0;
    int x = image->w / 2;
    int step = scan_line_dis();
    int scan_count = 0;

    int k = 0;
    while (x >= MIN_EDGE && x < image->w - MIN_EDGE) {
        x = image->w / 2 + k * step;
        if (x >= image->w - MIN_EDGE){
            break;
        }
        scan_count++;
        do_vertical_scan(image, x, pline);
        if (locate_in_line(pline, image->h, y1, y2, frame_size)) {
            *x1 = *x2 = x;
            ret = 1;
            break;
        }
        if (0 == k) {
            k++;
            continue; //第一次扫描
        }

        x = image->w / 2 - k * step;
        if (x < MIN_EDGE){
            break;
        }
        scan_count++;
        do_vertical_scan(image, x, pline);
        if (locate_in_line(pline, image->h, y1, y2, frame_size)) {
            *x1 = *x2 = x;
            ret = 1;
            break;
        }
        k++;
    }

    if (ret) {
        ISLII_LOGI("[locate] vertical MATCH: x=%d box=(%d,%d)-(%d,%d) frame_size=%.1f scans=%d",
                   *x1, *x1, *y1, *x2, *y2, *frame_size, scan_count);
    } else {
        ISLII_LOGD("[locate] vertical: no match after %d scans", scan_count);
    }

    if (!g_pool) delete[] pline;

    return ret;
}

//斜线扫描状态 — 用于延迟生成斜线，逐条生成逐条扫描
struct SkewLineGenState {
    int w, h;
    int i;         // current iteration index
    int end0;      // upper zone exhausted?
    int end1;      // lower zone exhausted?
    bool is_135;   // true=135 degrees, false=45 degrees
    bool done;     // all lines generated?
    bool diag_done; // first diagonal already returned?
    int phase;     // 0=try upper zone next, 1=try lower zone next
};

static void init_skew_line_gen(SkewLineGenState* st, int w, int h, bool is_135)
{
    st->w = w;
    st->h = h;
    st->i = 1;
    st->end0 = 0;
    st->end1 = 0;
    st->is_135 = is_135;
    st->done = false;
    st->diag_done = false;
    st->phase = 0;
}

// Generate next skew line on demand. Returns 1 if line is valid, 0 if done.
// The generator yields lines in this order:
//   1. Main diagonal (once)
//   2. For i=1,2,3,...: upper zone line (if valid), then lower zone line (if valid)
static int next_skew_line(SkewLineGenState* st, SKEW_LINE* line)
{
    static const int MARGIN = 150;
    double dx = 1.0 / sqrt(2.0);
    double dy = st->is_135 ? -dx : dx;

    if (st->done) return 0;

    // First diagonal — return exactly once
    if (!st->diag_done) {
        st->diag_done = true;
        int edge = st->w < st->h ? st->w : st->h;
        line->sx = 0;
        line->sy = st->is_135 ? (st->h - 1) : 0;
        line->dx = dx;
        line->dy = dy;
        line->len = int(edge * sqrt(2.0));
        return 1;
    }

    // Iterate over i values, yielding upper-then-lower at each i
    while (st->i < 1000) {
        int sx, sy, ex, ey, m, n;

        if (st->phase == 0) {
            // Try upper zone at current i
            if (st->is_135) {
                sy = st->h - 1 - st->i * skew_scan_dis();
                if (sy > MARGIN) {
                    sx = 0;
                    ex = sy; if (ex >= st->w) { ey = ex - (st->w - 1); ex = st->w - 1; } else ey = 0;
                    m = ex - sx; n = ey - sy;
                    line->len = int(sqrt((double)(m * m + n * n)));
                    line->sx = sx; line->sy = sy; line->dx = dx; line->dy = dy;
                    st->phase = 1; // next call yields lower
                    return 1;
                }
                st->end0 = 1;
            } else {
                sy = st->i * skew_scan_dis();
                if (sy + MARGIN < st->h) {
                    sx = 0;
                    ex = st->h - 1 - sy; if (ex > st->w - 1) ex = st->w - 1;
                    ey = ex + sy; if (ey >= st->h - 1) ey = st->h - 1;
                    m = ex - sx; n = ey - sy;
                    line->len = int(sqrt((double)(m * m + n * n)));
                    line->sx = sx; line->sy = sy; line->dx = dx; line->dy = dy;
                    st->phase = 1;
                    return 1;
                }
                st->end0 = 1;
            }
            st->phase = 1; // upper failed, try lower next
        }

        // Try lower zone at current i (phase == 1)
        if (st->is_135) {
            sx = st->i * skew_scan_dis();
            if (st->w - sx > MARGIN) {
                sy = st->h - 1;
                ex = st->h - 1 + sx; if (ex >= st->w) { ey = ex - (st->w - 1); ex = st->w - 1; } else ey = 0;
                m = ex - sx; n = ey - sy;
                line->len = int(sqrt((double)(m * m + n * n)));
                line->sx = sx; line->sy = sy; line->dx = dx; line->dy = dy;
                st->phase = 0; st->i++; // next call: upper at next i
                return 1;
            }
            st->end1 = 1;
        } else {
            sx = st->i * skew_scan_dis();
            if (st->w - sx > MARGIN) {
                sy = 0;
                ey = st->w - 1 - sx; if (ey > st->h - 1) ey = st->h - 1;
                ex = ey + sx; if (ex > st->w - 1) ex = st->w - 1;
                m = ex - sx; n = ey - sy;
                line->len = int(sqrt((double)(m * m + n * n)));
                line->sx = sx; line->sy = sy; line->dx = dx; line->dy = dy;
                st->phase = 0; st->i++;
                return 1;
            }
            st->end1 = 1;
        }

        // Both zones exhausted at current i
        if (st->end0 && st->end1) {
            st->done = true;
            return 0;
        }
        st->i++;
        st->phase = 0;
    }

    st->done = true;
    return 0;
}

int do_isliicon_locating(IMAGE* image,
    int* x1, int* y1, int* x2, int* y2, double* frame_size)
{
    islii_reset_bs_confidence();
    ISLII_LOGI("[locate] ====== START image=%dx%d ======", image->w, image->h);

    //P2 空帧预检查：稀疏采样判断图像是否完全没有暗结构，若是则跳过全扫描
    {
        int min_v = 255, max_v = 0;
        int step = 10;
        long sum = 0, cnt = 0;
        for (int y = MIN_EDGE; y < image->h - MIN_EDGE; y += step) {
            unsigned char* p = image->pixel + y * image->bpl;
            for (int x = MIN_EDGE; x < image->w - MIN_EDGE; x += step) {
                int v = p[x];
                if (v < min_v) min_v = v;
                if (v > max_v) max_v = v;
                sum += v; cnt++;
            }
        }
        if (cnt > 0 && (min_v > 230 || (max_v - min_v) < 15)) {
            ISLII_LOGI("[locate] pre-check: image too uniform (min=%d max=%d), skip locate", min_v, max_v);
            return 0;
        }
    }
    int ret = 0;

    ret = do_horizontal_locating(image, x1, y1, x2, y2, frame_size);
    if (ret) {
        return ret;
    }

    ret = do_vertical_locating(image, x1, y1, x2, y2, frame_size);
    if (ret) {
        return ret;
    }

    //斜线扫描 — 延迟生成：逐条生成、逐条扫描，命中即停止
    {
        ISLII_LOGI("[locate] skew scan start (45°)");
        SkewLineGenState state;
        SKEW_LINE line;
        int skew_count = 0;
        init_skew_line_gen(&state, image->w, image->h, false); //45°
        unsigned char* wave = g_pool ? g_pool->skew_wave_buf : 0;
        int wave_cap = g_pool ? DecoderMemoryPool::MAX_IMAGE_DIM * 2 : 0;
        while (next_skew_line(&state, &line)) {
            skew_count++;
            if (!g_pool && line.len > wave_cap) {
                delete[] wave;
                wave = new unsigned char[(size_t)line.len];
                wave_cap = line.len;
            }
            do_skew_scan(image, &line, wave);
            int a = 0, b = 0;
            if (locate_in_line(wave, line.len, &a, &b, frame_size)) {
                *x1 = int(line.sx + line.dx * a + 0.5);
                *y1 = int(line.sy + line.dy * a + 0.5);
                *x2 = int(line.sx + line.dx * b + 0.5);
                *y2 = int(line.sy + line.dy * b + 0.5);
                ISLII_LOGI("[locate] skew(45°) MATCH: line#%d box=(%d,%d)-(%d,%d) frame_size=%.1f",
                           skew_count, *x1, *y1, *x2, *y2, *frame_size);
                ret = 1;
                break;
            }
        }
        if (!ret) ISLII_LOGD("[locate] skew(45°): no match after %d lines", skew_count);
        if (!g_pool) delete[] wave;
        if (ret) return ret;
    }

    {
        ISLII_LOGI("[locate] skew scan start (135°)");
        SkewLineGenState state;
        SKEW_LINE line;
        int skew_count = 0;
        init_skew_line_gen(&state, image->w, image->h, true); //135°
        unsigned char* wave = g_pool ? g_pool->skew_wave_buf : 0;
        int wave_cap = g_pool ? DecoderMemoryPool::MAX_IMAGE_DIM * 2 : 0;
        while (next_skew_line(&state, &line)) {
            skew_count++;
            if (!g_pool && line.len > wave_cap) {
                delete[] wave;
                wave = new unsigned char[(size_t)line.len];
                wave_cap = line.len;
            }
            do_skew_scan(image, &line, wave);
            int a = 0, b = 0;
            if (locate_in_line(wave, line.len, &a, &b, frame_size)) {
                *x1 = int(line.sx + line.dx * a + 0.5);
                *y1 = int(line.sy + line.dy * a + 0.5);
                *x2 = int(line.sx + line.dx * b + 0.5);
                *y2 = int(line.sy + line.dy * b + 0.5);
                ISLII_LOGI("[locate] skew(135°) MATCH: line#%d box=(%d,%d)-(%d,%d) frame_size=%.1f",
                           skew_count, *x1, *y1, *x2, *y2, *frame_size);
                ret = 1;
                break;
            }
        }
        if (!ret) ISLII_LOGD("[locate] skew(135°): no match after %d lines", skew_count);
        if (!g_pool) delete[] wave;
        if (ret) return ret;
    }

    ISLII_LOGE("[locate] ====== FAILED: no ISLI icon found in image ======");
    return 0;
}

