#include "ISLIIconDecoder.h"
#include "ISLIIconLocator.h"
#include "BSPatternMatch.h"
#include "FrameTracer.h"
#include "CornerFinder.h"
#include "CurveSampler.h"
#include "Wave2Bits.h"
#include "bch.h"
#include "DecoderMemoryPool.h"
#include "IldLog.h"
#include <math.h>
#include <memory.h>
#include <chrono>

//==== 阶段计时（g_timing_enable=1 时累计，0=关闭无开销）====
static int g_timing_enable = 0;
static long long g_stage_us[6] = {0};  //[1]trace [2]corner [3]curve [4]wave [5]bch (微秒)
void islii_set_timing_enable(int e) { g_timing_enable = e; }
void islii_reset_stage_timing(void) { for (int i = 0; i < 6; i++) g_stage_us[i] = 0; }
void islii_get_stage_timing(long long out[6]) { for (int i = 0; i < 6; i++) out[i] = g_stage_us[i]; }
#define STAGE_TIMER_BEGIN(var) auto _st_##var = std::chrono::steady_clock::now()
#define STAGE_TIMER_END(var, idx) do { if (g_timing_enable) g_stage_us[idx] += \
    std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - _st_##var).count(); } while(0)
#include <string.h>

#define REMOTE_DRAW 0
#if REMOTE_DRAW
#include "canvas.h"
#include <QDebug>
#endif


bch_control*   __bch_ctrl63 = 0;
bch_control*   __bch_ctrl127 = 0;

DecoderMemoryPool* g_pool = 0;
extern int g_wave_bitth_used;

// 最近一次解码的失败阶段（0=成功）
static int g_last_fail_stage = 0;
int islii_get_last_fail_stage() { return g_last_fail_stage; }

// === 诊断状态（仅批量分析用）===
static int g_last_bch_err63 = -1;
static int g_last_bch_err112 = -1;
static int g_last_wave63_ret = 0;
static int g_last_wave112_ret = 0;
static int g_last_dot_num = 0;
static unsigned char g_last_received63[9] = {0};
static unsigned char g_last_received112[17] = {0};
static unsigned char g_last_bits63_raw[63] = {0};
int islii_get_last_bch_err63()  { return g_last_bch_err63; }
int islii_get_last_bch_err112() { return g_last_bch_err112; }
int islii_get_last_wave63_ret()  { return g_last_wave63_ret; }
int islii_get_last_wave112_ret() { return g_last_wave112_ret; }
int islii_get_last_dot_num()    { return g_last_dot_num; }
void islii_get_last_received63(unsigned char out[9]) {
    memcpy(out, g_last_received63, 9);
}
void islii_get_last_received112(unsigned char out[17]) {
    memcpy(out, g_last_received112, 17);
}
void islii_get_last_bits63_raw(unsigned char out[63]) {
    memcpy(out, g_last_bits63_raw, 63);
}

// 追踪 fallback 开关（默认启用：mode0 失败再试 mode2）
static int g_trace_fallback = 1;
void islii_set_trace_fallback(int enable) { g_trace_fallback = enable; }

// 快速模式（默认关闭）：激进性能优化，容许准确度下降
//   - 定位：扫描步长加倍 + BS 容差放宽到 ±12%
//   - 追踪：amend_center 迭代 3→2，部分弧接受阈值 100→80
//   - 解码：跳过 112-bit 回退，跳过 try-both mode-2 重试
static int g_fast_mode = 0;
void islii_set_fast_mode(int enable) { g_fast_mode = enable; islii_set_trace_subsample(enable ? 2 : 1); }

//Chase 软判决开关（默认0=A/B隔离，默认1=shipped）
static int g_chase_enable = 0;  // 63-bit Chase 已禁用：err∈{4,5}时可能误纠FP（实测 cache2 2FP）。
//原 +5 cache1 收益已由 c3 极性重试 (+45) 超额补偿，且 0 FP 为硬性要求。
void islii_set_chase_enable(int e) { g_chase_enable = e; }
int  islii_get_chase_enable() { return g_chase_enable; }
// 112-bit Chase 默认禁用（+0 收益，19位码 FP 风险源，report 警告）
static int g_chase112_enable = 0;
void islii_set_chase112_enable(int e) { g_chase112_enable = e; }
int  islii_get_fast_mode() { return g_fast_mode; }

//P1 模型角点预测（默认0=仅对称性修正，1=始终从标记+几何推导4角）
static int g_model_corners = 0;
void islii_set_model_corners(int e) { g_model_corners = e; }
int  islii_get_model_corners() { return g_model_corners; }

//P2 直接采样（默认0=曲线拟合+弧长采样，1=直接从trace点线性采样）
static int g_direct_sample = 0;
void islii_set_direct_sample(int e) { g_direct_sample = e; }
int  islii_get_direct_sample() { return g_direct_sample; }

//预处理开关（默认0=禁用，需要更多调优才能稳定启用）
static int g_preprocess = 0;
void islii_set_preprocess(int e) { g_preprocess = e; }
int  islii_get_preprocess() { return g_preprocess; }

//BCH 纠错接受上限（默认 63bit=3, 112bit=7，保守防误纠）
//诊断用：可放宽到 5/7 测量上限，但 shipped 必须保持 3/7
static int g_max_bch_err63 = 3;
static int g_max_bch_err112 = 3;
void islii_set_max_bch_err63(int n)  { g_max_bch_err63 = (n < 0 ? 0 : (n > 5 ? 5 : n)); }
void islii_set_max_bch_err112(int n) { g_max_bch_err112 = (n < 0 ? 0 : (n > 7 ? 7 : n)); }
int  islii_get_max_bch_err63()  { return g_max_bch_err63; }
int  islii_get_max_bch_err112() { return g_max_bch_err112; }

//曲线采样 try-both（默认1=启用）：direct(P2) 失败后回退多项式拟合(direct=0)重试。
//cache1 实测 +27 解码（poly 路径解码 direct 漏掉的图），零回归零误报。
static int g_curve_try_both = 1;
void islii_set_curve_try_both(int e) { g_curve_try_both = e; }
int  islii_get_curve_try_both() { return g_curve_try_both; }

//c3 长弧同步极性重试（默认1=启用）：63-bit BCH 失败时，逐一尝试 c3 两条同步位的
//4 种强制极性组合（[0,0][1,0][0,1][1,1]），由 BCH err<=3 + re-encode 校验裁决。
//根因：c3 长弧的 is_peak 自动检测会被相邻数据位污染（c0/c1/c2 完全正确、c3 错~半数位）。
//零回归：仅在自动极性 BCH 失败时触发；接受标准与基线一致（err<=3 + re-encode 匹配）。
static int g_c3_retry = 1;
void islii_set_c3_retry(int e) { g_c3_retry = e; }
int  islii_get_c3_retry() { return g_c3_retry; }

//c2+c3 联合同步极性重试（默认1=启用）：c3_retry 仅重试 c3（c2 自动），
//对 c2+c3 dominant 失败（两长弧极性均误，c0/c1 正确）无效。此时 c3 强制极性虽对，
//但 c2 自动仍错 -> BCH err 仍 >3。联合重试枚举 c2×c3 共 16 组极性，取 BCH err 最小的合格组合。
//根因：c2 长弧(24bit) 与 c3 长弧(23bit) 的 is_peak 自动检测同理被污染；diag 实测 c2+c3
//dominant ~810 图（cache2 277 / cache3 242 / cache1 120），为最大失败桶。
//零回归：仅在 63-bit auto + c3_retry 均失败后触发；接受标准与基线一致（err<=3 + re-encode）。
static int g_c2_retry = 1;
void islii_set_c2_retry(int e) { g_c2_retry = e; }
int  islii_get_c2_retry() { return g_c2_retry; }

//同步位置偏移重试（默认1=启用）：c2+c3 同步极性重试均失败后，对两条长弧的 2 个同步位
//施加 ±1 比特偏移联合重试（auto 极性），min-err 选择，err==0 提前退出。
//根因：cache2 c2+c3 主导失败（~810图）经诊断是同步位置错位——c2 整体偏移1比特
//(got==exp>>1)，c3 单同步位错位使一个子段偏移；信号满对比度、跨图确定性复现，
//极性重试(force_peak)不改位置故 +0。位置偏移尝试相邻峰/谷同步位以纠正错位。
//零回归：仅在前序 63-bit 重试均失败后触发；接受阈值 err<=g_pos_retry_max_err(默认2)，
//比基线 err<=3 收紧（36 组合多重比较防伪 BCH 可解 FP）。
static int g_pos_retry = 1;
void islii_set_pos_retry(int e) { g_pos_retry = e; }
int  islii_get_pos_retry() { return g_pos_retry; }
//pos_retry 接受阈值（默认2=err<=2）：36 组合多重比较下 err<=3 有伪 BCH 可解风险（cache5
//68719476735 小盾实测 1 FP）。收紧到 err<=2：随机词 err<=2 概率~1.5e-5/组合，36x1140 期望
// FP<1，实测全 cache 0 FP 0 回归，保留 err∈{0,1,2} 救回。auto 路径仍用 g_max_bch_err63(=3)。
static int g_pos_retry_max_err = 2;
void islii_set_pos_retry_max_err(int e) { g_pos_retry_max_err = e; }
int  islii_get_pos_retry_max_err() { return g_pos_retry_max_err; }
//pos_retry 单弧偏移扩展（默认1=启用，追加12单弧组合）：36 联合组合要求 c2、c3 均非零偏移，
//漏掉"仅一弧偏移"情形。诊断(cache2 mode-0-direct sweep)发现 73 帧仅 c3=(0,-1) 单弧偏移即可修
//(bch=1)，c2 已正确(err=0)；联合搜索强迫 c2 非零偏移反而破坏 c2 -> 漏救。追加 c2-only 6 +
//c3-only 6 = 12 组合，复用同一 min-err 与 err<=2 阈值。A/B 全 cache：+157 解码(1407->1564)，
//0 FP 0 回归，cache2 +81(最大)。err<=2 下 12 新组合无伪 BCH FP(含 cache5 小盾)。
static int g_pos_retry_single = 1;
void islii_set_pos_retry_single(int e) { g_pos_retry_single = e; }
int  islii_get_pos_retry_single() { return g_pos_retry_single; }

//span 放宽重试（默认1=启用）：g_min_span(0.75) 下整条 wave2bits+BCH 失败时，
//放宽同步跨度到 SPAN_RETRY_FALLBACK(0.70) 重试一次（fallback，0.75 优先）。
//根因：182/591 图卡在 wave 同步(span<75%)；放宽到 0.70 可救回部分边界波形。
//不能直接下调 g_min_span：低阈值会移动鲁棒/原始同步切换边界，对另一批图产生回归
//（22.6.2 实测 shipped c3r 下 -48）。fallback 方式仅对 0.75 失败的图触发，零回归。cache1-6 实测 +16，0 FP。
static int g_span_retry = 1;
void islii_set_span_retry(int e) { g_span_retry = e; }
int  islii_get_span_retry() { return g_span_retry; }
static const double SPAN_RETRY_FALLBACK = 0.70;

//退化码字过滤：拒绝全1(2^36-1=68719476735 / 2^63-1) 或全0 数据字。
//这类码字在位提取失败时出现（NEON float 精度差异 / 阈值崩溃 / 全黑全白帧），
//BCH 一致性校验无法拦截（全1、全0 均为合法码字，re-encode 必然匹配）。
//真实盾牌码为混合比特，数据字不可能是全同 -> 过滤安全。
//cache5 真机 12 个 68719476735 FP 即此签名（手机运行过期 NEON 快照所致，见报告第二十一节）。
static int g_reject_degenerate = 1;
void islii_set_reject_degenerate(int e) { g_reject_degenerate = e; }
int  islii_get_reject_degenerate() { return g_reject_degenerate; }


//图像预处理：对比度拉伸 + 轻度锐化，改善低对比度盾牌的波形质量
//在 locate 之前调用，修改 image->pixel 原地（调用者需确保可写）
static void preprocess_image(IMAGE* image)
{
    if (!g_preprocess) return;
    int w = image->w, h = image->h, bpl = image->bpl;
    unsigned char* pixel = image->pixel;
    int total = w * h;

    //1) 直方图采样（每4像素采1个，速度优先）
    int hist[256] = {0};
    for (int y = 0; y < h; y += 2) {
        unsigned char* p = pixel + y * bpl;
        for (int x = 0; x < w; x += 2) {
            hist[p[x]]++;
        }
    }
    //找 p5 和 p95 百分位
    int sample_total = (total + 3) / 4;
    int p5 = 0, p95 = 255;
    int sum = 0, target5 = sample_total * 5 / 100;
    int target95 = sample_total * 95 / 100;
    for (int i = 0; i < 256; i++) {
        sum += hist[i];
        if (sum < target5) p5 = i;
        if (sum < target95) p95 = i;
    }
    if (p95 <= p5 + 10) return; //已有足够对比度，跳过

    ISLII_LOGI("[preprocess] contrast stretch: [%d,%d] -> [0,255]", p5, p95);
    double scale = 255.0 / (p95 - p5);

    //2) 对比度拉伸（Pass 1：全图）
    for (int i = 0; i < total; i++) {
        int v = (int)((pixel[i] - p5) * scale);
        if (v < 0) v = 0; if (v > 255) v = 255;
        pixel[i] = (unsigned char)v;
    }

    //3) 3×3 模糊（Pass 2）+ 锐化（Pass 3），使用内存池临时缓冲
    unsigned char* blurred = g_pool ? g_pool->vert_scan_buf : 0;
    int need_alloc = 0;
    if (!blurred || (size_t)total > 4096) {
        blurred = new unsigned char[(size_t)total];
        need_alloc = 1;
    }

    for (int y = 0; y < h; y++) {
        unsigned char* src = pixel + y * bpl;
        unsigned char* dst = blurred + y * bpl;
        for (int x = 0; x < w; x++) {
            if (y > 0 && y < h - 1 && x > 0 && x < w - 1) {
                int sum3 = src[x-1] + src[x] + src[x+1]
                         + src[x-1 - bpl] + src[x - bpl] + src[x+1 - bpl]
                         + src[x-1 + bpl] + src[x + bpl] + src[x+1 + bpl];
                dst[x] = (unsigned char)((sum3 + 4) / 9);
            } else {
                dst[x] = src[x];
            }
        }
    }

    //4) 锐化：sharp = orig + amount * (orig - blurred)，amount=0.35
    for (int i = 0; i < total; i++) {
        int diff = (int)pixel[i] - (int)blurred[i];
        int sharp = pixel[i] + (int)(diff * 0.35);
        if (sharp < 0) sharp = 0; if (sharp > 255) sharp = 255;
        pixel[i] = (unsigned char)sharp;
    }

    if (need_alloc) delete[] blurred;
    ISLII_LOGI("[preprocess] done: p5=%d p95=%d scale=%.2f", p5, p95, scale);
}

int isli_icon_decoder_init()
{
    if (0 == __bch_ctrl63) {
        __bch_ctrl63 = init_bch(6, 5, 0);
        __bch_ctrl127 = init_bch(7, 7, 0);

        if (!g_pool) {
            g_pool = new DecoderMemoryPool();
            memset(g_pool, 0, sizeof(DecoderMemoryPool));  // 消除未初始化内存造成的非确定性
        }

        return 1;
    }
    else {
        return 0;
    }
}

int isli_icon_decoder_uninit()
{
    if (__bch_ctrl63) {
        free_bch(__bch_ctrl63);
        __bch_ctrl63 = 0;

        free_bch(__bch_ctrl127);
        __bch_ctrl127 = 0;

        delete g_pool;
        g_pool = 0;

        return 1;
    }
    else {
        return 0;
    }
}

#if REMOTE_DRAW
//给四角打上标记
static void mark_corner(double* px, double* py, int corner_pos[4], double frame_width)
{
    double cx = 0, cy = 0;
    for (int i = 0; i < 4; i++){
        cx += px[corner_pos[i]];
        cy += py[corner_pos[i]];
    }
    cx /= 4;
    cy /= 4;
    for (int i = 0; i < 4; i++){
        int k = corner_pos[i];

        double dx = px[k] - cx;
        double dy = py[k] - cy;
        double r = sqrt(dx * dx + dy * dy);
        double d = frame_width * 1.5;
        if (d < 10)
            d = 10;
        double ofstx = d / r * dx;
        double ofsty = d / r * dy;
        char no[2] = { 0 };
        no[0] = (char)('0' + i);

        __canvas.DrawDot("source", "shape=circle;color=0xff;size=6", short(px[k] + 0.5), short(py[k] + 0.5));
        __canvas.DrawText("source", "color=0xff", short(px[k] + ofstx - 4 + 0.5), short(py[k] + ofsty - 8 + 0.5), no);
        //__canvas.DrawLine("source", "color=0xff", cx, cy, short(px[k] + ofstx + 0.5), short(py[k] + ofsty + 0.5));
    }
}
#endif

// ________________________________________________________________________________________________________________________________________________________
//|                                       data                                         |                               ecc                                 |
//|____________________________________________________________________________________|___________________________________________________________________|
//|     BYTE0      |     BYTE1      |     BYTE2      |     BYTE3      |     BYTE4      |     BYTE5      |     BYTE6      |     BYTE7      |     BYTE8      |
//|-_______________|________________|________________|________________|________________|________________|________________|________________|________________|
//|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|
//|xxxxxxxxvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvxxxxxxxxxx|
//|________________|________________|________________|________________|________________|________________|________________|________________|________________|
//
// 63bit排列顺序：从BYTE0到BYTE8，每个BYTE内从b0到b7，x表示不使用且固定为0,v为有效bit
static void compact_bits(const unsigned char bits[63], unsigned char received[9])
{
    memset(received, 0, 9);

    int k = 0;
    for (int i = 0; i < 8 * 9; i++){
        if ((i >= 4 && i <= 7) || (i >= 64 && i <= 68)) {
            continue;
        }
        if (bits[k]) {
            received[i >> 3] |= (1 << (i & 7));
        }
        k++;
    }
}

static int bits2string(unsigned char bits[5], char str[12])
{
    long long v = 0;

    int k = 0;
    for (int i = 0; i < 5*8; i++) {
        if (i >= 4 && i <= 7) {
            continue;
        }
        if (bits[i >> 3] & (1 << (i & 7))){
            v |= ((long long)1 << k);
        }
        k++;
    }

    long long val = v;  //保存原始 36-bit 值用于退化检查（下面的循环会消耗 v）
    for (int i = 0; i < 11; i++) {
        char c = (v % 10) + '0';
        str[10 - i] = c;
        v = v / 10;
    }
    str[11] = 0;

    //退化码字过滤：全1(2^36-1=68719476735) 或 全0 -> 返回0表示拒绝
    if (g_reject_degenerate && (val == 0 || val == 0xFFFFFFFFFLL)) {
        return 0;
    }
    return 1;
}

//自检：构造全1/全0 数据字，验证退化码字过滤在 guard ON 时拒绝、OFF 时放行。
//PC 真机数据从不产生全1（NEON 已移除），故用合成数据证明 guard 逻辑正确。
int islii_selftest_degenerate_guard(void)
{
    unsigned char all_ones[5]  = { 0x0F, 0xFF, 0xFF, 0xFF, 0xFF };  //36 数据位全1 -> 68719476735
    unsigned char all_zero[5]  = { 0, 0, 0, 0, 0 };                  //36 数据位全0 -> 00000000000
    char code[12] = { 0 };
    int saved = g_reject_degenerate;

    g_reject_degenerate = 1;
    int on_ones = bits2string(all_ones, code);   //期望 0 (拒绝), code=="68719476735"
    int on_zero = bits2string(all_zero, code);   //期望 0 (拒绝), code=="00000000000"

    g_reject_degenerate = 0;
    int off_ones = bits2string(all_ones, code);  //期望 1 (放行), code=="68719476735"
    int off_zero = bits2string(all_zero, code);  //期望 1 (放行), code=="00000000000"

    g_reject_degenerate = saved;
    return (on_ones == 0 && on_zero == 0 && off_ones == 1 && off_zero == 1) ? 1 : 0;
}

static int bits_decode(const unsigned char bits[63], unsigned char* conf, char isli_code[12])
{
    unsigned char received[9] = { 0 };
    unsigned int error_loc[5] = { 0 };

    compact_bits(bits, received);
    memcpy(g_last_received63, received, 9);

    int err_num = decode_bch(__bch_ctrl63, &received[0], 5, &received[5], 0, 0, error_loc);
    g_last_bch_err63 = err_num;
    if (err_num >= 0 && err_num <= g_max_bch_err63) {
        for (int i = 0; i < err_num; i++) {
            unsigned int k = error_loc[(size_t)i];
            received[k >> 3] ^= (1 << (k & 7));
        }

        unsigned char data[5] = { 0 };
        unsigned char ecc[4] = { 0 };
        memcpy(data, received, 5);
        encode_bch(__bch_ctrl63, data, 5, ecc);
        if (0 == memcmp(&received[5], ecc, 4)) {
            if (bits2string(data, isli_code)) {
                return 1;  //成功（非退化码字）
            }
        }
    }

    //Chase 软判决：翻转最低置信度比特组合重试 BCH。
    //仅在直接解码"接近"成功时（err_num∈{4,5}，差1-2位即可纠）才启用。
    //err_num=-1（不可纠，>5 错）时跳过：此时 Chase 翻转更易落入另一合法码字（误纠 FP）。
    //百分位阈值改变了 bit，Chase 双翻转可能误纠(FP) -> 也跳过。
    if (g_chase_enable && conf && !g_wave_bitth_used && err_num >= 4 && err_num <= 5) {
        int L = 6, idx[63];
        for (int i=0;i<63;i++) idx[i]=i;
        //按置信度升序排序前L个
        for (int i=0;i<L;i++) for (int j=i+1;j<63;j++) if (conf[idx[j]] < conf[idx[i]]) {int t=idx[i];idx[i]=idx[j];idx[j]=t;}
        //单比特翻转
        for (int a=0;a<L;a++){
            unsigned char tb[63]; memcpy(tb,bits,63);
            int bi = idx[a]; tb[bi] = bits[bi] ? 0 : 0xFF;
            unsigned char r2[9]={0}; unsigned int el2[5]={0};
            compact_bits(tb,r2);
            int en=decode_bch(__bch_ctrl63,r2,5,&r2[5],0,0,el2);
            if (en>=0&&en<=3){
                for (int j=0;j<en;j++) r2[el2[j]>>3]^=(1<<(el2[j]&7));
                unsigned char d2[5]={0},e2[4]={0}; memcpy(d2,r2,5);
                encode_bch(__bch_ctrl63,d2,5,e2);
                if (0==memcmp(&r2[5],e2,4)){if(bits2string(d2,isli_code))return 1;}
            }
        }
        //双比特翻转
        for (int a=0;a<L;a++) for (int b=a+1;b<L;b++){
            unsigned char tb[63]; memcpy(tb,bits,63);
            int bi=idx[a]; tb[bi]=bits[bi]?0:0xFF;
            bi=idx[b]; tb[bi]=bits[bi]?0:0xFF;
            unsigned char r2[9]={0}; unsigned int el2[5]={0};
            compact_bits(tb,r2);
            int en=decode_bch(__bch_ctrl63,r2,5,&r2[5],0,0,el2);
            if (en>=0&&en<=3){
                for (int j=0;j<en;j++) r2[el2[j]>>3]^=(1<<(el2[j]&7));
                unsigned char d2[5]={0},e2[4]={0}; memcpy(d2,r2,5);
                encode_bch(__bch_ctrl63,d2,5,e2);
                if (0==memcmp(&r2[5],e2,4)){if(bits2string(d2,isli_code))return 1;}
            }
        }
    }

    return 0;
}

// __________________________________________________________________________________________________________________________________________________________________________
//|                                       data， 80bits - 2个x位 - 15个0位 = 63位有效位                                                                                        | 
//|_________________________________________________________________________________________________________________________________________________________________________|
//|     BYTE0      |     BYTE1      |     BYTE2      |     BYTE3      |     BYTE4       |    BYTE5      |     BYTE6      |     BYTE7      |     BYTE8      |     BYTE9      |
//|________________|________________|________________|________________|_________________|_______________|________________|________________|________________|________________|
//|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0b|7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|
//|0000000000000000|0000000000000000|vvvvvvvvvvvvvv00|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|
//|________________|________________|________________|________________|_________________|_______________|________________|________________|________________|________________|
//|                                       ecc[49bits]                                                   |                |                                 
//|_____________________________________________________________________________________________________|________________|
//|     BYTE10     |     BYTE11     |     BYTE12     |     BYTE13     |     BYTE14      |     BYTE15    |     BYTE16     |
//|________________|________________|________________|________________|_________________|_______________|________________|
//|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0b|7b6b5b4b3b2b1b0|b7b6b5b4b3b2b1b0|
//|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvvvv|vvvvvvvvvvvvvvv|vv00000000000000|
//|________________|________________|________________|________________|_________________|_______________|________________|
//
// 127bit排列顺序：从BYTE0到BYTE16，每个BYTE内从b0到b7，v为有效bit,0为预设固定值0
static const int PRESET_DATA_ZERO_BITS_START = 0;
static const int PRESET_DATA_ZERO_BITS_END   = 16;
static const int PRESET_ECC_ZERO_BITS_START  = 48;
static const int PRESET_ECC_ZERO_BITS_END    = 54;

static void compact_bits2(const unsigned char bits[112], unsigned char received[17])
{
    memset(received, 0, 17);

    int i = 0, k = 0;
    for (i = 0, k = 0; i < 10*8; i++){
        if (i >= PRESET_DATA_ZERO_BITS_START &&
            i <= PRESET_DATA_ZERO_BITS_END) {
            continue;
        }
        if (bits[k]) {
            received[i >> 3] |= (1 << (i & 7));
        }
        k++;
    }
    for (i = 0; i < 7*8; i++){
        if (i >= PRESET_ECC_ZERO_BITS_START &&
            i <= PRESET_ECC_ZERO_BITS_END){
            continue;
        }
        if (bits[k]) {
            int j = 80 + i;
            received[j >> 3] |= (1 << (j & 7));
        }
        k++;
    }
}

static int bits2string2(unsigned char bits[10], char str[20])
{
    long long v = 0;

    int k = 0;
    for (int i = 0; i < 80; i++) {
        if (i < 17) {
            continue;
        }
        if (bits[i >> 3] & (1 << (i & 7))){
            v |= ((long long)1 << k);
        }
        k++;
    }

    long long val = v;  //保存原始 63-bit 值用于退化检查
    for (int i = 0; i < 19; i++) {
        char c = (v % 10) + '0';
        str[18 - i] = c;
        v = v / 10;
    }
    str[19] = 0;

    //退化码字过滤：全1(2^63-1) 或 全0 -> 返回0表示拒绝
    if (g_reject_degenerate && (val == 0 || val == 0x7FFFFFFFFFFFFFFFLL)) {
        return 0;
    }
    return 1;
}

static int bits_decode2(const unsigned char bits[112], unsigned char* conf, char isli_code[20])
{
    unsigned char received[17] = { 0 };
    unsigned int error_loc[7] = { 0 };

    compact_bits2(bits, received);
    memcpy(g_last_received112, received, 17);

    int err_num = decode_bch(__bch_ctrl127, &received[0], 10, &received[10], 0, 0, error_loc);
    g_last_bch_err112 = err_num;
    if (err_num >= 0 && err_num <= g_max_bch_err112) {
        for (int i = 0; i < err_num; i++) {
            unsigned int k = error_loc[(size_t)i];
            if (((k >= PRESET_DATA_ZERO_BITS_START) && (k <= PRESET_DATA_ZERO_BITS_END)) ||
                ((k >= PRESET_ECC_ZERO_BITS_START)  && (k <= PRESET_ECC_ZERO_BITS_END))){
                return 0;
            }
            received[k >> 3] ^= (1 << (k & 7));
        }

        unsigned char data[10] = { 0 };
        unsigned char ecc[7] = { 0 };
        memcpy(data, received, 10);
        encode_bch(__bch_ctrl127, data, 10, ecc);
        if (0 == memcmp(&received[10], ecc, 7)) {
            if (bits2string2(data, isli_code)) {
                return 1;  //成功（非退化码字）
            }
        }
    }

    if (g_chase112_enable) {
        for (int i = 0; i < 112; i++) {
            unsigned char tb[112];
            memcpy(tb, bits, 112);
            tb[i] = bits[i] ? 0 : 0xFF;
            unsigned char r2[17]={0};
            unsigned int el2[7]={0};
            compact_bits2(tb, r2);
            int en = decode_bch(__bch_ctrl127, r2, 10, &r2[10], 0, 0, el2);
            if (en >= 0 && en <= 7) {
                int bad = 0;
                for (int j=0;j<en;j++) {
                    unsigned int k = el2[j];
                    if ((k>=PRESET_DATA_ZERO_BITS_START && k<=PRESET_DATA_ZERO_BITS_END)||
                        (k>=PRESET_ECC_ZERO_BITS_START && k<=PRESET_ECC_ZERO_BITS_END)){bad=1;break;}
                    r2[k>>3] ^= (1<<(k&7));
                }
                if (!bad) {
                    unsigned char d2[10]={0}, e2[7]={0};
                    memcpy(d2, r2, 10);
                    encode_bch(__bch_ctrl127, d2, 10, e2);
                    if (0==memcmp(&r2[10],e2,7)){if(bits2string2(d2,isli_code))return 1;}
                }
            }
        }
    }

    return 0;
}

//定位后的解码流水线（trace→corner→curve→bits→BCH），按指定追踪模式执行
//返回1成功，0失败（g_last_fail_stage 记录失败阶段）
static int decode_pipeline(IMAGE* image, int x1, int y1, int x2, int y2, double frame_size,
                           int trace_mode, char isli_code[20], short feax[6], short feay[6])
{
    islii_set_trace_mode(trace_mode);

    //外框追踪 - 使用内存池中的预分配缓冲区
    double* px = g_pool->px;
    double* py = g_pool->py;
    int dot_num;
    int corner_pos[4];
    int is_clockwise = 0;
    int ret = 0;

    //trace 复用：poly 回退时跳过 mode 0 的 trace+corner，复用 direct 的缓存结果（避免重追踪）
    dot_num = DecoderMemoryPool::MAX_DOTS;
    STAGE_TIMER_BEGIN(trace);
    ret = do_trace_frame(image, x1, y1, x2, y2, frame_size, px, py, &dot_num);
    STAGE_TIMER_END(trace, 1);
    g_last_dot_num = dot_num;
    if (!ret || dot_num < 88) {
        ISLII_LOGE("do_trace_frame FAILED: ret=%d dot_num=%d (need >= 88)", ret, dot_num);
        g_last_fail_stage = 2;
        ISLII_LOGI("[summary] mode=%d fw=%.1f dot_num=%d stage=2 TRACE_FAIL", trace_mode, frame_size, dot_num);
        return 0;
    }
    ISLII_LOGI("do_trace_frame OK: dot_num=%d", dot_num);
    STAGE_TIMER_BEGIN(corner);
    is_clockwise = do_corner_finder(px, py, dot_num, corner_pos);
    finetune_corners(image, px, py, dot_num, corner_pos, frame_size, is_clockwise);
    STAGE_TIMER_END(corner, 2);
    {
        double cx0=px[corner_pos[0]],cy0=py[corner_pos[0]];
        double cx1=px[corner_pos[1]],cy1=py[corner_pos[1]];
        double cx2=px[corner_pos[2]],cy2=py[corner_pos[2]];
        double cx3=px[corner_pos[3]],cy3=py[corner_pos[3]];
        double dx01=cx1-cx0,dy01=cy1-cy0,dx12=cx2-cx1,dy12=cy2-cy1;
        double dx23=cx3-cx2,dy23=cy3-cy2,dx30=cx0-cx3,dy30=cy0-cy3;
        double e0=sqrt(dx01*dx01+dy01*dy01), e1=sqrt(dx12*dx12+dy12*dy12);
        double e2=sqrt(dx23*dx23+dy23*dy23), e3=sqrt(dx30*dx30+dy30*dy30);
        if (e0>0 && e1>0) { double r=(e0<e1?e0/e1:e1/e0); if(r<0.65){
            cx1=(cx0+cx2)/2; cy1=(cy0+cy2)/2-3.0*frame_size;
            px[corner_pos[1]]=cx1; py[corner_pos[1]]=cy1;
        }}
        if (e2>0 && e3>0) { double r=(e2<e3?e2/e3:e3/e2); if(r<0.65){
            cx3=(cx0+cx2)/2; cy3=(cy0+cy2)/2+20.0*frame_size;
            px[corner_pos[3]]=cx3; py[corner_pos[3]]=cy3;
        }}
    }
        if (g_model_corners) {
        double cx0=px[corner_pos[0]],cy0=py[corner_pos[0]];
        double cx1=px[corner_pos[1]],cy1=py[corner_pos[1]];
        double cx2=px[corner_pos[2]],cy2=py[corner_pos[2]];
        double cx3=px[corner_pos[3]],cy3=py[corner_pos[3]];
        //计算四边形面积（用鞋带公式的绝对值）
        double area = 0.5 * fabs(
            cx0*cy1 + cx1*cy2 + cx2*cy3 + cx3*cy0 -
            cy0*cx1 - cy1*cx2 - cy2*cx3 - cy3*cx0);
        double diag02 = sqrt((cx2-cx0)*(cx2-cx0) + (cy2-cy0)*(cy2-cy0));
        double diag13 = sqrt((cx3-cx1)*(cx3-cx1) + (cy3-cy1)*(cy3-cy1));
        //盾牌应有显著面积和合理对角线比
        //收紧阈值：仅在形状几乎退化（面积极小或对角线比极端）时才介入
        //避免过度替换 traced 角点——P2 直接采样是主收益来源
        double min_area = frame_size * frame_size * 2.0;
        double max_diag_ratio = 15.0;  // very conservative: only catch complete collapse
        double dr = (diag02 > diag13) ? diag02/diag13 : diag13/diag02;
        int bad_shape = (area < min_area || dr > max_diag_ratio || area != area);
        if (bad_shape && diag02 > frame_size * 2) {
            //角点形状不合理，用模型预测全部替换（并 clamp 到图像边界内）
            double mid_x = (x1 + x2) * 0.5;
            double mid_y = (y1 + y2) * 0.5;
            double pcx[4] = { (double)x1, mid_x, (double)x2, mid_x };
            double pcy[4] = { mid_y, mid_y - 3.2 * frame_size, mid_y, mid_y + 25.0 * frame_size };
            // clamp to image bounds (with margin)
            double margin = frame_size * 4;
            double xmin = margin, xmax = image->w - 1 - margin;
            double ymin = margin, ymax = image->h - 1 - margin;
            for (int i = 0; i < 4; i++) {
                if (pcx[i] < xmin) pcx[i] = xmin;
                if (pcx[i] > xmax) pcx[i] = xmax;
                if (pcy[i] < ymin) pcy[i] = ymin;
                if (pcy[i] > ymax) pcy[i] = ymax;
                px[corner_pos[i]] = pcx[i];
                py[corner_pos[i]] = pcy[i];
            }
            ISLII_LOGI("[model] shape bad (area=%.0f diag_ratio=%.1f), using predicted corners", area, dr);
        }
    }
    ISLII_LOGI("do_corner_finder OK: corners=(%d,%d,%d,%d) clockwise=%d",
              corner_pos[0], corner_pos[1], corner_pos[2], corner_pos[3], is_clockwise);
#if REMOTE_DRAW
    mark_corner(px, py, corner_pos, frame_size);
#endif
    for (int i = 0; i < 4; i++){
        feax[i] = short(px[corner_pos[i]] + 0.5);
        feay[i] = short(py[corner_pos[i]] + 0.5);
    }

    //逐段拟合曲线，采样波形 — 使用内存池中的预分配缓冲区
    int one_curve_len = max_curve_length();
    unsigned char* curve_buffer = g_pool->curve_buf;
    unsigned char* pcurve[4] = { 0 };
    int            curve_len[4] = { 0 };

    for (int i = 0; i < 4; i++){
        pcurve[i] = curve_buffer + i * one_curve_len;
        curve_len[i] = one_curve_len;
    }

    //尝试用给定 c2/c3 同步极性从当前曲线解码 63-bit。
    //fp1/fp2=-1=自动检测(默认)，>=0=强制 c3 两条同步位的极性(0=谷,1=峰)。
    //c2fp1/c2fp2 同理作用于 c2 长弧（-1=自动）。
    //复用已采样的曲线，仅重做 wave2bits63 + BCH（远轻于 trace/curve_sample）。
    //返回：成功(通过 err<=3 + re-encode)时返回 BCH err_num(0..3)，失败返回 -1。
    //成功码字写入 code_out（不影响外层 isli_code，便于多组合择优）。
    auto try_decode63 = [&](int fp1, int fp2, int c2fp1, int c2fp2, char* code_out) -> int {
        // 零初始化 + wave 失败跳过 BCH：do_wave2bits63 失败时 break 早退，bits63 仅部分填充，
        // 若直接 bits_decode 会读到栈上未初始化字节 -> 非确定性 FP（如 52512886016）。
        unsigned char bits63[112] = {0};
        unsigned char conf63[64] = {0};
        if (fp1 >= 0) islii_set_c3_force_peak(fp1, fp2);
        if (c2fp1 >= 0) islii_set_c2_force_peak(c2fp1, c2fp2);
        STAGE_TIMER_BEGIN(wave);
        g_last_wave63_ret = do_wave2bits63(pcurve, curve_len, bits63, g_chase_enable ? conf63 : 0);
        STAGE_TIMER_END(wave, 4);
        memcpy(g_last_bits63_raw, bits63, 63);
        if (fp1 >= 0) islii_set_c3_force_peak(-1, -1);  // 复位为自动
        if (c2fp1 >= 0) islii_set_c2_force_peak(-1, -1);  // 复位为自动
        code_out[0] = 0;
        STAGE_TIMER_BEGIN(bch);
        int bch_ok = g_last_wave63_ret && bits_decode(bits63, g_chase_enable ? conf63 : 0, code_out);
        STAGE_TIMER_END(bch, 5);
        if (bch_ok)
            return islii_get_last_bch_err63();  // 成功：返回纠错数
        return -1;
    };

    //c2/c3 同步极性强制组合：4 种（2 同步位 × 0=谷/1=峰）。c2 与 c3 各取一组即 16 联合组合。
    static const int PEAK_COMBOS[4][2] = { {0,0},{1,0},{0,1},{1,1} };

    //完整 wave2bits+BCH 解码尝试（63-bit auto + c3_retry + c2c3联合 + 112-bit），复用已采样曲线。
    //span 重试复用此 lambda：先以 g_min_span 解码，失败再放宽到 0.70 调一次。
    //tag 仅用于日志标注（如 "(span)"）。
    auto try_full_decode = [&](char* code_out, const char* tag) -> int {
        // 长弧 setup 缓存重置：曲线已采样且本调用内固定，重试复用 setup（仅重算 sample）。
        // span_retry 二次调用时 min_span 已变，缓存键自然 miss 重算，此处重置仅为干净起点。
        islii_wave_longarc_cache_reset();
        // 1) 63-bit 自动 c2/c3 极性
        if (try_decode63(-1, -1, -1, -1, code_out) >= 0) {
            ISLII_LOGI("bits_decode(63bit) SUCCESS%s: code=%s", tag, code_out);
            return 1;
        }
        if (islii_get_fast_mode()) return 0;  // fast mode：仅 63-bit auto，跳过后续重试
        // 2) c3 同步极性重试（c2 自动，4 组合，min-err）：救 c3-dominant（c2 自动正确）
        if (g_c3_retry) {
            int best_err = 999, best_c = -1;
            char best_code[20] = {0};
            for (int c = 0; c < 4; c++) {
                char ccode[20] = {0};
                int e = try_decode63(PEAK_COMBOS[c][0], PEAK_COMBOS[c][1], -1, -1, ccode);
                if (e >= 0 && e < best_err) { best_err = e; best_c = c; strcpy(best_code, ccode); }
            }
            if (best_c >= 0) {
                strcpy(code_out, best_code);
                ISLII_LOGI("[c3-retry] rescued%s err=%d: code=%s", tag, best_err, code_out);
                return 1;
            }
        }
        // 2b) c2+c3 联合同步极性重试（16 组合，min-err）：救 c2+c3 dominant（两长弧极性均误，
        //     c3_retry 因 c2 自动仍错而失败）。err=0 时提前退出（不可能更优）。
        if (g_c2_retry) {
            int best_err = 999; char best_code[20] = {0}; int found = 0;
            for (int a = 0; a < 4 && best_err != 0; a++) {
                for (int b = 0; b < 4; b++) {
                    char ccode[20] = {0};
                    int e = try_decode63(PEAK_COMBOS[b][0], PEAK_COMBOS[b][1],
                                         PEAK_COMBOS[a][0], PEAK_COMBOS[a][1], ccode);
                    if (e >= 0 && e < best_err) { best_err = e; strcpy(best_code, ccode); found = 1; }
                    if (best_err == 0) break;
                }
            }
            if (found) {
                strcpy(code_out, best_code);
                ISLII_LOGI("[c2c3-retry] rescued%s err=%d: code=%s", tag, best_err, code_out);
                return 1;
            }
        }
        // 2c) c2+c3 同步位置偏移联合重试（auto 极性）：救同步位锁定到错误相邻极值导致的
        //     整体/子段偏移。cache2 主导失败根因：c2 整体偏移1比特、c3 单同步位偏移；
        //     信号满对比度+跨图确定性，极性重试 +0，故需位置重试。每弧 6 种非零偏移
        //     (单同步±1 + 整体±1)，联合 36 组合，min-err，err==0 提前退出。
        if (g_pos_retry) {
            // c2/c3 极性复位为自动（前序重试已 reset，此处防御性再置）
            islii_set_c2_force_peak(-1, -1);
            islii_set_c3_force_peak(-1, -1);
            static const int SYNC_OFFS[6][2] = { {1,0},{-1,0},{0,1},{0,-1},{1,1},{-1,-1} };
            int best_err = 999; char best_code[20] = {0}; int found = 0;
            for (int a = 0; a < 6 && best_err != 0; a++) {
                for (int b = 0; b < 6; b++) {
                    islii_set_c2_sync_off(SYNC_OFFS[a][0], SYNC_OFFS[a][1]);
                    islii_set_c3_sync_off(SYNC_OFFS[b][0], SYNC_OFFS[b][1]);
                    char ccode[20] = {0};
                    int e = try_decode63(-1, -1, -1, -1, ccode);  // auto 极性 + 位置偏移
                    if (e >= 0 && e < best_err) { best_err = e; strcpy(best_code, ccode); found = 1; }
                    if (best_err == 0) break;
                }
            }
            // 单弧偏移（c2-only 或 c3-only）：36 联合组合要求两弧均非零，漏掉"仅一弧偏移"情形。
            // 诊断(cache2 mode-0-direct sweep)：73 帧仅 c3=(0,-1) 单弧即可修(bch=1, c2 err=0)，
            // 联合搜索强迫 c2 非零偏移破坏 c2 -> 漏救。c2-only 6 + c3-only 6 = 12 新组合，复用
            // 同一 min-err/best_code 与 err<=2 阈值，err==0 提前退出。
            if (g_pos_retry_single && best_err != 0) {
                for (int a = 0; a < 6 && best_err != 0; a++) {  // c2-only (c3=0,0)
                    islii_set_c2_sync_off(SYNC_OFFS[a][0], SYNC_OFFS[a][1]);
                    islii_set_c3_sync_off(0, 0);
                    char ccode[20] = {0};
                    int e = try_decode63(-1, -1, -1, -1, ccode);
                    if (e >= 0 && e < best_err) { best_err = e; strcpy(best_code, ccode); found = 1; }
                }
                for (int b = 0; b < 6 && best_err != 0; b++) {  // c3-only (c2=0,0)
                    islii_set_c2_sync_off(0, 0);
                    islii_set_c3_sync_off(SYNC_OFFS[b][0], SYNC_OFFS[b][1]);
                    char ccode[20] = {0};
                    int e = try_decode63(-1, -1, -1, -1, ccode);
                    if (e >= 0 && e < best_err) { best_err = e; strcpy(best_code, ccode); found = 1; }
                }
            }
            islii_set_c2_sync_off(0, 0);
            islii_set_c3_sync_off(0, 0);
            // 接受阈值收紧到 err<=g_pos_retry_max_err(默认2)：36 组合多重比较下 err<=3 有伪 BCH
            // 可解风险（cache5 68719476735 小盾实测 1 FP，err=3/agree=1，与真实 err=3 案例不可区分）。
            // err<=2：随机词可解概率~1.5e-5/组合，36x1140 期望 FP<1，实测全 cache 0 FP 0 回归。
            // 一致性(agree>=2)无效：每偏移产生不同码字，真实案例亦仅 agree=1。
            if (found && best_err <= g_pos_retry_max_err) {
                strcpy(code_out, best_code);
                ISLII_LOGI("[pos-retry] rescued%s err=%d: code=%s", tag, best_err, code_out);
                return 1;
            }
        }
        // 3) 112-bit 回退（当前 curve）
        ISLII_LOGW("bits_decode(63bit) FAILED%s, trying 112bit", tag);
        unsigned char bits112[112] = {0};   // 零初始化：防 wave 失败时部分填充致非确定性 FP
        unsigned char conf112[112] = {0};
        g_last_wave112_ret = do_wave2bits112(pcurve, curve_len, bits112, g_chase112_enable ? conf112 : 0);
        if (g_last_wave112_ret && bits_decode2(bits112, g_chase112_enable ? conf112 : 0, code_out)) {
            ISLII_LOGI("bits_decode2(112bit) SUCCESS%s: code=%s", tag, code_out);
            return 1;
        }
        return 0;
    };

    //曲线采样 try-both：direct(P2) 失败后用多项式拟合重试（同一 trace，不重追踪）。
    //cache1 实测 +27 解码，零回归零误报。性能：仅重做 curve_sample+BCH（远轻于 trace）。
    int try_list[2] = { g_direct_sample, (g_curve_try_both && g_direct_sample) ? 0 : -1 };
    int n_try = (try_list[1] >= 0) ? 2 : 1;
    ret = 0;
    int last_curve_ok = 0;
    for (int t = 0; t < n_try && !ret; t++) {
        int use_direct = try_list[t];
        STAGE_TIMER_BEGIN(curve);
        int curve_ok = use_direct
            ? do_curve_sample_direct(image, px, py, dot_num, corner_pos, is_clockwise, pcurve, curve_len)
            : do_curve_sample(image, px, py, dot_num, corner_pos, is_clockwise, pcurve, curve_len);
        STAGE_TIMER_END(curve, 3);
        if (!curve_ok) {
            ISLII_LOGE("do_curve_sample FAILED (direct=%d)", use_direct);
            continue;
        }
        last_curve_ok = 1;
        ISLII_LOGI("do_curve_sample OK (direct=%d): curve_len=[%d,%d,%d,%d]",
                   use_direct, curve_len[0], curve_len[1], curve_len[2], curve_len[3]);
        const char* path_tag = use_direct ? "" : "(poly)";

        // 1-3) 63-bit auto + c3_retry + 112-bit（当前 span）
        if (try_full_decode(isli_code, path_tag)) {
            ISLII_LOGI("[summary] mode=%d fw=%.1f dot_num=%d stage=0 OK code=%s%s",
                       trace_mode, frame_size, dot_num, isli_code, path_tag);
            ret = 1;
            break;
        }
        if (islii_get_fast_mode()) break;  // fast mode 跳过重试与 span fallback

        // 4) span 放宽重试：g_min_span 下整条解码失败时，放宽同步跨度到 0.70 重试。
        //    低阈值会移动鲁棒/原始同步切换边界（Wave2Bits.cpp 同步选择），对部分图产生
        //    回归，故仅作 fallback（0.75 优先命中则不触发）。cache1-6 实测 +16 解码，0 FP 0 回归。
        if (g_span_retry && islii_get_min_span() > SPAN_RETRY_FALLBACK) {
            double saved_span = islii_get_min_span();
            islii_set_min_span(SPAN_RETRY_FALLBACK);
            int ok = try_full_decode(isli_code, "(span)");
            islii_set_min_span(saved_span);
            if (ok) {
                ISLII_LOGI("[summary] mode=%d fw=%.1f dot_num=%d stage=0 OK code=%s%s(span)",
                           trace_mode, frame_size, dot_num, isli_code, path_tag);
                ret = 1;
                break;
            }
        }
    }
    if (!ret) {
        if (last_curve_ok) {
            g_last_fail_stage = 5;
            ISLII_LOGI("[summary] mode=%d fw=%.1f dot_num=%d stage=5 BCH_FAIL", trace_mode, frame_size, dot_num);
        } else {
            g_last_fail_stage = 3;
            ISLII_LOGI("[summary] mode=%d fw=%.1f dot_num=%d stage=3 CURVE_FAIL", trace_mode, frame_size, dot_num);
        }
    }
    return ret;
}

//P1 模型解码：trace 完全失败时，用 locate 标记直接推导角点 + P2 直接采样
//无需 trace dots，从模型预测角点线性插值生成合成边框点
static int decode_pipeline_model(IMAGE* image, int x1, int y1, int x2, int y2,
                                  double frame_size, char isli_code[20], short feax[6], short feay[6])
{
    double mid_x = (x1 + x2) * 0.5;
    double mid_y = (y1 + y2) * 0.5;
    //模型预测4角（clamp 到图像边界内）
    double margin = frame_size * 4;
    double xmin = margin, xmax = image->w - 1 - margin;
    double ymin = margin, ymax = image->h - 1 - margin;
    double pcx[4] = { (double)x1, mid_x, (double)x2, mid_x };
    double pcy[4] = { mid_y, mid_y - 3.2 * frame_size, mid_y, mid_y + 25.0 * frame_size };
    for (int i = 0; i < 4; i++) {
        if (pcx[i] < xmin) pcx[i] = xmin; if (pcx[i] > xmax) pcx[i] = xmax;
        if (pcy[i] < ymin) pcy[i] = ymin; if (pcy[i] > ymax) pcy[i] = ymax;
    }
    ISLII_LOGI("[model-decode] predicted corners: C0=(%.0f,%.0f) C1=(%.0f,%.0f) C2=(%.0f,%.0f) C3=(%.0f,%.0f)",
               pcx[0], pcy[0], pcx[1], pcy[1], pcx[2], pcy[2], pcx[3], pcy[3]);

    double* px = g_pool->px;
    double* py = g_pool->py;
    //在4角之间线性插值生成合成边框点（每边~40点，足够直接采样用）
    int pts_per_edge = 40;
    int total_pts = pts_per_edge * 4;
    for (int edge = 0; edge < 4; edge++) {
        int i0 = edge, i1 = (edge + 1) % 4;
        for (int j = 0; j < pts_per_edge; j++) {
            double t = (double)j / pts_per_edge;
            int idx = edge * pts_per_edge + j;
            px[idx] = pcx[i0] + t * (pcx[i1] - pcx[i0]);
            py[idx] = pcy[i0] + t * (pcy[i1] - pcy[i0]);
        }
    }

    int corner_pos[4] = { 0, pts_per_edge, pts_per_edge * 2, pts_per_edge * 3 };
    int is_clockwise = 1;
    for (int i = 0; i < 4; i++) {
        feax[i] = (short)(pcx[i] + 0.5);
        feay[i] = (short)(pcy[i] + 0.5);
    }

    //直接采样 + 解码
    int one_curve_len = max_curve_length();
    unsigned char* curve_buffer = g_pool->curve_buf;
    unsigned char* pcurve[4] = { 0 };
    int curve_len[4] = { 0 };
    for (int i = 0; i < 4; i++) {
        pcurve[i] = curve_buffer + i * one_curve_len;
        curve_len[i] = one_curve_len;
    }

    if (!do_curve_sample_direct(image, px, py, total_pts, corner_pos, is_clockwise, pcurve, curve_len)) {
        ISLII_LOGE("[model-decode] curve_sample_direct FAILED");
        g_last_fail_stage = 3;
        return 0;
    }
    ISLII_LOGI("[model-decode] curve OK: len=[%d,%d,%d,%d]", curve_len[0], curve_len[1], curve_len[2], curve_len[3]);

    // 模型路径重新采样了曲线（与主路径不同的曲线内容，复用同一 g_pool 缓冲区），
    // 必须清空长弧 setup 缓存，否则可能命中上一帧主路径留下的同键陈旧 setup。
    islii_wave_longarc_cache_reset();

    unsigned char bits[112] = {0};   // 零初始化：防 wave 失败时部分填充致非确定性 FP
    unsigned char conf63[64]={0}, conf112[112]={0};
    //span 重试：先 g_min_span，失败放宽到 0.70（fallback，零回归）
    double span_list[2] = { islii_get_min_span(), (g_span_retry && islii_get_min_span() > SPAN_RETRY_FALLBACK) ? SPAN_RETRY_FALLBACK : islii_get_min_span() };
    int n_span = (g_span_retry && islii_get_min_span() > SPAN_RETRY_FALLBACK) ? 2 : 1;
    for (int si = 0; si < n_span; si++) {
        islii_set_min_span(span_list[si]);
        const char* stag = (si > 0) ? "(span)" : "";
        g_last_wave63_ret = do_wave2bits63(pcurve, curve_len, bits, g_chase_enable ? conf63 : 0);
        memcpy(g_last_bits63_raw, bits, 63);
        if (g_last_wave63_ret && bits_decode(bits, g_chase_enable ? conf63 : 0, isli_code)) {
            ISLII_LOGI("[model-decode] 63bit SUCCESS%s: code=%s", stag, isli_code);
            ISLII_LOGI("[summary] mode=model fw=%.1f stage=0 OK code=%s%s", frame_size, isli_code, stag);
            islii_set_min_span(span_list[0]);
            return 1;
        }
        g_last_wave112_ret = do_wave2bits112(pcurve, curve_len, bits, g_chase112_enable ? conf112 : 0);
        if (g_last_wave112_ret && bits_decode2(bits, g_chase112_enable ? conf112 : 0, isli_code)) {
            ISLII_LOGI("[model-decode] 112bit SUCCESS%s: code=%s", stag, isli_code);
            ISLII_LOGI("[summary] mode=model fw=%.1f stage=0 OK code=%s%s(112)", frame_size, isli_code, stag);
            islii_set_min_span(span_list[0]);
            return 1;
        }
    }
    islii_set_min_span(span_list[0]);
    ISLII_LOGE("[model-decode] BCH FAILED");
    g_last_fail_stage = 5;
    ISLII_LOGI("[summary] mode=model fw=%.1f stage=5 BCH_FAIL", frame_size);
    return 0;
}

int isli_icon_decoder_do_image_decode(IMAGE* image, char isli_code[20], short feax[6], short feay[6])
{
    g_last_fail_stage = 0;
    g_last_bch_err63 = -1;
    g_last_bch_err112 = -1;
    g_last_wave63_ret = 0;
    g_last_wave112_ret = 0;
    g_last_dot_num = 0;
    memset(g_last_received63, 0, 9);
    memset(g_last_received112, 0, 17);
    memset(g_last_bits63_raw, 0, 63);

    if (0 == __bch_ctrl63){
        ISLII_LOGE("BCH table not initialized");
        return 0;
    }

    if (!g_pool) {
        ISLII_LOGE("Memory pool not initialized");
        return 0;
    }

    ISLII_LOGI("Image: w=%d h=%d bpl=%d", image->w, image->h, image->bpl);

    //定位isli icon
    int x1, y1, x2, y2;
    double frame_size; //for debug
    int ret = do_isliicon_locating(image, &x1, &y1, &x2, &y2, &frame_size);
    if (!ret){
        ISLII_LOGE("do_isliicon_locating FAILED — no ISLI icon found in image");
        g_last_fail_stage = 1;
        ISLII_LOGI("[frame] LOCATE_FAIL");
        return 0;
    }
    ISLII_LOGI("do_isliicon_locating OK: box=(%d,%d)-(%d,%d) frame_size=%.1f",
              x1, y1, x2, y2, frame_size);
#if REMOTE_DRAW
    __canvas.DrawLine("source", "color=0xff", (short)x1, (short)y1, (short)x2, (short)y2);
#endif
    feax[4] = (short)x1;
    feay[4] = (short)y1;
    feax[5] = (short)x2;
    feay[5] = (short)y2;

    //Try-both 策略：先用原始质心追踪(mode 0)；失败再按需重试。
    //性能优化：满周长 trace(dot>=140)跳过 mode2/3——角点跳跃不会改善已完整追踪的边框
    //Try-both 策略：mode 0->2->3->model。封装为 lambda 以支持 poly 回退。
    if (g_trace_fallback && !islii_get_fast_mode()) {
        struct TryModes {
            static int run(IMAGE* image, int x1, int y1, int x2, int y2, double frame_size,
                           char isli_code[20], short feax[6], short feay[6]) {
                ISLII_LOGI("decode attempt 1: centroid trace (mode 0)");
                if (decode_pipeline(image, x1, y1, x2, y2, frame_size, 0, isli_code, feax, feay)) {
                    ISLII_LOGI("[frame] OK path=mode0"); return 1;
                }
                int prog0 = islii_get_last_trace_progress();
                int min_progress = (int)(frame_size * 3.5);
                if (min_progress > 60) min_progress = 60;
                if (min_progress < 25) min_progress = 25;
                if (prog0 >= 140) { ISLII_LOGI("[frame] FULL_TRACE progress=%d, skip mode2/3", prog0); return 0; }
                if (prog0 < min_progress) {
                    ISLII_LOGI("[frame] SKIP progress=%d < %d (fw=%.1f)", prog0, min_progress, frame_size);
                    if (g_model_corners && decode_pipeline_model(image, x1, y1, x2, y2, frame_size, isli_code, feax, feay)) {
                        ISLII_LOGI("[frame] OK path=model(skip)"); return 1;
                    }
                    return 0;
                }
                ISLII_LOGI("decode attempt 2: stage-3 corner-jump trace (mode 2)");
                if (decode_pipeline(image, x1, y1, x2, y2, frame_size, 2, isli_code, feax, feay)) { ISLII_LOGI("[frame] OK path=mode2"); return 1; }
                ISLII_LOGI("decode attempt 3: reverse-start trace (mode 3, pos2->pos1)");
                if (decode_pipeline(image, x2, y2, x1, y1, frame_size, 2, isli_code, feax, feay)) { ISLII_LOGI("[frame] OK path=mode3"); return 1; }
                ISLII_LOGI("[frame] ALL3_FAIL fw=%.1f", frame_size);
                if (g_model_corners && decode_pipeline_model(image, x1, y1, x2, y2, frame_size, isli_code, feax, feay)) {
                    ISLII_LOGI("[frame] OK path=model"); return 1;
                }
                return 0;
            }
        };
        if (TryModes::run(image, x1, y1, x2, y2, frame_size, isli_code, feax, feay)) return 1;
        //poly 回退已在 decode_pipeline 内部完成（同一 trace 上 try direct->poly，无需重追踪）
        return 0;
    }

        //A/B 隔离模式：只用预设 trace 模式跑一次
    return decode_pipeline(image, x1, y1, x2, y2, frame_size, islii_get_trace_mode(), isli_code, feax, feay);
}

