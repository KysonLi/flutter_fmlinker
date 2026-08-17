#ifndef __WAVE2BINARY_H__
#define __WAVE2BINARY_H__

int do_wave2bits63(unsigned char* pcurve[4], int curve_len[4], unsigned char bits[63], unsigned char* conf);
int do_wave2bits112(unsigned char* pcurve[4], int curve_len[4], unsigned char bits[112], unsigned char* conf);

// 诊断：dump 每条曲线的波形 + bit 采样决策到 <dir>/<graph_name>.csv
void islii_set_dump_wave(int enable, const char* dir);

// c3 长弧同步极性强制（BCH 重试用）：-1=自动, 0=强制谷, 1=强制峰
void islii_set_c3_force_peak(int p1, int p2);
void islii_set_c2_force_peak(int p1, int p2);

// 长弧同步位置偏移重试（单位：比特，±1）：尝试因同步位锁定到错误相邻极值
// 而导致的整体/子段偏移。0=不偏移(默认)。
void islii_set_c2_sync_off(int o1, int o2);
void islii_set_c3_sync_off(int o1, int o2);
void islii_get_c2_sync_off(int* o1, int* o2);
void islii_get_c3_sync_off(int* o1, int* o2);

// 同步跨度阈值（默认 0.75）：放宽可接受边界波形
void islii_set_min_span(double v);
double islii_get_min_span(void);

// 长弧 setup 缓存重置：每次解码（曲线重采样后、重试开始前）调用，清空缓存槽。
// 缓存按 (force_peak1,force_peak2,min_span) 复用 wave2bits63_2 的 setup（trim/match/th/s-e），
// 重试只重算 sample。曲线变化（新图/span重采样）或 min_span 变化（span_retry）必须重置/失效。
void islii_wave_longarc_cache_reset(void);

#endif

