#ifndef __ILD_WAVE2BINARY_H__
#define __ILD_WAVE2BINARY_H__

#include <vector>
#include "Common.h"
#include "buffer.h"

enum IldOrientation {
    NoSync,
    SyncOnLeft,
    SyncOnRight
};

int ild_wave2bits112(tl::buffer<Byte> &wave, tl::buffer<Byte> &out,
    int head, int tail, std::vector<int> &sync_pos, const char* graph_name, bool use_mean = false,
    tl::buffer<int>* conf = 0);

int ild_wave2bits64(tl::buffer<Byte> &wave, tl::buffer<Byte> &out,
    std::vector<int> &sync_pos, double avg_width, const char* graph_name);

void ild_find_peak_valley(tl::buffer<unsigned char> &wave, std::vector<int> &peak, std::vector<int> &valley, const char *graph_name);
void ild_trim_head_tail(tl::buffer<unsigned char> &wave, std::vector<int> &peak, std::vector<int> &valley, IldOrientation syncType, int &head_len, int &tail_len, const char* graph_name);

#endif

