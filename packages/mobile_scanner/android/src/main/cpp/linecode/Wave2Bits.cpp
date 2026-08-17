#include "Common.h"
#include "Wave2Bits.h"
#include "Filter.h"
#include "ISLILineDecoder.h"
#include "buffer.h"
#include <assert.h>
#include <cmath>

static int mean_of_peak2vally(tl::buffer<unsigned char> &wave, size_t pos, size_t len, bool use_mean = false)
{
    if (use_mean) {
        // DR-4: window mean (robust to outlier pixels that pull the min/max midpoint).
        long sum = 0; size_t cnt = 0;
        for (size_t i = pos; i < pos + len && i < wave.size(); i++) { sum += wave[i]; cnt++; }
        return cnt ? (int)(sum / (long)cnt) : 0;
    }
    int min_v = 256, max_v = 0;
    for (size_t i = pos; i < pos + len && i < wave.size(); i++) {
        int v = wave[i];
        if (v < min_v) min_v = v;
        else if (v > max_v) max_v = v;
    }
    return (min_v + max_v) / 2;
}

static void center_peak_valley(tl::buffer<unsigned char> &wave, std::vector<int> &peak_valley)
{
    for (size_t i = 0; i < peak_valley.size(); i++) {
        int idx = peak_valley[i];
        unsigned char value = wave[idx];
        size_t j = idx;
        for (; j < wave.size() && value == wave[j]; j++) {}
        peak_valley[i] = (int)(idx + j - 1) / 2;
    }
}

void ild_find_peak_valley(tl::buffer<unsigned char> &wave, std::vector<int> &peak,
    std::vector<int> &valley, const char *graph_name)
{
    graph_name = graph_name;
    const int d = 5, t = 2;
    if (wave.size() < 2 * d + 1)
        return;
    for (size_t k = d; k < wave.size() - d; k++) {
        int p0 = wave[k - d], p1 = wave[k], p2 = wave[k + d];
        if (abs((p0 + p2) - p1 * 2) <= t) continue;
        int max_v = wave[k - d], min_v = wave[k - d];
        size_t max_i = k - d, min_i = k - d;
        for (size_t j = k - d + 1; j < k + d; j++) {
            int v = wave[j];
            if (v > max_v) { max_v = v; max_i = j; }
            else if (v < min_v) { min_v = v; min_i = j; }
        }
        if (max_i == k) peak.push_back((int)k);
        else if (min_i == k) valley.push_back((int)k);
    }
    center_peak_valley(wave, peak);
    center_peak_valley(wave, valley);
}

static int wave2bits(tl::buffer<unsigned char> &wave, int pos, int len,
    double sample_per_bit, int th0, int th1,
    int bit_num, tl::buffer<Byte> &bits, const char* graph_name)
{
    graph_name = graph_name;
    if (len <= 0 || pos + len > (int)wave.size()) return 0;
    tl::buffer<signed char> bin;
    bin.resize(len);
    double det = (double)(th1 - th0) / len, t = th0;
    for (int i = 0; i < len; i++) { bin[i] = (signed char)(wave[i + pos] - t); t += det; }
    int margin = (int)(sample_per_bit * 1.5 + 0.5);
    if (margin < 1) margin = 1;  // ensure at least 1 sample of padding to avoid OOB
    int s = pos + margin;
    int e = pos + len - margin;
    if (e <= s) return 0;  // margin too large for segment length → skip
    det = (double)(e - s) / bit_num;
    for (int i = 0; i < bit_num; i++) {
        int p = s + (int)(0.5 * det + i * det + 0.5);
        int idx = p - pos;
        // Clamp to valid range to guard against floating-point rounding at segment edges
        if (idx < 0) idx = 0;
        if (idx >= len) idx = len - 1;
        bits.push_back(bin[idx] > 0 ? 0xff : 0x00);
    }
    return 1;
}

static int match_sync_pos(unsigned char* wave, int sync_pos, int sample_per_bit, int* is_peak, const char* graph_name)
{
    graph_name = graph_name;
    int s0 = sync_pos - sample_per_bit, s1 = s0 + sample_per_bit, n = s1 - s0;
    int score[32]; // sample_per_bit is ~9-12, fits in stack
    for (int i = s0; i < s1; i++) {
        int sum = 0;
        for (int j = 0; j < sample_per_bit; j++) sum += wave[i + j];
        score[i - s0] = sum;
    }
    if ((score[0] + score[n - 1]) / 2 < score[n / 2]) {
        int max_v = score[0], max_p = 0;
        for (int i = 1; i < n; i++) { if (score[i] > max_v) { max_v = score[i]; max_p = i; } }
        sync_pos = s0 + max_p + int(0.5 * sample_per_bit + 0.5);
        *is_peak = 1;
    } else {
        int min_v = score[0], min_p = 0;
        for (int i = 1; i < n; i++) { if (score[i] < min_v) { min_v = score[i]; min_p = i; } }
        sync_pos = s0 + min_p + int(0.5 * sample_per_bit + 0.5);
        *is_peak = 0;
    }
    return sync_pos;
}

void ild_trim_head_tail(tl::buffer<unsigned char> &wave, std::vector<int> &peak,
    std::vector<int> &valley, IldOrientation syncType, int &head_len, int &tail_len, const char* graph_name)
{
    UNREFERENCED_PARAMETER(graph_name);
    assert(peak.size() > 0 && valley.size() > 0);
    if (IldOrientation::SyncOnLeft == syncType) {
        head_len = peak[0]; tail_len = (int)(wave.size() - valley[valley.size() - 1]);
    } else if (IldOrientation::NoSync == syncType) {
        head_len = valley[0]; tail_len = (int)(wave.size() - valley[valley.size() - 1]);
    } else if (IldOrientation::SyncOnRight == syncType) {
        head_len = valley[0]; tail_len = (int)(wave.size() - peak[peak.size() - 1]);
    } else {
        assert(false);
    }
}

int ild_wave2bits112(tl::buffer<Byte> &wave, tl::buffer<Byte> &out,
    int head, int tail, std::vector<int> &sync_pos, const char* graph_name, bool use_mean)
{
    int real_len = (int)wave.size() - head - tail;
    double spb_f = real_len / 68.0;
    int spb = (int)(spb_f + 0.5);
    int s[5] = { head, sync_pos[0], sync_pos[1], sync_pos[2], (int)wave.size() - tail };
    const int thr = (int)(15.5 * 9 * 0.6666);
    if (s[1] - s[0] < thr || s[2] - s[1] < thr || s[3] - s[2] < thr || s[4] - s[3] < thr) return 0;
    int th[5];
    for (int k = 0; k < 5; k++) th[k] = mean_of_peak2vally(wave, s[k] - spb, spb * 2, use_mean);
    int ret = 1;
    for (int k = 0; k < 4; k++)
        ret &= wave2bits(wave, s[k], s[k + 1] - s[k], spb_f, th[k], th[k + 1], 14, out, graph_name);
    return ret;
}

int ild_wave2bits64(tl::buffer<Byte> &wave, tl::buffer<Byte> &out,
    std::vector<int> &sync_pos, double avg_width, const char* graph_name)
{
    UNREFERENCED_PARAMETER(avg_width);
    int real_len = sync_pos[2] - sync_pos[0];
    double spb_f = real_len / 38.0;
    int spb = (int)(spb_f + 0.5);
    int s[3] = { sync_pos[0], sync_pos[1], sync_pos[2] };
    const int thr = (int)(16 * spb_f + 0.5);
    if (s[1] - s[0] < thr || s[2] - s[1] < thr) return 0;
    int th[3];
    for (int k = 0; k < 3; k++) th[k] = mean_of_peak2vally(wave, s[k] - spb, spb * 2);
    int ret = 1;
    for (int k = 0; k < 2; k++)
        ret &= wave2bits(wave, s[k], s[k + 1] - s[k], spb_f, th[k], th[k + 1], 16, out, graph_name);
    return ret;
}
