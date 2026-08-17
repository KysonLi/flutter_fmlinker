#include "Common.h"
#include "ISLILineDecoder.h"
#include "BSPatternMatch.h"
#include "CurveFit.h"
#include "CurveSampler.h"
#include "Filter.h"
#include "Wave2Bits.h"
#include "bch.h"
#include "BchHelper.h"
#include "GaussianBinarization.h"
#include "BarLocator.h"
#include "LineCodeSpec.h"
#include "buffer.h"
#include <algorithm>
#include <assert.h>
#include <chrono>
#include <math.h>
#include <string.h>
#include <cstdio>
#if defined(__aarch64__)
#include <arm_neon.h>
#endif

bch_control*   __bch_ctrl127 = 0;
bch_control*   __bch_ctrl64 = 0;


int isli_line_decoder_init()
{
    if (0 == __bch_ctrl127) {
        __bch_ctrl127 = init_bch(7, 7, 0);
        __bch_ctrl64 = init_bch(6, 4, 0);

        return 1;
    }
    else {
        return 0;
    }
}

int isli_line_decoder_uninit()
{
    if (__bch_ctrl127) {
        free_bch(__bch_ctrl127);
        __bch_ctrl127 = 0;

        free_bch(__bch_ctrl64);
        __bch_ctrl64 = 0;

        return 1;
    }
    else {
        return 0;
    }
}

static void convert_coord_and_sort(std::vector<point_t> &pat_vec, std::vector<double> &px,
    std::vector<double> &py)
{
    px.clear();
    py.clear();
    px.reserve(pat_vec.size());
    py.reserve(pat_vec.size());

    std::sort(pat_vec.begin(), pat_vec.end(),
        [](const point_t & a, const point_t & b) -> bool
    {
        return a.x < b.x;
    });

    for (auto &pt : pat_vec)
    {
        px.push_back(pt.x);
        py.push_back(pt.y);
    }
}

static const int SPAN_NUM = 71;
static const int SAPMLES_PER_SPAN = 9;

static void fit_and_sample_one_curve(TImage *image, std::vector<point_t> &bar_vec, tl::buffer<unsigned char> &wave,
    const char *graph_name)
{
    UNREFERENCED_PARAMETER(graph_name);

    std::vector<double> px; // px[0] py[0]是偏移
    std::vector<double> py;
    double cosa = 0; // 旋转曲线的角度 
    double sina = 0;

    convert_coord_and_sort(bar_vec, px, py);

    double c_bar1[4];
    ild_curve_fit_with_coord_normalization(&px[0], &py[0], px.size(), c_bar1, &cosa, &sina);


    double span_len[SPAN_NUM];
    double shift_x = px[0];
    double shift_y = py[0];
    double span_x[SPAN_NUM + 1];
    double span_y[SPAN_NUM + 1];
    double x_len = (px[px.size() - 1] - px[0]) * cosa - (py[py.size() - 1] - py[0]) * sina;

    ild_split_curve_into_span(c_bar1, 0, x_len, shift_x, shift_y, cosa, sina, span_len, span_x, span_y, SPAN_NUM);
    for (int s = 0; s < SPAN_NUM; s++) {
        //qDebug() << span_len[s];
#if 0
        __canvas.DrawLine("source", "color=0xff",
            (short)(span_x[s] + 0.5), (short)(span_y[s] + 0.5),
            (short)(span_x[s + 1] + 0.5), (short)(span_y[s + 1] + 0.5));
#endif
    }

    wave.resize(SAPMLES_PER_SPAN * SPAN_NUM);
    int len = (int)wave.size();
    ild_sample_one_curve(image, span_len, span_x, span_y, SPAN_NUM, &len, &wave[0]);
    if (len <= 0)
        return;
    wave.resize(len);
    
    //DrawWave(1, "color=0xff0000", graph_name, &wave[0], len);


    //对波形做低通滤波，然后定位同步位
    //以同步位附近的波形平均值作为阈值对波形二值化，采样波形得到bit
    //unsigned char filtered[SAPMLES_PER_SPAN * SPAN_NUM];
    tl::buffer<unsigned char> filtered;
    filtered.resize(SAPMLES_PER_SPAN * SPAN_NUM);
    ild_low_pass_filter(&wave[0], len, &filtered[0]);

    wave.swap(filtered);
}

static void fit_and_sample_one_curve2(
    TImage *image, 
    std::vector<point_t> &bar_vec,
    double width,
    tl::buffer<unsigned char> &wave,
    const char *graph_name)
{
    UNREFERENCED_PARAMETER(graph_name);

    std::vector<double> px; // px[0] py[0]是偏移
    std::vector<double> py;
    double cosa = 0; // 旋转曲线的角度 
    double sina = 0;

    convert_coord_and_sort(bar_vec, px, py);

    double c_bar1[4];
    ild_curve_fit_with_coord_normalization(&px[0], &py[0], px.size(), c_bar1, &cosa, &sina);
    //double width = px[px.size() - 1] - px[0];

    tl::buffer<double> span_len;
    double shift_x = px[0];
    double shift_y = py[0];
    tl::buffer<double> span_x;
    tl::buffer<double> span_y;
    double x_len = (px[px.size() - 1] - px[0]) * cosa - (py[py.size() - 1] - py[0]) * sina;

    int span_num = x_len * 6 * ILD_CYCLE_CODE_ASPECT_RATIO / width; // 根据宽度(距离摄像头的远近)来决定采样数
    span_len.resize(span_num);
    span_x.resize(span_num + 1);
    span_y.resize(span_num + 1);

    ild_split_curve_into_span2(c_bar1, 0, x_len, shift_x, shift_y, cosa, sina, span_len, span_x, span_y, span_num);
    for (int s = 0; s < span_num; s++) {
        //qDebug() << span_len[s];
#if 0
        __canvas.DrawLine("source", "color=0xff",
            (short)(span_x[s] + 0.5), (short)(span_y[s] + 0.5),
            (short)(span_x[s + 1] + 0.5), (short)(span_y[s + 1] + 0.5));
#endif
    }

    wave.resize(SAPMLES_PER_SPAN * span_num);
    int len = (int)wave.size();
    ild_sample_one_curve2(image, span_len, span_x, span_y, span_num, &len, &wave[0]);
    if (len <= 0)
        return;
    wave.resize(len);

    //DrawWave(1, "color=0xff0000", graph_name, &wave[0], len);


    //对波形做低通滤波，然后定位同步位
    //以同步位附近的波形平均值作为阈值对波形二值化，采样波形得到bit
    //unsigned char filtered[SAPMLES_PER_SPAN * span_num];
    tl::buffer<unsigned char> filtered;
    filtered.resize(SAPMLES_PER_SPAN * span_num);
    ild_low_pass_filter(&wave[0], len, &filtered[0]);

    wave.swap(filtered);
}

static double point_distance(point_t &a, point_t &b)
{
    double dx = b.x - a.x;
    double dy = b.y - a.y;
    return sqrt(dx * dx + dy * dy);
}

static double get_avg_width(std::vector<point_t> &pat_vec)
{
    double sum = 0.0;
    for (auto &pat : pat_vec)
    {
        sum += pat.width;
    }
    return sum / pat_vec.size();
}

struct FindSyncParam {
    int pos1;
    int pos2;
    int distance;
};

void get_sync_combinations(std::vector<int> &peak1, std::vector<int> &peak2,
    std::vector<std::vector<int>> &output, bool bit_112)
{
    std::vector<FindSyncParam> params;
    std::vector<int> sync_pos;
    for (auto v1 : peak1)
    {
        for (auto v2 : peak2)
        {
            if (abs(v1 - v2) < 9)
            {
                int pos = (v1 + v2) / 2;
                if (bit_112)
                {
                    if (pos > 27 && pos < 639 - 27) // is not the head or tail sync position.
                        sync_pos.push_back(pos);
                }
                else
                {
                    sync_pos.push_back(pos);
                }
            }
        }
    }
    std::sort(sync_pos.begin(), sync_pos.end());

    std::vector<int> combination;
    combination.resize(3);

    for (size_t a1 = 0; a1 < sync_pos.size(); a1++)
    {
        for (size_t a2 = a1 + 1; a2 < sync_pos.size(); a2++)
        {
            for (size_t a3 = a2 + 1; a3 < sync_pos.size(); a3++)
            {
                //ILDLOG("%d %d %d", a1, a2, a3);
                combination[0] = sync_pos[a1];
                combination[1] = sync_pos[a2];
                combination[2] = sync_pos[a3];
                output.push_back(combination); // TODO use std::move to save allocations
            }
        }
    }
    // TODO: randomize the combinations.
}

// 2× 垂直放大：每两行之间插入一行（均值）。行主序 + NEON(vrhaddq_u8=(a+b+1)>>1)。
static void interpolation_image(TImage &input, TImage &output)
{
    const int w = input.w, h = input.h;
    const int bpl_i = input.bpl, bpl_o = output.bpl;
    const unsigned char* in = input.pixel;
    unsigned char* out = output.pixel;

    for (int y = 0; y + 1 < h; ++y) {
        const unsigned char* r0 = in + (size_t)y * bpl_i;
        const unsigned char* r1 = in + (size_t)(y + 1) * bpl_i;
        unsigned char* o0 = out + (size_t)(y * 2) * bpl_o;       // 偶行 = r0（拷贝）
        unsigned char* o1 = out + (size_t)(y * 2 + 1) * bpl_o;   // 奇行 = (r0+r1+1)/2
        memcpy(o0, r0, w);
        int x = 0;
#if defined(__aarch64__)
        for (; x + 15 < w; x += 16) {
            uint8x16_t a = vld1q_u8(r0 + x);
            uint8x16_t b = vld1q_u8(r1 + x);
            vst1q_u8(o1 + x, vrhaddq_u8(a, b));   // (a+b+1)>>1，与原 (a+b+1)/2 等价
        }
#endif
        for (; x < w; ++x)
            o1[x] = (unsigned char)((r0[x] + r1[x] + 1) >> 1);
    }
    // 最后一行：两行输出都 = 最后一行输入
    {
        const unsigned char* r0 = in + (size_t)(h - 1) * bpl_i;
        unsigned char* o0 = out + (size_t)((h - 1) * 2) * bpl_o;
        unsigned char* o1 = out + (size_t)((h - 1) * 2 + 1) * bpl_o;
        memcpy(o0, r0, w);
        memcpy(o1, r0, w);
    }
}

static int decode_waves(tl::buffer<Byte>& wave1, tl::buffer<Byte>& wave2, char isli_code[20], 
    unsigned char corrected_bits[ILD_BIT_COUNT])
{
    std::vector<int> peak1;
    std::vector<int> peak2;

    std::vector<int> valley1;
    std::vector<int> valley2;
    ild_find_peak_valley(wave1, peak1, valley1, "Curve");
    ild_find_peak_valley(wave2, peak2, valley2, "Curve2");
    ILD_LOGD("decode_waves(112): peak1=%zu valley1=%zu peak2=%zu valley2=%zu",
             peak1.size(), valley1.size(), peak2.size(), valley2.size());

    if (peak1.size() == 0 || valley1.size() == 0 || peak2.size() == 0 || valley2.size() == 0) {
        ILD_LOGD("decode_waves(112): empty peak/valley -> abort");
        return 0;
    }

    std::vector<std::vector<int>> combinations;
    get_sync_combinations(peak1, peak2, combinations, true);
    ILD_LOGD("decode_waves(112): sync combinations=%zu", combinations.size());
    int head1 = 0;
    int tail1 = 0;
    int head2 = 0;
    int tail2 = 0;
    ild_trim_head_tail(wave1, peak1, valley1, IldOrientation::SyncOnLeft, head1, tail1, "Curve");
    ild_trim_head_tail(wave2, peak2, valley2, IldOrientation::NoSync, head2, tail2, "Curve2");

    tl::buffer<Byte> bits;
    bits.reserve(ILD_BIT_COUNT2);

    int decode_count = 0;

    for (auto &sync : combinations)
    {
        bits.clear();
        int ret1 = ild_wave2bits112(wave1, bits, head1, tail1, sync, "Curve");
        int ret2 = ild_wave2bits112(wave2, bits, head2, tail2, sync, "Curve2");

        if (ret1 && ret2)
        {
            decode_count++;
            if (ild_bits_decode2(bits.data(), isli_code, corrected_bits)) {
                return 1;
            }
            if (decode_count > 300)
            {
                ILDLOG("old decode_count: %d", decode_count);
                break;  // DR-2: 主路径未解码时落入 pos-retry 兜底（不再直接 return 0）
            }
        }
    }

    ild_trim_head_tail(wave1, peak1, valley1, IldOrientation::NoSync, head1, tail1, "Curve3");
    ild_trim_head_tail(wave2, peak2, valley2, IldOrientation::SyncOnRight, head2, tail2, "Curve4");

    for (auto &sync : combinations)
    {
        bits.clear();
        int ret1 = ild_wave2bits112(wave1, bits, head1, tail1, sync, "Curve3");
        int ret2 = ild_wave2bits112(wave2, bits, head2, tail2, sync, "Curve4");

        if (ret1 && ret2)
        {
            decode_count++;
            if (ild_bits_decode_inverted(bits.data(), isli_code, corrected_bits)) {
                return 1;
            }
            if (decode_count > 300)
            {
                ILDLOG("old decode_count: %d", decode_count);
                break;  // DR-2: 主路径未解码时落入 pos-retry 兜底（不再直接 return 0）
            }
        }
    }
    // ── pos-retry（DR-2）：仅在 112-bit 主路径(Δ=0)未解码时执行（纯增量兜底）。
    // 对每个 sync 组合作整体 ±1/±2 平移后再采样，救援 min-err=7（刚过 cap=6）的边缘帧——
    // 真实同步中心相对整数中点 (v1+v2)/2 偏移 ~1 sample 时，采样点漂移到 bit-cell 边缘
    // 致少量 bit 翻转；平移栅格可把漂移 bit 拉回。主路径(Δ=0)逐字节不变 → 已解码帧 0 回归；
    // FP 由 BCH cap≤6 + 再编码守卫兜底（均不变）→ 0 FP。
    {
        int h1L, t1L, h2L, t2L;  // 极性1 trim：SyncOnLeft / NoSync
        ild_trim_head_tail(wave1, peak1, valley1, IldOrientation::SyncOnLeft, h1L, t1L, "CurveJ");
        ild_trim_head_tail(wave2, peak2, valley2, IldOrientation::NoSync,     h2L, t2L, "Curve2J");
        int h1R, t1R, h2R, t2R;  // 极性2 trim：NoSync / SyncOnRight
        ild_trim_head_tail(wave1, peak1, valley1, IldOrientation::NoSync,      h1R, t1R, "CurveJ");
        ild_trim_head_tail(wave2, peak2, valley2, IldOrientation::SyncOnRight, h2R, t2R, "Curve2J");
        std::vector<int> syncBuf(3);
        static const int JITTER[] = { 1, -1, 2, -2 };
        bool cap_hit = false;  // DR-4: 触顶后跳出双循环，落入 mean-retry（不再 return 0）
        for (int delta : JITTER) {
            if (cap_hit) break;
            for (auto &base : combinations) {
                syncBuf[0] = base[0] + delta;
                syncBuf[1] = base[1] + delta;
                syncBuf[2] = base[2] + delta;
                // 极性1（同主路径 pass-1）
                bits.clear();
                if (ild_wave2bits112(wave1, bits, h1L, t1L, syncBuf, "CurveJ") &&
                    ild_wave2bits112(wave2, bits, h2L, t2L, syncBuf, "Curve2J")) {
                    ++decode_count;
                    if (ild_bits_decode2(bits.data(), isli_code, corrected_bits)) {
                        ILD_LOGI("decode OK via decode_waves(112) pos-retry delta=%d code=%s", delta, isli_code);
                        return 1;
                    }
                    if (decode_count > 450) { ILDLOG("jitter decode_count: %d (cap->mean-retry)", decode_count); cap_hit = true; break; }
                }
                // 极性2（同主路径 pass-2，反转）
                bits.clear();
                if (ild_wave2bits112(wave1, bits, h1R, t1R, syncBuf, "CurveJ") &&
                    ild_wave2bits112(wave2, bits, h2R, t2R, syncBuf, "Curve2J")) {
                    ++decode_count;
                    if (ild_bits_decode_inverted(bits.data(), isli_code, corrected_bits)) {
                        ILD_LOGI("decode OK via decode_waves(112) pos-retry(inv) delta=%d code=%s", delta, isli_code);
                        return 1;
                    }
                    if (decode_count > 450) { ILDLOG("jitter decode_count: %d (cap->mean-retry)", decode_count); cap_hit = true; break; }
                }
            }
        }
    }

    // ── mean-threshold retry（DR-4）：主路径(midpoint 阈值)+pos-retry 未解码时，
    // 用 window-mean 阈值重采所有 sync 组合。救援“min/max 中点被离群像素拉偏、
    // bit 翻转”的帧（诊断 ceiling A/B：midpoint→mean +38 GT 0FP）。纯增量（主路径
    // 逐字节不变 → 已解码帧 0 回归）；FP 由 BCH cap≤6 + 再编码守卫兜底（均不变）。
    {
        int h1L, t1L, h2L, t2L;
        ild_trim_head_tail(wave1, peak1, valley1, IldOrientation::SyncOnLeft, h1L, t1L, "CurveM");
        ild_trim_head_tail(wave2, peak2, valley2, IldOrientation::NoSync,     h2L, t2L, "Curve2M");
        int h1R, t1R, h2R, t2R;
        ild_trim_head_tail(wave1, peak1, valley1, IldOrientation::NoSync,      h1R, t1R, "CurveM");
        ild_trim_head_tail(wave2, peak2, valley2, IldOrientation::SyncOnRight, h2R, t2R, "Curve2M");
        const bool MEAN = true;
        for (auto &sync : combinations) {
            bits.clear();
            if (ild_wave2bits112(wave1, bits, h1L, t1L, sync, "CurveM", MEAN) &&
                ild_wave2bits112(wave2, bits, h2L, t2L, sync, "Curve2M", MEAN)) {
                ++decode_count;
                if (ild_bits_decode2(bits.data(), isli_code, corrected_bits)) {
                    ILD_LOGI("decode OK via decode_waves(112) mean-thr code=%s", isli_code);
                    return 1;
                }
                if (decode_count > 3000) { ILDLOG("mean decode_count: %d", decode_count); return 0; }
            }
            bits.clear();
            if (ild_wave2bits112(wave1, bits, h1R, t1R, sync, "CurveM", MEAN) &&
                ild_wave2bits112(wave2, bits, h2R, t2R, sync, "Curve2M", MEAN)) {
                ++decode_count;
                if (ild_bits_decode_inverted(bits.data(), isli_code, corrected_bits)) {
                    ILD_LOGI("decode OK via decode_waves(112) mean-thr(inv) code=%s", isli_code);
                    return 1;
                }
                if (decode_count > 3000) { ILDLOG("mean decode_count: %d", decode_count); return 0; }
            }
        }
    }

    ILDLOG("old decode_count: %d", decode_count);
    return 0;
}

static unsigned char test_vector[] = {
    0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0xFF, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0xFF, 0x00,
};

static int decode_waves2(tl::buffer<Byte>& wave1, tl::buffer<Byte>& wave2, char isli_code[20],
    double avg_width, unsigned char corrected_bits[ILD_BIT_COUNT])
{
    std::vector<int> peak1;
    std::vector<int> peak2;

    std::vector<int> valley1;
    std::vector<int> valley2;
    ild_find_peak_valley(wave1, peak1, valley1, "Curve");
    ild_find_peak_valley(wave2, peak2, valley2, "Curve2");
    ILD_LOGD("decode_waves2(64): peak1=%zu valley1=%zu peak2=%zu valley2=%zu",
             peak1.size(), valley1.size(), peak2.size(), valley2.size());

    if (peak1.size() == 0 || valley1.size() == 0 || peak2.size() == 0 || valley2.size() == 0) {
        ILD_LOGD("decode_waves2(64): empty peak/valley -> abort");
        return 0;
    }

    std::vector<std::vector<int>> combinations;
    get_sync_combinations(peak1, peak2, combinations, false);
    ILD_LOGD("decode_waves2(64): sync combinations=%zu", combinations.size());

    tl::buffer<Byte> bits;
    bits.reserve(ILD_BIT_COUNT2);

    int decode_count = 0;

    for (auto &sync : combinations)
    {
        bits.clear();
        int ret1 = ild_wave2bits64(wave1, bits, sync, avg_width, "Curve");
        int ret2 = ild_wave2bits64(wave2, bits, sync, avg_width, "Curve2");

        if (ret1 && ret2)
        {
            // TODO compare with result of svg writer
            assert(bits.size() == 64);
            //assert(memcmp(bits.data(), test_vector, sizeof(test_vector)) != 0);
            decode_count++;
            if (ild_bits_decode_short_chain(bits.data(), isli_code, corrected_bits)) {
                return 1;
            }
            if (decode_count > 150)
            {
                ILDLOG("new decode_count: %d", decode_count);
                return 0;
            }
        }
    }
    ILDLOG("new decode_count: %d", decode_count);
    return 0;
}

// Clean barcode direct-sampling decoder.
// Bypasses the anti-copy pattern-matching bar locator and wave analysis.
// Instead, uses the polynomial curve fit to sample the binarized image
// at 71 equally-spaced x positions along each data row.
// Works on both anti-copy-textured and clean-rendered barcodes.
// Clean barcode direct-sampling (flat geometry).
// row0Y and row1Y are the row center positions (in image coordinates).
// If row1Y <= 0, defaults to H/6 and 5*H/6 are used.
static int decode_clean_flat_ex(TImage* gray_img, int row0Y, int row1Y,
    char isli_code[20], unsigned char corrected_bits[ILD_BIT_COUNT])
{
    int W = gray_img->w, H = gray_img->h;
    if (W < 71 || H < 10) return 0;
    double bw = (double)W / 71.0;
    if (bw < 1.5 || bw > 200.0) return 0;

    // Default to H/6 and 5*H/6 if not provided.
    if (row1Y <= 0) {
        row0Y = (int)(H / 6.0 + 0.5);
        row1Y = (int)(5.0 * H / 6.0 + 0.5);
    }

    unsigned char raw142[142];
    memset(raw142, 0, sizeof(raw142));
    for (int b = 0; b < 71; ++b) {
        int ix = (int)((b + 0.5) * bw + 0.5);
        if (ix < 0) ix = 0; if (ix >= W) ix = W - 1;

        int dk0 = 0;
        for (int dy = -1; dy <= 1; ++dy) {
            int iy = row0Y + dy;
            if (iy < 0) iy = 0; if (iy >= H) iy = H - 1;
            if (gray_img->pixel[(size_t)iy * gray_img->bpl + ix] < 128) ++dk0;
        }
        if (dk0 >= 2) raw142[b] = 1;

        int dk1 = 0;
        for (int dy = -1; dy <= 1; ++dy) {
            int iy = row1Y + dy;
            if (iy < 0) iy = 0; if (iy >= H) iy = H - 1;
            if (gray_img->pixel[(size_t)iy * gray_img->bpl + ix] < 128) ++dk1;
        }
        if (dk1 >= 2) raw142[71 + b] = 1;
    }

    unsigned char data112[ILD_BIT_COUNT];
    memset(data112, 0, sizeof(data112));
    {
        const std::array<int, linecode::kTotalData>& lut = linecode::deinterleaveLut();
        for (int i = 0; i < linecode::kTotalData; ++i)
            data112[i] = raw142[lut[i]];
    }

    if (ild_bits_decode2(data112, isli_code, corrected_bits)) return 1;
    if (ild_bits_decode_inverted(data112, isli_code, corrected_bits)) return 1;
    return 0;
}

static int decode_clean_flat(TImage* gray_img,
    char isli_code[20], unsigned char corrected_bits[ILD_BIT_COUNT])
{
    return decode_clean_flat_ex(gray_img, -1, -1, isli_code, corrected_bits);
}

// Shared pre-crop: subsampled row projection → two-band detection → vertical crop.
// Detects the two dark bands (barcode data rows) and crops to their vicinity with margin.
// Returns cropY0 and cropH (output parameters). On near-uniform images where the second
// band can't be found, cropY0=0 and cropH=H (no cropping).
// Tilt-adaptive pre-crop: estimates tilt via top/bottom row cross-correlation,
// computes sheared projection for sharp band detection, returns tiltD for deskew.
static void pre_crop_vertical(TImage* image, int& cropY0, int& cropH, int& tiltD)
{
    int W = image->w, H = image->h;
    cropY0 = 0; cropH = H; tiltD = 0;

    // --- Estimate tilt via cross-correlation of top/bottom row profiles ---
    int nTop = H < 20 ? H/2 : 10;
    int profLen = W/4;
    tl::buffer<double> topProfile; topProfile.resize(profLen);
    tl::buffer<double> botProfile; botProfile.resize(profLen);
    for (int xi = 0; xi < W/4; ++xi) {
        int x = xi * 4;
        double st = 0, sb = 0;
        for (int dy = 0; dy < nTop; ++dy) {
            st += image->pixel[static_cast<size_t>(dy) * image->bpl + x];
            sb += image->pixel[static_cast<size_t>(H-1-dy) * image->bpl + x];
        }
        topProfile[xi] = st / nTop; botProfile[xi] = sb / nTop;
    }
    int N = profLen, bestShift = 0;
    double bestCorr = -1e18;
    int searchRange = W / 20;
    for (int shift = -searchRange; shift <= searchRange; ++shift) {
        double corr = 0; int cnt = 0;
        for (int i = 0; i < N; ++i) {
            int j = i + shift;
            if (j >= 0 && j < N) { corr += topProfile[i] * botProfile[j]; ++cnt; }
        }
        if (cnt > 0 && corr > bestCorr) { bestCorr = corr; bestShift = shift; }
    }
    tiltD = bestShift * 4;

    // --- Tilt-compensated row projection ---
    tl::buffer<double> rm; rm.resize(H);
    if (abs(tiltD) < 2) {
        for (int y = 0; y < H; ++y) {
            long long s = 0; int n = 0;
            const unsigned char* r = image->pixel + static_cast<size_t>(y) * image->bpl;
            for (int x = 0; x < W; x += 4) { s += r[x]; ++n; }
            rm[y] = static_cast<double>(s) / n;
        }
    } else {
        double invH = 1.0 / H;
        for (int y = 0; y < H; ++y) {
            double ox = (double)y * invH * tiltD;
            int oxi = (int)ox; double frac = ox - oxi;
            long long s = 0; int n = 0;
            const unsigned char* row = image->pixel + static_cast<size_t>(y) * image->bpl;
            for (int xi = 0; xi < W/4; ++xi) {
                int x = xi * 4 + oxi;
                double v = row[x];
                if (frac != 0.0 && x + 1 < W)
                    v = row[x] * (1.0 - frac) + row[x+1] * frac;
                s += (long long)v; ++n;
            }
            rm[y] = static_cast<double>(s) / n;
        }
    }

    // --- Find two darkest bands ---
    double rmin = rm[0], rmax = rm[0];
    for (int y = 1; y < H; ++y) { if (rm[y] < rmin) rmin = rm[y]; if (rm[y] > rmax) rmax = rm[y]; }
    double bg = rmin + (rmax - rmin) * 0.85;
    double accept = bg - 0.15 * (bg - rmin);
    int ya = 0; for (int y = 1; y < H; ++y) if (rm[y] < rm[ya]) ya = y;
    int b0 = ya, b1 = ya;
    while (b0 > 0 && rm[b0-1] < accept) --b0;
    while (b1 < H-1 && rm[b1+1] < accept) ++b1;
    int yb = -1; double pb = 1e18;
    for (int y = 0; y < H; ++y) {
        if (y >= b0 && y <= b1) continue;
        if (rm[y] < pb && rm[y] < accept) { pb = rm[y]; yb = y; }
    }
    if (yb >= 0) {
        int d0 = yb, d1 = yb;
        while (d0 > 0 && rm[d0-1] < accept) --d0;
        while (d1 < H-1 && rm[d1+1] < accept) ++d1;
        int lo = b0 < d0 ? b0 : d0, hi = b1 > d1 ? b1 : d1;
        int margin = (hi - lo) / 4 + 3;
        cropY0 = lo - margin > 0 ? lo - margin : 0;
        int cy1 = hi + margin < H-1 ? hi + margin : H-1;
        cropH = cy1 - cropY0 + 1;
    }
}

// 在已二值化的 bin_img（及灰度 enlarged）上跑“定位 -> 曲线拟合 -> 单条定位 -> 采样 -> 波形解码”
// 完整下游流水线。enlarged=2× 放大灰度图（采样用），bin_img=与之同尺寸的二值图，
// src=放大前的裁剪灰度图。成功返回 1 并填充结果。
static int decode_from_binary(TImage *enlarged, TImage *bin_img, TImage *src,
    char isli_code[20], short feax[2], short feay[2],
    unsigned char corrected_bits[ILD_BIT_COUNT])
{
    // 清空上一次（Otsu/Gaussian）尝试可能残留的半解码结果，保证 FAILED 日志干净。
    memset(isli_code, 0, 20);

    std::vector<point_t> pt_vec;
    point_t center;
    { auto _t0 = std::chrono::steady_clock::now();
    ild_do_vertical_locating(bin_img, pt_vec, center);
    auto _t1 = std::chrono::steady_clock::now();
    auto _ms = std::chrono::duration_cast<std::chrono::microseconds>(_t1 - _t0).count();
    ILD_LOGI("stage(vertical_locating) took %lldus", (long long)_ms); }
    ILD_LOGD("vertical_locating: pt_vec=%zu center=(%g,%g)", pt_vec.size(), center.x, center.y);
    if (pt_vec.size() < 7) {
        ILD_LOGW("rejected: vertical locating pt_vec=%zu (<7)", pt_vec.size());
        return 0;
    }

    std::vector<double> px;
    std::vector<double> py;
    convert_coord_and_sort(pt_vec, px, py);

    double span = point_distance(pt_vec[0], pt_vec[pt_vec.size() - 1]);
    if (span < 64)
    {
        ILD_LOGW("rejected: feature point_distance=%.1f (<64)", span);
        return 0;
    }
    feax[0] = px[0];
    feay[0] = py[0];
    feax[1] = px[px.size() - 1];
    feay[1] = py[py.size() - 1];

    double avg_width = get_avg_width(pt_vec);
    ILD_LOGD("avg_width=%.2f span=%.1f fea=(%d,%d)-(%d,%d)", avg_width, span, feax[0], feay[0], feax[1], feay[1]);

    double coefficient[4];
    ild_fit_curve(&px[0], &py[0], (int)px.size(), coefficient);
    ILD_LOGD("fit_curve coef=[%g %g %g %g]", coefficient[0], coefficient[1], coefficient[2], coefficient[3]);

    std::vector<point_t> bar1_vec;
    std::vector<point_t> bar2_vec;
    bar1_vec.reserve(500);
    bar2_vec.reserve(500);
    { auto _t0 = std::chrono::steady_clock::now();
    ild_locate_single_bar(enlarged, bin_img, coefficient, center, avg_width * 0.8, bar1_vec, bar2_vec);
    auto _t1 = std::chrono::steady_clock::now();
    auto _ms = std::chrono::duration_cast<std::chrono::microseconds>(_t1 - _t0).count();
    ILD_LOGI("stage(bar_locating) took %lldus", (long long)_ms); }
    ILD_LOGD("locate_single_bar: bar1=%zu bar2=%zu", bar1_vec.size(), bar2_vec.size());

    if (bar1_vec.size() < 10 || bar2_vec.size() < 10)
    {
        ILD_LOGW("rejected: locate_single_bar bar1=%zu bar2=%zu (<10)", bar1_vec.size(), bar2_vec.size());
        return 0;
    }
    tl::buffer<unsigned char> wave1; wave1.reserve(900);
    tl::buffer<unsigned char> wave2; wave2.reserve(900);

    { auto _t0 = std::chrono::steady_clock::now();
    fit_and_sample_one_curve(enlarged, bar1_vec, wave1, "Curve-old");
    fit_and_sample_one_curve(enlarged, bar2_vec, wave2, "Curve2-old");
    auto _t1 = std::chrono::steady_clock::now();
    auto _ms = std::chrono::duration_cast<std::chrono::microseconds>(_t1 - _t0).count();
    ILD_LOGI("stage(wave_sampling) took %lldus", (long long)_ms); }
    ILD_LOGD("sample(curve-old): wave1=%zu wave2=%zu", wave1.size(), wave2.size());

    if (wave1.size() == 0 || wave2.size() == 0)
    {
        ILD_LOGW("fit_and_sample_one_curve empty wave1=%zu wave2=%zu", wave1.size(), wave2.size());
        return 0;
    }

    if (decode_waves(wave1, wave2, isli_code, corrected_bits))
    {
        ILD_LOGI("decode OK via decode_waves(112-bit) code=%s", isli_code);
        return 1;
    }
    ILD_LOGD("decode_waves(112-bit) miss -> try 64-bit path");

    wave1.clear(); wave2.clear();

    fit_and_sample_one_curve2(enlarged, bar1_vec, avg_width, wave1, "Curve");
    fit_and_sample_one_curve2(enlarged, bar2_vec, avg_width, wave2, "Curve2");
    ILD_LOGD("sample(curve2): wave1=%zu wave2=%zu", wave1.size(), wave2.size());
    if (wave1.size() == 0 || wave2.size() == 0)
    {
        ILD_LOGW("fit_and_sample_one_curve2 empty wave1=%zu wave2=%zu", wave1.size(), wave2.size());
        return 0;
    }

    if (decode_waves2(wave1, wave2, isli_code, avg_width, corrected_bits)) {
        ILD_LOGI("decode OK via decode_waves2(64-bit) code=%s", isli_code);
        return 1;
    }

    ILD_LOGD("decode_from_binary: all stages exhausted");

    return 0;
}

static int decode_landscape(TImage *image, char isli_code[20], short feax[2], short feay[2],
    int *is_blur, unsigned char corrected_bits[ILD_BIT_COUNT])
{
    // FFT 模糊检测已移除：它在 ROI 定位前对每帧开销 ~1.5ms 且过度拒绝可解码图
    // （误拒 HIT_00006/08/20）。真正的不可解码过滤由 ild_do_vertical_locating
    // （<7 个条码点即返回 0）与 BCH（≤5 错+再编码验证）兜底，无需 FFT 快通道。
    (void)is_blur;

    // clean_flat 门控：纹理码 0 命中却每帧跑全图。连续 miss>=8 后跳过，每 30 帧重试一次。
    static int s_clean_miss_streak = 0;
    static int s_frames_since_attempt = 0;
    ++s_frames_since_attempt;
    bool attempt_clean = (s_clean_miss_streak < 8) || (s_frames_since_attempt >= 30);
    if (attempt_clean) {
        s_frames_since_attempt = 0;
        bool ok;
        { auto _t0 = std::chrono::steady_clock::now();
        ok = decode_clean_flat(image, isli_code, corrected_bits) != 0;
        auto _ms = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - _t0).count();
        ILD_LOGI("stage(clean_flat) took %lldus", (long long)_ms); }
        if (ok) {
            s_clean_miss_streak = 0;
            ILD_LOGI("decode OK via clean_flat fast-path code=%s", isli_code);
            return 1;
        }
        ++s_clean_miss_streak;
        ILD_LOGD("clean_flat miss (streak=%d) -> full pipeline", s_clean_miss_streak);
    }

    // Pre-crop with tilt estimation.
    int cropY0 = 0, cropH = image->h, tiltD = 0;
    { auto _t0 = std::chrono::steady_clock::now();
    pre_crop_vertical(image, cropY0, cropH, tiltD);
    auto _ms = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - _t0).count();
    ILD_LOGI("stage(pre_crop) took %lldus", (long long)_ms); }
    ILD_LOGD("pre_crop: cropY0=%d cropH=%d tiltD=%d", cropY0, cropH, tiltD);

    // Deskew full image if tilted.
    TImage deskewed;
    TImage* workImg = image;
    auto _ds_t0 = std::chrono::steady_clock::now();
    if (abs(tiltD) >= 6) {
        deskewed.allocate(image->w, image->h);
        double invH = 1.0 / image->h;
        for (int y = 0; y < image->h; ++y) {
            double ox = -(double)y * invH * tiltD;
            int oxi = (int)ox; double frac = ox - oxi;
            unsigned char* dstRow = deskewed.pixel + (size_t)y * deskewed.bpl;
            const unsigned char* srcRow = image->pixel + (size_t)y * image->bpl;
            for (int x = 0; x < image->w; ++x) {
                int sx = x + oxi;
                double v = (sx >= 0 && sx < image->w) ? srcRow[sx] : 255.0;
                if (frac != 0.0 && sx+1 >= 0 && sx+1 < image->w)
                    v = v * (1.0 - frac) + srcRow[sx+1] * frac;
                if (v < 0) v = 0; if (v > 255) v = 255;
                dstRow[x] = (unsigned char)v;
            }
        }
        workImg = &deskewed;
        // Re-crop on deskewed image.
        pre_crop_vertical(workImg, cropY0, cropH, tiltD);
        ILD_LOGD("pre_crop(deskewed): cropY0=%d cropH=%d", cropY0, cropH);
    }
    { auto _ms = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - _ds_t0).count();
      ILD_LOGI("stage(deskew) took %lldus", (long long)_ms); }

    // Crop via shared-memory view (zero-copy). Instead of allocating and
    // memcpy-ing the cropped region, create a TImage view that points directly
    // into workImg's buffer with adjusted dimensions. No allocation, no copy.
    TImage banded;
    TImage* src = workImg;
    if (cropH < workImg->h) {
        // View into workImg: start at row cropY0, height cropH, same bpl.
        banded = TImage(workImg->pixel + (size_t)cropY0 * workImg->bpl,
                        workImg->w, cropH, workImg->bpl);
        src = &banded;
    }

    // Second-pass crop via sync-code matching (S1=101 template).
    // Also uses view-based crop — no allocation.
    auto _sc_t0 = std::chrono::steady_clock::now();
    if (src != workImg && src->h > 50) {
        int cw = src->w, ch = src->h;
        double bw2 = (double)cw / 71.0;
        if (bw2 >= 8.0 && bw2 <= 30.0) {
            int ibw = (int)bw2;
            int hw = ibw / 3; if (hw < 2) hw = 2; if (hw > 6) hw = 6;
            tl::buffer<double> syncRow;
            syncRow.resize(ch);
            double syncMax = 0;
            for (int y = 0; y < ch; ++y) {
                const unsigned char* r = src->pixel + (size_t)y * src->bpl;
                int v0=0, v1=0, v2=0, n0=0, n1=0, n2=0;
                for (int dx = -hw; dx <= hw; ++dx) {
                    int sx=dx;     if(sx>=0&&sx<cw){v0+=r[sx];n0++;}
                    sx=ibw+dx;     if(sx>=0&&sx<cw){v1+=r[sx];n1++;}
                    sx=2*ibw+dx;   if(sx>=0&&sx<cw){v2+=r[sx];n2++;}
                }
                if (n0<3||n1<3||n2<3) continue;
                v0/=n0; v1/=n1; v2/=n2;
                double sc = (128.0 - v0) + (v1 - 128.0) + (128.0 - v2);
                syncRow[y] = sc;
                if (sc > syncMax) syncMax = sc;
            }
            // Validation 1: high absolute threshold (max possible ≈ 384).
            if (syncMax < 100.0) goto skip_sync;

            // Validation 2: compute median score; top rows must be clear outliers.
            {
                tl::buffer<double> sorted;
                sorted.resize(ch);
                for (int i = 0; i < ch; ++i) sorted[i] = syncRow[i];
                std::sort(&sorted[0], &sorted[0] + ch);
                double median = sorted[ch/2];
                if (syncMax < median * 3.0) goto skip_sync;
            }

            // Validation 3: find best pair with strict criteria.
            {
                int bA=-1, bB=-1; double bS=0;
                int minSep=(int)(bw2*1.3), maxSep=(int)(bw2*2.8);
                if (minSep<8) minSep=8;
                if (maxSep>=ch) maxSep=ch-1;
                for (int i=0; i<ch; ++i) {
                    if (syncRow[i] < syncMax*0.75) continue;
                    int je = i+maxSep; if (je>=ch) je=ch-1;
                    for (int j=i+minSep; j<=je; ++j) {
                        if (syncRow[j] < syncMax*0.75) continue;
                        if (syncRow[i]+syncRow[j] > bS) { bS=syncRow[i]+syncRow[j]; bA=i; bB=j; }
                    }
                }
                // Validation 4: both rows must be strong and well-separated.
                if (bA<0 || bB<0) goto skip_sync;
                int sep = bB - bA;
                if (sep < (int)(bw2*1.3) || sep > (int)(bw2*2.8)) goto skip_sync;

                // Validation 5: only crop if reduction is meaningful (>20% of first crop).
                int tiltShift = (int)((double)tiltD * cw / image->h);
                int yA0 = bA, yA1 = bA + tiltShift;
                int yB0 = bB, yB1 = bB + tiltShift;
                int rowTop = yA0; if (yA1<rowTop) rowTop=yA1; if (yB0<rowTop) rowTop=yB0; if (yB1<rowTop) rowTop=yB1;
                int rowBot = yA0; if (yA1>rowBot) rowBot=yA1; if (yB0>rowBot) rowBot=yB0; if (yB1>rowBot) rowBot=yB1;
                int m = 16;
                int y0 = rowTop - m; if (y0<0) y0=0;
                int y1 = rowBot + m; if (y1>=ch) y1=ch-1;
                if (y1-y0 < 80) { y1=y0+80; if (y1>=ch) { y1=ch-1; y0=y1-80; if (y0<0) y0=0; } }
                if (y1-y0 >= ch*0.80) goto skip_sync;  // no meaningful reduction
                if (y1-y0 < 60) goto skip_sync;

                // All validations passed — apply tight crop.
                banded = TImage(banded.pixel + (size_t)y0 * banded.bpl,
                                cw, y1 - y0 + 1, banded.bpl);
                src = &banded;
            }
            skip_sync:;
        }
    }
    { auto _ms = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - _sc_t0).count();
      ILD_LOGI("stage(sync_crop) took %lldus", (long long)_ms); }

    // 2x vertical interpolation for better row resolution.
    TImage enlarged;
    enlarged.allocate(src->w, src->h * 2);
    { auto _t0 = std::chrono::steady_clock::now();
    interpolation_image(*src, enlarged);
    auto _ms = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - _t0).count();
    ILD_LOGI("stage(interpolation) took %lldus", (long long)_ms); }

    TImage bin_img;
    bin_img.allocate(enlarged.w, enlarged.h);
    { auto _t0 = std::chrono::steady_clock::now();
    ild_gaussian_binarization(enlarged, bin_img);
    auto _t1 = std::chrono::steady_clock::now();
    auto _ms = std::chrono::duration_cast<std::chrono::microseconds>(_t1 - _t0).count();
    ILD_LOGI("stage(gaussian_binarize) took %lldus", (long long)_ms); }

    if (decode_from_binary(&enlarged, &bin_img, src, isli_code, feax, feay, corrected_bits)) {
        ILD_LOGI("decode OK via GAUSSIAN code=%s", isli_code);
        return 1;
    }

    // DR-6: 主路径(bias=0)二值化解码失败时，复用主路径已算好的高斯 blur(g_blur)，用更低
    // 阈值(bias=-5 → 更多白/更细条)重新阈值化 enlarged 并重跑 decode_from_binary。复用 blur
    // 跳过高斯模糊(占二值化 ~75%)，兜底仅多一个阈值比较循环。主路径逐字节不变（已解码帧提前
    // return，0 回归 by construction）；救援弱对比帧（高斯阈值下塌缩的条）。FP 由下游 BCH cap≤6
    // + 真值重编码守卫兜底（不变）。ceiling A/B：bias=-5 rescue44/regress32/mismatch0；兜底仅
    // 作用于 bias=0 失败帧，回收 rescue 集（regress 帧已由主路径解码）。
    {
        ild_gaussian_rethreshold(enlarged, bin_img, -5);
        if (decode_from_binary(&enlarged, &bin_img, src, isli_code, feax, feay, corrected_bits)) {
            ILD_LOGI("decode OK via GAUSSIAN bias-retry code=%s", isli_code);
            return 1;
        }
    }

    ILD_LOGW("decode FAILED (all stages missed)");
    return 0;
}

static unsigned char get_avg_brightness(TImage *image)
{
    unsigned char *pixel = image->pixel;
    size_t len = image->h * image->bpl;
    size_t upper = len - len % 4;
    int sum = 0; // for a 1920x1080 image which is all white, it is sufficient.
    for (size_t i = 0; i < upper; i += 4)
    {
        assert(i + 3 < len);
        sum += pixel[i];
        sum += pixel[i + 1];
        sum += pixel[i + 2];
        sum += pixel[i + 3];
    }
    for (size_t i = upper; i < len; i++)
    {
        assert(i < len);
        sum += pixel[i];
    }
    return (unsigned char)(sum / len);
}

int isli_line_decoder_do_image_decode(IMAGE *image, char isli_code[20], short *feax, short *feay,
    int *brightness, int *is_blur)
{
    ILD_LOGI("decode image %dx%d bpl=%d", image->w, image->h, image->bpl);

    // is_blur is now only "too dark" (the FFT blur detector was removed; see
    // decode_landscape's `(void)is_blur`). It is read below at the inversion
    // fallback (`*is_blur != 1`) even though the normal-brightness path never
    // writes it — so initialize it here, otherwise callers that pass an
    // uninitialized out-param read garbage and the flag flips 0<->1
    // non-deterministically.
    *is_blur = 0;

    TImage orig(image->pixel, image->w, image->h, image->bpl);
    *brightness = get_avg_brightness(&orig);
    ILD_LOGD("avg brightness=%d", *brightness);
    if (*brightness < ILD_MIN_BRIGHTNESS) {
        *is_blur = 1;
        ILD_LOGW("rejected: brightness=%d < MIN_BRIGHTNESS=%d (too dark/blur)", *brightness, ILD_MIN_BRIGHTNESS);
        return 0;
    }
    unsigned char corrected_bits[ILD_BIT_COUNT] = {};
    int ok = decode_landscape(&orig, isli_code, feax, feay, is_blur, corrected_bits);
    if (ok) {
        ILD_LOGI("decode OK code=%s", isli_code);
        return 1;
    }

    // Inversion fallback for white-on-black barcodes (rare in practice).
    // Only attempted when the image is very bright (avg > 200), which suggests
    // the barcode may be light-on-dark rather than dark-on-light.
    if (*brightness > 240 && *is_blur != 1) {
        ILD_LOGI("trying inversion fallback (brightness=%d > 240)", *brightness);
        size_t total = (size_t)image->bpl * image->h;
        tl::buffer<unsigned char> inverted;
        inverted.resize(total);
        for (size_t i = 0; i < total; ++i)
            inverted[i] = 255 - image->pixel[i];
        TImage invImg(inverted.data(), image->w, image->h, image->bpl);
        if (decode_landscape(&invImg, isli_code, feax, feay, is_blur, corrected_bits)) {
            ILD_LOGI("decode OK (inverted) code=%s", isli_code);
            return 1;
        }
    }
    ILD_LOGW("decode FAILED (all paths exhausted) code='%.19s'", isli_code);
    return 0;
}
