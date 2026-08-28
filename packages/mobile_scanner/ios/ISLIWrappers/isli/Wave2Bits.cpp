#include "Wave2Bits.h"
#include "Filter.h"
#include "DecoderMemoryPool.h"
#include "IldLog.h"
#include <memory.h>
#include <stdio.h>

// 诊断 dump 开关
static int g_dump_wave = 0;
static const char* g_dump_dir = 0;
static int g_dump_counter = 0;
void islii_set_dump_wave(int enable, const char* dir) {
    g_dump_wave = enable;
    g_dump_dir = dir;
    g_dump_counter = 0;
}

// c3 长弧同步极性强制（BCH 校验重试用）：
//  -1 = 自动检测（默认，shipped 行为）
//   0 = 强制谷，1 = 强制峰
// 当自动检测的 is_peak 被相邻数据位污染出错时，pipeline 用强制极性重试，
// 由 BCH 校验裁决正确极性（c0/c1/c2 正确时，错误极性 err>5，正确极性 err<=3）。
static int g_c3_force_peak1 = -1;
static int g_c3_force_peak2 = -1;
void islii_set_c3_force_peak(int p1, int p2) { g_c3_force_peak1 = p1; g_c3_force_peak2 = p2; }
// c2 长弧同步极性强制（诊断用，同 c3）
static int g_c2_force_peak1 = -1;
static int g_c2_force_peak2 = -1;
void islii_set_c2_force_peak(int p1, int p2) { g_c2_force_peak1 = p1; g_c2_force_peak2 = p2; }

// 长弧同步位置偏移（单位：比特，×sample_per_bit 转为样本）。
// 诊断发现 cache2 c2/c3 主导失败根因是同步位置错位：c2 整体偏移 1 比特（got==exp>>1），
// c3 单个同步位错位使一个子段偏移。force_peak 只改极性不改位置，故无法救援。
// 此偏移在 match_sync_pos + 一致性校验之后施加，用于重试不同的相邻同步位置。
// 0=不偏移(默认), ±1=偏移到相邻比特的峰/谷。
static int g_c2_sync1_off = 0, g_c2_sync2_off = 0;
static int g_c3_sync1_off = 0, g_c3_sync2_off = 0;
void islii_set_c2_sync_off(int o1, int o2) { g_c2_sync1_off = o1; g_c2_sync2_off = o2; }
void islii_set_c3_sync_off(int o1, int o2) { g_c3_sync1_off = o1; g_c3_sync2_off = o2; }
void islii_get_c2_sync_off(int* o1, int* o2) { *o1 = g_c2_sync1_off; *o2 = g_c2_sync2_off; }
void islii_get_c3_sync_off(int* o1, int* o2) { *o1 = g_c3_sync1_off; *o2 = g_c3_sync2_off; }

// 同步跨度阈值（默认 0.75）：wave2bits 接受 (e-s)/len > g_min_span 的波形。
// 诊断用：可放宽到 0.70/0.65 测量边界波形（span 刚好 <0.75）的解码潜力。
static double g_min_span = 0.75;
int g_wave_bitth_used = 0;
void islii_set_min_span(double v) { g_min_span = (v < 0.3) ? 0.3 : (v > 0.9 ? 0.9 : v); }
double islii_get_min_span(void) { return g_min_span; }

//==== 长弧 setup 缓存（重试去冗余）====
// 性能剖析：wave 阶段占 58%（~1435us/img），其中单次 wave2bits63_2 仅 ~22us，
// 余下全部是 57 次重试（auto 1 + c3_retry 4 + c2_retry 16 + pos_retry 36）重复计算。
// 重试只改 force_peak（极性）或 sync_off（采样相位），不影响 trim/match_sync_pos/th/二值化。
// 故把 wave2bits63_2 拆为 setup（trim+match+rectify+th+子段 s/e，与重试参数无关）与
// sample（比特中心采样循环，受 phase_off 影响）。setup 按 (force_peak1,force_peak2) 缓存，
// 5 种极性组合（auto + 4 PEAK_COMBOS）各一槽，2 条长弧(c2/c3)共 10 槽。
// 每次解码前 reset；缓存键含 g_min_span（span_retry 改阈值时自然 miss 重算）。
// bit-exact：setup 与 sample 拆自原 wave2bits 同一段代码，wave2bits 仍调用 setup+sample。
struct LongArcSubSetup {
    const unsigned char* wave;  // 子段波形基址
    int len;                     // 子段长度
    int s, e;                    // 同步游程起止（二值化+检测所得）
    int th0, th1;                // 子段两端阈值（线性斜坡）
    int bit_num;                 // 子段比特数（9/8/11）
    int ok;                      // span 检查通过
};
struct LongArcCache {
    int valid;
    int force_peak1, force_peak2;  // 键：极性组合
    double min_span;               // 键：跨度阈值（span_retry 时变化）
    LongArcSubSetup sub[3];        // 3 个子段
};
static LongArcCache g_longarc_cache[2][5];  // [curve 0=c2/1=c3][slot]
void islii_wave_longarc_cache_reset(void) {
    for (int c = 0; c < 2; c++)
        for (int s = 0; s < 5; s++)
            g_longarc_cache[c][s].valid = 0;
}
// 极性组合 -> 槽号：auto(-1,-1)=0, (0,0)=1, (1,0)=2, (0,1)=3, (1,1)=4。-1=不可缓存。
static int longarc_slot(int fp1, int fp2) {
    if (fp1 < 0 && fp2 < 0) return 0;
    if (fp1 == 0 && fp2 == 0) return 1;
    if (fp1 == 1 && fp2 == 0) return 2;
    if (fp1 == 0 && fp2 == 1) return 3;
    if (fp1 == 1 && fp2 == 1) return 4;
    return -1;
}


#define REMOTE_DRAW 0
#if REMOTE_DRAW
#include "canvas.h"
#include <QDebug>
#endif


static const int mean_of_peak2vally(unsigned char* wave, int len)
{
    int ret = 0;
    int min_v = 256;
    int max_v = 0;

    for (int i = 0; i < len; i++){
        if (wave[i] < min_v)
            min_v = wave[i];
        else if (wave[i] > max_v) {
            max_v = wave[i];
        }
    }

    ret = (min_v + max_v) / 2;

    return ret;
}

//向前查找第一个长度 >= min_run 的目标值游程（want_light=1 找亮游程，0 找暗游程），
//返回该游程结束位置（下一个非目标值的位置）。
//若无合格游程，回退到第一个游程的结束位置（保持原始行为，避免低对比度回归）。
//用途：跳过起点的短瞬态毛刺，锁定真正的同步位游程。
static int find_first_run_fwd(const unsigned char* bin, int len, int start, int want_light, int min_run)
{
    int p = start;
    int first_end = -1;
    while (p < len) {
        if (want_light) { while (p < len && 0 == bin[p]) p++; }
        else            { while (p < len && bin[p]) p++; }
        if (p >= len) break;
        int rs = p;
        if (want_light) { while (p < len && bin[p]) p++; }
        else            { while (p < len && 0 == bin[p]) p++; }
        if (first_end < 0) first_end = p;
        if (p - rs >= min_run) return p;
    }
    return (first_end >= 0) ? first_end : start;
}

//向后查找第一个长度 >= min_run 的目标值游程，返回该游程起始位置前一个采样
//（即数据区末尾，匹配原始 e 语义）。无合格游程则回退到最后一个游程。
static int find_last_run_bwd(const unsigned char* bin, int len, int end, int want_light, int min_run)
{
    int p = end;
    int first_pos = -1;
    while (p > 0) {
        if (want_light) { while (p > 0 && 0 == bin[p]) p--; }
        else            { while (p > 0 && bin[p]) p--; }
        if (p <= 0) break;
        int re = p;
        if (want_light) { while (p > 0 && bin[p]) p--; }
        else            { while (p > 0 && 0 == bin[p]) p--; }
        if (first_pos < 0) first_pos = p;
        if (re - p >= min_run) return p;
    }
    return (first_pos >= 0) ? first_pos : end;
}

// wave2bits 的 setup 部分：二值化 + 同步游程检测 + 跨度检查。与 phase_off/bit_th 无关，
// 仅依赖 (wave, len, sign0/1, th0/1, bit_num, g_min_span)。重试时这些不变即可命中缓存。
// 输出 s,e（同步游程起止）。返回 1=跨度合格，0=不合格。代码逐行取自原 wave2bits。
static int wave2bits_setup(const unsigned char* wave, int len,
    int sign_of_sync0, int th0, int sign_of_sync1, int th1,
    int bit_num, int* s_out, int* e_out)
{
    unsigned char* bin = g_pool ? g_pool->wave_bin : new unsigned char[(size_t)len];
    memset(bin, 0, (size_t)len);
    double det_t = (double)(th1 - th0) / len;
    double t = th0;
    for (int i = 0; i < len; i++){
        if (wave[i] > t) { bin[i] = 0xff; }
        t += det_t;
    }

    int min_run = (int)((double)len / (bit_num + 2) * 0.4 + 0.5);
    if (min_run < 2) min_run = 2;

    int s_robust = find_first_run_fwd(bin, len, 0, sign_of_sync0 > 0, min_run);
    int e_robust = find_last_run_bwd(bin, len, len - 1, sign_of_sync1 > 0, min_run);

    int s_orig = 0;
    if (sign_of_sync0 > 0) {
        while (0 == bin[s_orig] && s_orig < len) s_orig++;
        while (bin[s_orig] && s_orig < len) s_orig++;
    } else {
        while (bin[s_orig] && s_orig < len) s_orig++;
        while (0 == bin[s_orig] && s_orig < len) s_orig++;
    }
    int e_orig = len - 1;
    if (sign_of_sync1 > 0) {
        while (0 == bin[e_orig] && e_orig > 0) e_orig--;
        while (bin[e_orig] && e_orig > 0) e_orig--;
    } else {
        while (bin[e_orig] && e_orig > 0) e_orig--;
        while (0 == bin[e_orig] && e_orig > 0) e_orig--;
    }

    int s, e;
    if ((double)(e_robust - s_robust) / (double)len > g_min_span) {
        s = s_robust; e = e_robust;
    } else {
        s = s_orig; e = e_orig;
    }

    if (!g_pool) delete[] bin;
    *s_out = s; *e_out = e;
    return (((double)(e - s) / (double)len) > g_min_span) ? 1 : 0;
}

// wave2bits 的 sample 部分：比特中心亚像素采样 + 阈值判决。受 phase_off 影响（重试参数）。
// setup 已保证 s,e 跨度合格。bit_th>=0 时用固定阈值，否则用线性斜坡 th0+th_step*dp。
static void wave2bits_sample(const unsigned char* wave, int len,
    int s, int e, int th0, int th1, int bit_num,
    unsigned char bits[], unsigned char* conf, int bit_th, double phase_off)
{
    double det = (double)(e - s) / bit_num;
    double th_step = (double)(th1 - th0) / len;
    for (int i = 0; i < bit_num; i++){
        //亚像素比特采样：线性插值波形值，消除整数网格偏移造成的系统性错误
        //phase_off：比特采样相位偏移（单位：比特），用于同步位置重试时平移整段比特中心
        double dp = s + 0.5 * det + i * det + phase_off * det;
        int p = (int)(dp + 0.5);
        if (p < 0) p = 0; else if (p >= len) p = len - 1;
        double frac = dp - p;
        double wv = wave[p];
        if (frac > 0 && p + 1 < len) wv += frac * (wave[p+1] - wave[p]);
        else if (frac < 0 && p > 0) wv += frac * (wave[p] - wave[p-1]);
        double th_p = (bit_th >= 0) ? (double)bit_th : (th0 + th_step * dp);
        bits[i] = (wv > th_p) ? 0xFF : 0;
        if (conf) {
            int d = (int)(wv > th_p ? wv - th_p : th_p - wv);
            conf[i] = (unsigned char)(d < 255 ? d : 255);
        }
    }
}

static const int wave2bits(unsigned char* wave, int len,
    int sign_of_sync0, int th0,
    int sign_of_sync1, int th1,
    int bit_num, unsigned char bits[],
    unsigned char* conf,     //NULL=skip, else confidence[bit_num] (0=low,255=high)
    const char* graph_name, int offset, int bit_th = -1, double phase_off = 0.0)
{
    graph_name = graph_name, offset = offset;

    int s, e;
    int ok = wave2bits_setup(wave, len, sign_of_sync0, th0, sign_of_sync1, th1, bit_num, &s, &e);
    if (!ok) {
        // 诊断 dump：失败也记录波形（跨度<75%），便于分析低对比度/退化波形
        if (g_dump_wave && g_dump_dir) {
            char path[512];
            int n = ++g_dump_counter;
            sprintf(path, "%s/wave_%d_%s_FAIL.csv", g_dump_dir, n, graph_name);
            FILE* f = fopen(path, "w");
            if (f) {
                fprintf(f, "# FAIL len=%d th0=%d th1=%d s=%d e=%d bit_num=%d sign0=%d sign1=%d span=%.2f\n",
                        len, th0, th1, s, e, bit_num, sign_of_sync0, sign_of_sync1, (double)(e-s)/(double)len);
                int mn=255, mx=0; long sm=0;
                for (int i = 0; i < len; i++) { if (wave[i]<mn) mn=wave[i]; if (wave[i]>mx) mx=wave[i]; sm+=wave[i]; }
                fprintf(f, "# wave stats: min=%d max=%d mean=%d contrast=%d\n", mn, mx, (int)(sm/len), mx-mn);
                for (int i = 0; i < len; i++) fprintf(f, "%d,%d\n", i, wave[i]);
                fclose(f);
            }
        }
        return 0;
    }

    wave2bits_sample(wave, len, s, e, th0, th1, bit_num, bits, conf, bit_th, phase_off);

    // 诊断 dump
    if (g_dump_wave && g_dump_dir) {
        double det = (double)(e - s) / bit_num;
        double th_step = (double)(th1 - th0) / len;
        char path[512];
        int n = ++g_dump_counter;
        sprintf(path, "%s/wave_%d_%s.csv", g_dump_dir, n, graph_name);
        FILE* f = fopen(path, "w");
        if (f) {
            fprintf(f, "# len=%d th0=%d th1=%d s=%d e=%d det=%.3f bit_num=%d sign0=%d sign1=%d\n",
                    len, th0, th1, s, e, det, bit_num, sign_of_sync0, sign_of_sync1);
            fprintf(f, "idx,wave,th_ramp,bit_pos\n");
            for (int i = 0; i < len; i++) {
                double th_p = th0 + th_step * i;
                fprintf(f, "%d,%d,%.1f,", i, wave[i], th_p);
                // which bit does this sample belong to (if any)
                int bn = -1;
                for (int b = 0; b < bit_num; b++) {
                    double dp = s + 0.5 * det + b * det;
                    if (i == (int)(dp + 0.5)) { bn = b; break; }
                }
                fprintf(f, "%d\n", bn);
            }
            fprintf(f, "# bits:");
            for (int b = 0; b < bit_num; b++) fprintf(f, " %d", bits[b] ? 1 : 0);
            fprintf(f, "\n");
            fclose(f);
        }
    }

    return 1;
}

//短弧的参数：共12个数据位，去掉头尾的同步位后剩余10个数据位
int wave2bits63_1(unsigned char* wave, int len, unsigned char out[8], unsigned char* conf, const char* graph_name)
{
    int ret = 0;
    //头部均值、尾部均值
    int sync_len = (len * 2 + 6) / 12;
    int th0 = mean_of_peak2vally(wave, sync_len);
    int th1 = mean_of_peak2vally(wave + len - sync_len, sync_len);

    //双阈值：sync 检测用原始头尾阈值（分离 corner 过渡区与亮模块），
    //bit 提取用百分位阈值（分离暗 22 与亮 76）。白底 corner 过渡区（103-160）比亮模块（76）
    //更亮，原始阈值（~118）将过渡区判亮、亮模块判暗 -> sync 正确但 bit 错。
    //百分位（~49）将亮模块判亮 -> bit 正确，但使过渡区也判亮 -> sync 错。
    //双阈值分离：sync 用原始阈值，bit 用百分位 -> 两者都正确，无需 Chase，0 FP。
    int bit_th = -1;
    {
        int h_min = 255;
        for (int i = 0; i < sync_len; i++) if (wave[i] < h_min) h_min = wave[i];
        int t_min = 255;
        for (int i = len - sync_len; i < len; i++) if (wave[i] < t_min) t_min = wave[i];
        if ((h_min > 50 && th0 > 80) || (t_min > 50 && th1 > 80)) {
            int hist[256] = {0};
            for (int i = 0; i < len; i++) hist[wave[i]]++;
            int cum = 0, p25 = 0, p75 = 0;
            for (int v = 0; v < 256; v++) {
                cum += hist[v];
                if (!p25 && cum * 4 >= len) p25 = v;
                if (!p75 && cum * 4 >= 3 * len) p75 = v;
            }
            if (p25 > 0 && p75 > p25) { bit_th = (p25 + p75) / 2; g_wave_bitth_used = 1; }
        }
    }

    unsigned char bits[10];

    unsigned char conf10[10];
    if (wave2bits(wave, len, +1, th0, +1, th1, 10, bits, conf ? conf10 : 0, graph_name, 0, bit_th)){
        memcpy(out, bits + 1, 8);
        if (conf) memcpy(conf, conf10 + 1, 8);
        ret = 1;
    }

    return ret;
}

//匹配长弧中的同步位
//force_peak: -1=自动检测极性(默认), 0=强制谷, 1=强制峰
//BCH 校验重试时用强制极性覆盖自动检测，避免相邻数据位污染极性判断。
static int match_sync_pos(unsigned char* wave, int len, int sync_pos, int sample_per_bit, int* is_peak, int force_peak, const char* graph_name)
{
    graph_name = graph_name; //消除编译警告
    len = len;

    int s0 = sync_pos - sample_per_bit * 2;
    int s1 = s0 + sample_per_bit * 2;
    int* score = g_pool ? g_pool->wave_score : new int[(size_t)(sample_per_bit * 2)];

#if REMOTE_DRAW
    __canvas.DrawLine(graph_name, "color=0xff", sync_pos, 128, sync_pos, 256);
#endif

    for (int i = s0; i < s1; i++){
        int sum = 0;
        for (int j = 0; j < sample_per_bit; j++) {
            sum += wave[i + j];
        }
        score[i - s0] = sum;
    }

    int auto_peak = ((score[0] + score[sample_per_bit - 1]) / 2 < score[sample_per_bit/2]) ? 1 : 0;
    int use_peak = (force_peak >= 0) ? force_peak : auto_peak;

    if (use_peak) {
        int max_v = score[0];
        int max_p = 0;
        for (int i = 1; i < s1 - s0; i++) {
            if (score[i] > max_v) {
                max_v = score[i];
                max_p = i;
            }
        }
        sync_pos = s0 + max_p + int(0.5*sample_per_bit + 0.5);
        *is_peak = 1;
    }
    else {
        int min_v = score[0];
        int min_p = 0;
        for (int i = 1; i < s1 - s0; i++) {
            if (score[i] < min_v) {
                min_v = score[i];
                min_p = i;
            }
        }
        sync_pos = s0 + min_p + int(0.5*sample_per_bit + 0.5);
        *is_peak = 0;
    }
    if (!g_pool) delete[] score;

#if REMOTE_DRAW
    __canvas.DrawLine(graph_name, "color=0x7f7f00", sync_pos, 128, sync_pos, 256);
#endif

    return sync_pos;
}

static int match_sync_010(unsigned char* wave, int sync_pos, int sample_per_bit, const char* graph_name)
{
    graph_name = graph_name; //消除编译警告

    int s0 = sync_pos - sample_per_bit * 2;
    int s1 = s0 + sample_per_bit * 2;
    int* score = g_pool ? g_pool->wave_score : new int[(size_t)(sample_per_bit * 2)];

#if REMOTE_DRAW
    __canvas.DrawLine(graph_name, "color=0xff", sync_pos, 128, sync_pos, 256);
#endif

    for (int i = s0; i < s1; i++){
        int sum = 0;
        for (int j = 0; j < sample_per_bit; j++) {
            sum += wave[i + j];
        }
        score[i - s0] = sum;
    }

    int max_v = score[0];
    int max_p = 0;
    for (int i = 1; i < s1 - s0; i++) {
        if (score[i] > max_v) {
            max_v = score[i];
            max_p = i;
        }
    }
    sync_pos = s0 + max_p + int(0.5*sample_per_bit + 0.5);
#if REMOTE_DRAW
    __canvas.DrawLine(graph_name, "color=0x7f7f00", sync_pos, 128, sync_pos, 256);
#endif
    if (!g_pool) delete[] score;

    return sync_pos;
}

//去掉长弧的头尾
static void trim_head_tail(unsigned char* wave, int len, double sample_per_bit, int* head_len, int* tail_len, const char* graph_name)
{
    graph_name = graph_name;
    int spb = (int)(sample_per_bit + 0.5);
    int spb2 = (int)(sample_per_bit*2 + 0.5);
    int th0 = mean_of_peak2vally(wave, spb2);
    int k = 0;
    while ((wave[k] < th0) && (k < spb)) k++;
    *head_len = k;

    int th1 = mean_of_peak2vally(wave + len - 1 - spb2, spb2);
    k = len - 1;
    while ((wave[k] < th1) && (k > len - spb)) k--;
    *tail_len = len - 1 - k;

#if REMOTE_DRAW
    __canvas.DrawLine(graph_name, "color=0xff", *head_len - 1, 128, *head_len - 1, 256);
    __canvas.DrawLine(graph_name, "color=0xff", len - 1 - *tail_len, 128, len - 1 - *tail_len, 256);
#endif
}

//计算同步标记的得分
static int sync_score(unsigned char*wave, int sync_pos, int sample_per_bit)
{
    int r = sample_per_bit / 2;
    int score = 0;

    int v = wave[sync_pos];
    for (int i = 1; i <= r; i++){
        score += (v - wave[sync_pos - r]);
        score += (v - wave[sync_pos + r]);
    }

    return (score < 0 ? -score : score);
}

static int rectify_sync_pos(unsigned char* wave, int sync_pos, int sample_per_bit, int is_peak)
{
    int s0 = sync_pos - sample_per_bit * 2;
    int s1 = s0 + sample_per_bit * 2;
    int* score = g_pool ? g_pool->wave_score : new int[(size_t)(sample_per_bit * 2)];

    for (int i = s0; i < s1; i++){
        int sum = 0;
        for (int j = 0; j < sample_per_bit; j++) {
            sum += wave[i + j];
        }
        score[i - s0] = sum;
    }

    if (is_peak) {
        int max_v = score[0];
        int max_p = 0;
        for (int i = 1; i < s1 - s0; i++) {
            if (score[i] > max_v) {
                max_v = score[i];
                max_p = i;
            }
        }
        sync_pos = s0 + max_p + int(0.5*sample_per_bit + 0.5);
    }
    else {
        int min_v = score[0];
        int min_p = 0;
        for (int i = 1; i < s1 - s0; i++) {
            if (score[i] < min_v) {
                min_v = score[i];
                min_p = i;
            }
        }
        sync_pos = s0 + min_p + int(0.5*sample_per_bit + 0.5);
    }
    if (!g_pool) delete[] score;

    return sync_pos;
}

static int wave2bits63_2(unsigned char* wave, int len, unsigned char out[24], unsigned char* conf, const char* graph_name,
                         int force_peak1 = -1, int force_peak2 = -1,
                         int sync1_off = 0, int sync2_off = 0, int cache_id = 0)
{
    // 诊断模式：走原始未缓存路径（保留逐子段 dump CSV 输出，便于排查）。
    if (g_dump_wave) {
        int head_len = 0, tail_len = 0;
        trim_head_tail(wave, len, len / 32.0, &head_len, &tail_len, graph_name);
        int real_len = len - head_len - tail_len;
        int sync_pos1 = head_len + int(10.5 / 32 * real_len + 0.5);
        int sync_pos2 = head_len + int(19.5 / 32 * real_len + 0.5);
        int sample_per_bit = (real_len + 16) / 32;
        int is_peak1 = 0, is_peak2 = 0;
        int new_pos1 = match_sync_pos(wave, len, sync_pos1, sample_per_bit, &is_peak1, force_peak1, graph_name);
        int new_pos2 = match_sync_pos(wave, len, sync_pos2, sample_per_bit, &is_peak2, force_peak2, graph_name);
        {
            int shift = (new_pos1 - sync_pos1) - (new_pos2 - sync_pos2);
            if (shift < sample_per_bit / 2){ sync_pos1 = new_pos1; sync_pos2 = new_pos2; }
            else {
                int sync_score1 = sync_score(wave, new_pos1, sample_per_bit);
                int sync_score2 = sync_score(wave, new_pos2, sample_per_bit);
                if (sync_score1 > sync_score2){ sync_pos1 = new_pos1; sync_pos2 = rectify_sync_pos(wave, sync_pos2, sample_per_bit, !is_peak2); is_peak2 = !is_peak2; }
                else{ sync_pos1 = rectify_sync_pos(wave, sync_pos1, sample_per_bit, !is_peak1); is_peak1 = !is_peak1; sync_pos2 = new_pos2; }
            }
        }
        double ph1 = (double)sync1_off;
        double ph2 = (sync1_off + sync2_off) * 0.5;
        double ph3 = (double)sync2_off;
        int th0 = mean_of_peak2vally(wave, sample_per_bit * 2);
        int th1 = mean_of_peak2vally(wave + sync_pos1 - sample_per_bit, sample_per_bit * 2);
        int th2 = mean_of_peak2vally(wave + sync_pos2 - sample_per_bit, sample_per_bit * 2);
        int th3 = mean_of_peak2vally(wave + (len - 1 - sample_per_bit * 2), sample_per_bit * 2);
        unsigned char bits[12]; unsigned char ctmp[12];
        int ret = 1;
        ret &= wave2bits(wave, sync_pos1, +1, th0, is_peak1, th1, 9, bits, conf ? ctmp : 0, graph_name, 0, -1, ph1);
        memcpy(out, bits + 1, 8); if (conf) memcpy(conf, ctmp + 1, 8);
        ret &= wave2bits(wave + sync_pos1, sync_pos2 - sync_pos1, is_peak1, th1, is_peak2, th2, 8, bits, conf ? ctmp : 0, graph_name, sync_pos1, -1, ph2);
        memcpy(out + 8, bits + 1, 7); if (conf) memcpy(conf + 8, ctmp + 1, 7);
        ret &= wave2bits(wave + sync_pos2, len - sync_pos2, is_peak2, th2, +1, th3, 11, bits, conf ? ctmp : 0, graph_name, sync_pos2, -1, ph3);
        memcpy(out + 15, bits + 1, 9); if (conf) memcpy(conf + 15, ctmp + 1, 9);
        return ret;
    }

    // 生产路径：setup 按 (force_peak1,force_peak2,min_span) 缓存，重试只重算 sample。
    // 重试（c3_retry/c2_retry/pos_retry）只改 force_peak 或 sync_off，不影响 trim/match_sync_pos/
    // rectify/th/二值化/s/e。故 setup 命中缓存后跳过，仅重跑 3 段比特采样循环（~30 次运算）。
    int slot = longarc_slot(force_peak1, force_peak2);
    LongArcCache local_cs;  // slot<0（理论不发生）时用，不跨调用复用
    LongArcCache* cs;
    if (slot >= 0) {
        cs = &g_longarc_cache[cache_id][slot];
    } else {
        local_cs.valid = 0;  // 强制 miss：setup 算入 local，不跨调用复用
        cs = &local_cs;
    }
    if (!cs->valid || cs->force_peak1 != force_peak1 || cs->force_peak2 != force_peak2 || cs->min_span != g_min_span) {
        // ---- setup（与 sync_off/phase 无关，可缓存）----
        int head_len = 0, tail_len = 0;
        trim_head_tail(wave, len, len / 32.0, &head_len, &tail_len, graph_name);
        int real_len = len - head_len - tail_len;
        int sync_pos1 = head_len + int(10.5 / 32 * real_len + 0.5);
        int sync_pos2 = head_len + int(19.5 / 32 * real_len + 0.5);
        int sample_per_bit = (real_len + 16) / 32;
        int is_peak1 = 0, is_peak2 = 0;
        int new_pos1 = match_sync_pos(wave, len, sync_pos1, sample_per_bit, &is_peak1, force_peak1, graph_name);
        int new_pos2 = match_sync_pos(wave, len, sync_pos2, sample_per_bit, &is_peak2, force_peak2, graph_name);
        {
            int shift = (new_pos1 - sync_pos1) - (new_pos2 - sync_pos2);
            if (shift < sample_per_bit / 2){ sync_pos1 = new_pos1; sync_pos2 = new_pos2; }
            else {
                int sync_score1 = sync_score(wave, new_pos1, sample_per_bit);
                int sync_score2 = sync_score(wave, new_pos2, sample_per_bit);
                if (sync_score1 > sync_score2){ sync_pos1 = new_pos1; sync_pos2 = rectify_sync_pos(wave, sync_pos2, sample_per_bit, !is_peak2); is_peak2 = !is_peak2; }
                else{ sync_pos1 = rectify_sync_pos(wave, sync_pos1, sample_per_bit, !is_peak1); is_peak1 = !is_peak1; sync_pos2 = new_pos2; }
            }
        }
        int th0 = mean_of_peak2vally(wave, sample_per_bit * 2);
        int th1 = mean_of_peak2vally(wave + sync_pos1 - sample_per_bit, sample_per_bit * 2);
        int th2 = mean_of_peak2vally(wave + sync_pos2 - sample_per_bit, sample_per_bit * 2);
        int th3 = mean_of_peak2vally(wave + (len - 1 - sample_per_bit * 2), sample_per_bit * 2);
        // 3 子段 setup：二值化 + 同步游程 s/e 检测 + 跨度检查（与 phase_off 无关）
        // sub0: wave[0..sync_pos1], sign0=+1, sign1=is_peak1, th0->th1, bit_num=9
        // sub1: wave[sync_pos1..sync_pos2], sign0=is_peak1, sign1=is_peak2, th1->th2, bit_num=8
        // sub2: wave[sync_pos2..len], sign0=is_peak2, sign1=+1, th2->th3, bit_num=11
        int s, e;
        LongArcSubSetup* sb = cs->sub;
        sb[0].wave = wave;             sb[0].len = sync_pos1;            sb[0].th0 = th0; sb[0].th1 = th1; sb[0].bit_num = 9;
        sb[0].ok = wave2bits_setup(wave, sync_pos1, +1, th0, is_peak1, th1, 9, &s, &e); sb[0].s = s; sb[0].e = e;
        sb[1].wave = wave + sync_pos1; sb[1].len = sync_pos2 - sync_pos1; sb[1].th0 = th1; sb[1].th1 = th2; sb[1].bit_num = 8;
        sb[1].ok = wave2bits_setup(wave + sync_pos1, sync_pos2 - sync_pos1, is_peak1, th1, is_peak2, th2, 8, &s, &e); sb[1].s = s; sb[1].e = e;
        sb[2].wave = wave + sync_pos2; sb[2].len = len - sync_pos2;       sb[2].th0 = th2; sb[2].th1 = th3; sb[2].bit_num = 11;
        sb[2].ok = wave2bits_setup(wave + sync_pos2, len - sync_pos2, is_peak2, th2, +1, th3, 11, &s, &e); sb[2].s = s; sb[2].e = e;
        cs->valid = 1; cs->force_peak1 = force_peak1; cs->force_peak2 = force_peak2; cs->min_span = g_min_span;
    }

    // ---- sample（受 sync_off 影响，每次重试重算）----
    double ph1 = (double)sync1_off;                 // sub1 相位
    double ph2 = (sync1_off + sync2_off) * 0.5;     // sub2 相位（双边偏移均值）
    double ph3 = (double)sync2_off;                 // sub3 相位
    double phases[3] = {ph1, ph2, ph3};
    static const int OUT_OFF[3] = {0, 8, 15};
    static const int COPY_N[3] = {8, 7, 9};
    unsigned char bits[12]; unsigned char ctmp[12];
    int ret = 1;
    for (int k = 0; k < 3; k++) {
        const LongArcSubSetup* sb = &cs->sub[k];
        if (sb->ok) {
            wave2bits_sample(sb->wave, sb->len, sb->s, sb->e, sb->th0, sb->th1, sb->bit_num,
                             bits, conf ? ctmp : 0, -1, phases[k]);
            memcpy(out + OUT_OFF[k], bits + 1, COPY_N[k]);
            if (conf) memcpy(conf + OUT_OFF[k], ctmp + 1, COPY_N[k]);
        } else {
            ret = 0;
        }
    }
    return ret;
}

static int wave2bits112_1(unsigned char* wave, int len, unsigned char out[14], unsigned char* conf, const char* graph_name)
{
    int head_len = 0;
    int tail_len = 0;
    trim_head_tail(wave, len, len / 21.0, &head_len, &tail_len, graph_name);
    int real_len = len - head_len - tail_len;

    int sync_pos = head_len + int(real_len / 2.0 + 0.5); //同部位在弧长中间
    int sample_per_bit = int(real_len / 21.0 + 0.5);     //每bit采样数，无累积误差无需用浮点数

    sync_pos = match_sync_010(wave, sync_pos, sample_per_bit, graph_name);

    int th0 = mean_of_peak2vally(wave, sample_per_bit * 2);
    int th1 = mean_of_peak2vally(wave + sync_pos - sample_per_bit, sample_per_bit * 2);
    int th2 = mean_of_peak2vally(wave + (len - 1 - sample_per_bit * 2), sample_per_bit * 2);

    int ret = 1;
    unsigned char bits[9];
    ret &= wave2bits(wave, sync_pos, +1, th0, +1, th1, 9, bits, 0, graph_name, 0);
    memcpy(out, bits + 1, 7);

    ret &= wave2bits(wave + sync_pos, len - sync_pos, 1, th1, +1, th2, 9, bits, 0, graph_name, sync_pos);
    memcpy(out + 7, bits + 1, 7);

    return ret;
}

static int wave2bits112_2(unsigned char* wave, int len, unsigned char out[42], unsigned char* conf, const char* graph_name)
{
    int head_len = 0;
    int tail_len = 0;
    trim_head_tail(wave, len, len / 55.0, & head_len, &tail_len, graph_name);
    int real_len = len - head_len - tail_len;

    double sample_per_bit = real_len / 55.0;
    int spb = (int)(sample_per_bit + 0.5);
    int sync_pos1 = head_len + int(sample_per_bit * 14.5 + 0.5);
    int sync_pos2 = head_len + int(sample_per_bit * 27.5 + 0.5);
    int sync_pos3 = head_len + int(sample_per_bit * 40.5 + 0.5);

    sync_pos1 = match_sync_010(wave, sync_pos1, spb, graph_name);
    sync_pos2 = match_sync_010(wave, sync_pos2, spb, graph_name);
    sync_pos3 = match_sync_010(wave, sync_pos3, spb, graph_name);

    int th0 = mean_of_peak2vally(wave, spb * 2);
    int th1 = mean_of_peak2vally(wave + sync_pos1 - spb, spb * 2);
    int th2 = mean_of_peak2vally(wave + sync_pos2 - spb, spb * 2);
    int th3 = mean_of_peak2vally(wave + sync_pos3 - spb, spb * 2);
    int th4 = mean_of_peak2vally(wave + (len - 1 - spb * 2), spb * 2);

    int ret = 1;
    unsigned char bits[13];
    ret &= wave2bits(wave, sync_pos1, +1, th0, +1, th1, 13, bits, 0, graph_name, 0);
    memcpy(out, bits + 1, 11);

    ret &= wave2bits(wave + sync_pos1, sync_pos2 - sync_pos1, +1, th1, +1, th2, 12, bits, 0, graph_name, sync_pos1);
    memcpy(out + 11, bits + 1, 10);

    ret &= wave2bits(wave + sync_pos2, sync_pos3 - sync_pos2, +1, th2, +1, th3, 12, bits, 0, graph_name, sync_pos2);
    memcpy(out + 21, bits + 1, 10);

    ret &= wave2bits(wave + sync_pos3, len - sync_pos3, 1, th3, +1, th4, 13, bits, 0, graph_name, sync_pos3);
    memcpy(out + 31, bits + 1, 11);

    return ret;
}

int do_wave2bits63(unsigned char* pcurve[4], int curve_len[4], unsigned char bits[63], unsigned char* conf)
{
    int ret = 1;
    // 每次调用前复位百分位阈值标志：c3 极性重试会多次调用本函数，
    // 若不复位，前次调用设置的 g_wave_bitth_used=1 会污染后续调用，错误跳过 Chase。
    g_wave_bitth_used = 0;

    ISLII_LOGI("[wave2bits] 63bit decode start: curve_len=[%d,%d,%d,%d]",
               curve_len[0], curve_len[1], curve_len[2], curve_len[3]);

    for (int i = 0; i < 4; i++){
        char graph_name[32];
        sprintf(graph_name, "Curve%d", i);

        unsigned char binary[24];
        if (0 == i || 1 == i) {
            if (wave2bits63_1(pcurve[i], curve_len[i], binary, conf ? conf + i*8 : 0, graph_name)){
                memcpy(bits + i * 8, binary, 8);
                ISLII_LOGD("[wave2bits] 63bit curve[%d] (short): OK", i);
            }
            else{
                ISLII_LOGE("[wave2bits] 63bit curve[%d] (short): FAILED", i);
                ret = 0;
                break;
            }
        }
        if (2 == i || 3 == i) {
            int fp1 = -1, fp2 = -1;
            int so1 = 0, so2 = 0;
            if (2 == i) { fp1 = g_c2_force_peak1; fp2 = g_c2_force_peak2; so1 = g_c2_sync1_off; so2 = g_c2_sync2_off; }
            if (3 == i) { fp1 = g_c3_force_peak1; fp2 = g_c3_force_peak2; so1 = g_c3_sync1_off; so2 = g_c3_sync2_off; }
            if (wave2bits63_2(pcurve[i], curve_len[i], binary, conf ? conf + 16 + (i-2)*24 : 0, graph_name, fp1, fp2, so1, so2, i - 2)) {
                if (2 == i) {
                    memcpy(bits + 16, binary, 24);
                }
                else {
                    for (int k = 1; k < 24; k++){
                        bits[64 - 1 - k] = binary[k];
                    }
                }
                ISLII_LOGD("[wave2bits] 63bit curve[%d] (long): OK", i);
            }
            else{
                ISLII_LOGE("[wave2bits] 63bit curve[%d] (long): FAILED", i);
                ret = 0;
                break;
            }
        }
    }

    ISLII_LOGI("[wave2bits] 63bit decode: ret=%d", ret);
    return ret;
}

int do_wave2bits112(unsigned char* pcurve[4], int curve_len[4], unsigned char bits[112], unsigned char* conf)
{
    ISLII_LOGI("[wave2bits] 112bit decode start: curve_len=[%d,%d,%d,%d]",
               curve_len[0], curve_len[1], curve_len[2], curve_len[3]);
    int ret = 1;

    for (int i = 0; i < 4; i++) {
        char graph_name[32];
        sprintf(graph_name, "Curve%d", i);

        unsigned char binary[42];
        if (0 == i || 1 == i) {
            if (wave2bits112_1(pcurve[i], curve_len[i], binary, conf ? conf + i*14 : 0, graph_name)){
                memcpy(bits + i * 14, binary, 14);
                ISLII_LOGD("[wave2bits] 112bit curve[%d] (short): OK", i);
            }
            else {
                ISLII_LOGE("[wave2bits] 112bit curve[%d] (short): FAILED", i);
                ret = 0;
                break;
            }
        }
        if (2 == i || 3 == i) {
            if (wave2bits112_2(pcurve[i], curve_len[i], binary, conf ? conf + 28 + (i-2)*42 : 0, graph_name)) {
                if (2 == i) {
                    memcpy(bits + 28, binary, 42);
                }
                else {
                    for (int k = 0; k < 42; k++){
                        bits[112 - 1 - k] = binary[k];
                    }
                }
                ISLII_LOGD("[wave2bits] 112bit curve[%d] (long): OK", i);
            }
            else {
                ISLII_LOGE("[wave2bits] 112bit curve[%d] (long): FAILED", i);
                ret = 0;
                break;
            }
        }
    }

    ISLII_LOGI("[wave2bits] 112bit decode: ret=%d", ret);
    return ret;
}

