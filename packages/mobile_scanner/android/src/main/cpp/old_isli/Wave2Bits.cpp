#include "Wave2Bits.h"
#include "Filter.h"
#include <memory.h>
#include <stdio.h>

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

static const int wave2bits(unsigned char* wave, int len,
    int sign_of_sync0, int th0,
    int sign_of_sync1, int th1,
    int bit_num, unsigned char bits[],
    const char* graph_name, int offset)
{
    graph_name = graph_name, offset = offset; //消除编译警告

    int ret = 0;
    unsigned char* bin = new unsigned char[(size_t)len];

    //二值化，头尾均值插值作为阈值
    memset(bin, 0, (size_t)len);
    double det = (double)(th1 - th0) / len;
    double t = th0;
    for (int i = 0; i < len; i++){
        if (wave[i] > t) {
            bin[i] = 0xff;
        }
        t += det;
    }
#if REMOTE_DRAW
    __canvas.DrawLine(graph_name, "color=0x009f9f", 0 + offset, 255 - th0, len + offset, 255 - th1);
#endif

    //去掉头部的同部位
    int s = 0;
    if (sign_of_sync0 > 0) {
        while (0 == bin[s] && s < len) s++;
        while (bin[s] && s < len) s++;
    }
    else {
        while (bin[s] && s < len) s++;
        while (0 == bin[s] && s < len) s++;
    }

    //去掉尾部的同步位
    int e = len - 1;
    if (sign_of_sync1 > 0) {
        while (0 == bin[e] && e > 0) e--;
        while (bin[e] && e > 0) e--;
    }

    else {
        while (bin[e] && e > 0) e--;
        while (0 == bin[e] && e > 0) e--;
    }

    //采样
    if (((double)(e - s) / (double)len) > 0.75) {
        //头尾最多只能占25%
#if REMOTE_DRAW
        __canvas.DrawLine(graph_name, "color=0x9f00", s + offset, 255, s + offset, 255 - wave[s]);
        __canvas.DrawLine(graph_name, "color=0x9f00", e + offset, 255, e + offset, 255 - wave[e]);
#endif
        double det = (double)(e - s) / bit_num;
        for (int i = 0; i < bit_num; i++){
            int p = s + (int)(0.5 * det + i * det + 0.5);
#if REMOTE_DRAW
            __canvas.DrawLine(graph_name, "color=0x9f009f", p + offset, 255, p + offset, 255 - wave[p]);
#endif
            bits[i] = bin[p];
        }
        ret = 1;
    }
    else {
        ret = 0;
    }

    delete[] bin;

    return ret;
}

//短弧的参数：共12个数据位，去掉头尾的同步位后剩余10个数据位
int wave2bits63_1(unsigned char* wave, int len, unsigned char out[8], const char* graph_name)
{
    int ret = 0;
    //头部均值、尾部均值
    int sync_len = (len * 2 + 6) / 12;
    int th0 = mean_of_peak2vally(wave, sync_len);   
    int th1 = mean_of_peak2vally(wave + len - sync_len, sync_len);

    unsigned char bits[10];

    if (wave2bits(wave, len, +1, th0, +1, th1, 10, bits, graph_name, 0)){
        memcpy(out, bits + 1, 8);
        ret = 1;
    }

    return ret;
}

//匹配长弧中的同步位
static int match_sync_pos(unsigned char* wave, int sync_pos, int sample_per_bit, int* is_peak, const char* graph_name)
{
    graph_name = graph_name; //消除编译警告

    int s0 = sync_pos - sample_per_bit;
    int s1 = s0 + sample_per_bit;
    int* score = new int[(size_t)sample_per_bit];

#if REMOTE_DRAW
    __canvas.DrawLine(graph_name, "color=0xff", sync_pos, 128, sync_pos, 256);
    //__canvas.DrawLine(graph_name, "color=0xff", s0, 128, s0, 256);
    //int right = sync_pos + sample_per_bit;
    //__canvas.DrawLine(graph_name, "color=0xff", right, 128, right, 256);
#endif

    for (int i = s0; i < s1; i++){
        int sum = 0;
        for (int j = 0; j < sample_per_bit; j++) {
            sum += wave[i + j];
        }
        score[i - s0] = sum;
    }

    if ((score[0] + score[sample_per_bit - 1]) / 2 < score[sample_per_bit/2]) {
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
    delete[] score;

#if REMOTE_DRAW
    __canvas.DrawLine(graph_name, "color=0x7f7f00", sync_pos, 128, sync_pos, 256);
#endif
    
    return sync_pos;
}

static int match_sync_010(unsigned char* wave, int sync_pos, int sample_per_bit, const char* graph_name)
{
    graph_name = graph_name; //消除编译警告

    int s0 = sync_pos - sample_per_bit;
    int s1 = s0 + sample_per_bit;
    int* score = new int[(size_t)sample_per_bit];

#if REMOTE_DRAW
    __canvas.DrawLine(graph_name, "color=0xff", sync_pos, 128, sync_pos, 256);
    //__canvas.DrawLine(graph_name, "color=0xff", s0, 128, s0, 256);
    //int right = sync_pos + sample_per_bit;
    //__canvas.DrawLine(graph_name, "color=0xff", right, 128, right, 256);
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
    delete[] score;

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
    int s0 = sync_pos - sample_per_bit;
    int s1 = s0 + sample_per_bit;
    int* score = new int[(size_t)sample_per_bit];

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
    delete[] score;

    return sync_pos;
}

static int wave2bits63_2(unsigned char* wave, int len, unsigned char out[24], const char* graph_name)
{
    int head_len = 0;
    int tail_len = 0;
    trim_head_tail(wave, len, len / 32.0, &head_len, &tail_len, graph_name);
    int real_len = len - head_len - tail_len;

    int sync_pos1 = head_len + int(10.5 / 32 * real_len + 0.5); //设弧长32.5位，则第一个同部位在10.5位
    int sync_pos2 = head_len + int(19.5 / 32 * real_len + 0.5); //设弧长32.5位，则第一个同部位在19.5位
    int sample_per_bit = (real_len + 16) / 32;                  //每bit采样数，无累积误差无需用浮点数

    int is_peak1 = 0, is_peak2 = 0;
    int new_pos1 = match_sync_pos(wave, sync_pos1, sample_per_bit, &is_peak1, graph_name);
    int new_pos2 = match_sync_pos(wave, sync_pos2, sample_per_bit, &is_peak2, graph_name);
    int shift = (new_pos1 - sync_pos1) - (new_pos2 - sync_pos2);
    if (shift < sample_per_bit / 2){
        sync_pos1 = new_pos1;
        sync_pos2 = new_pos2;
    }
    else {
        //至少有一个同步位错了！
        int sync_score1 = sync_score(wave, new_pos1, sample_per_bit);
        int sync_score2 = sync_score(wave, new_pos2, sample_per_bit);
        if (sync_score1 > sync_score2){
            sync_pos1 = new_pos1;
            sync_pos2 = rectify_sync_pos(wave, sync_pos2, sample_per_bit, !is_peak2);
            is_peak2 = !is_peak2;
        }
        else{
            sync_pos1 = rectify_sync_pos(wave, sync_pos1, sample_per_bit, !is_peak1);
            is_peak1 = !is_peak1;
            sync_pos2 = new_pos2;
        }
    }
    
    int th0 = mean_of_peak2vally(wave, sample_per_bit * 2);
    int th1 = mean_of_peak2vally(wave + sync_pos1 - sample_per_bit, sample_per_bit * 2);
    int th2 = mean_of_peak2vally(wave + sync_pos2 - sample_per_bit, sample_per_bit * 2);
    int th3 = mean_of_peak2vally(wave + (len - 1 - sample_per_bit * 2), sample_per_bit * 2);

    unsigned char bits[12];
    int ret = 1;
    ret &= wave2bits(wave, sync_pos1, +1, th0, is_peak1, th1, 9, bits, graph_name, 0);
    memcpy(out, bits + 1, 8);

    ret &= wave2bits(wave + sync_pos1, sync_pos2 - sync_pos1, is_peak1, th1, is_peak2, th2, 8, bits, graph_name, sync_pos1);
    memcpy(out + 8, bits + 1, 7);

    ret &= wave2bits(wave + sync_pos2, len - sync_pos2, is_peak2, th2, +1, th3, 11, bits, graph_name, sync_pos2);
    memcpy(out + 15, bits + 1, 9);

    return ret;
}

static int wave2bits112_1(unsigned char* wave, int len, unsigned char out[14], const char* graph_name)
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
    ret &= wave2bits(wave, sync_pos, +1, th0, +1, th1, 9, bits, graph_name, 0);
    memcpy(out, bits + 1, 7);

    ret &= wave2bits(wave + sync_pos, len - sync_pos, 1, th1, +1, th2, 9, bits, graph_name, sync_pos);
    memcpy(out + 7, bits + 1, 7);

    return ret;
}

static int wave2bits112_2(unsigned char* wave, int len, unsigned char out[42], const char* graph_name)
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
    ret &= wave2bits(wave, sync_pos1, +1, th0, +1, th1, 13, bits, graph_name, 0);
    memcpy(out, bits + 1, 11);

    ret &= wave2bits(wave + sync_pos1, sync_pos2 - sync_pos1, +1, th1, +1, th2, 12, bits, graph_name, sync_pos1);
    memcpy(out + 11, bits + 1, 10);

    ret &= wave2bits(wave + sync_pos2, sync_pos3 - sync_pos2, +1, th2, +1, th3, 12, bits, graph_name, sync_pos2);
    memcpy(out + 21, bits + 1, 10);

    ret &= wave2bits(wave + sync_pos3, len - sync_pos3, 1, th3, +1, th4, 13, bits, graph_name, sync_pos3);
    memcpy(out + 31, bits + 1, 11);

    return ret;
}

int do_wave2bits63(unsigned char* pcurve[4], int curve_len[4], unsigned char bits[63])
{
    int ret = 1;

    for (int i = 0; i < 4; i++){
        char graph_name[32];
        sprintf(graph_name, "Curve%d", i);

        unsigned char binary[24];
        if (0 == i || 1 == i) {
            if (wave2bits63_1(pcurve[i], curve_len[i], binary, graph_name)){
                memcpy(bits + i * 8, binary, 8);
            }
            else{
                ret = 0;
                break;
            }
        }
        if (2 == i || 3 == i) {
            if (wave2bits63_2(pcurve[i], curve_len[i], binary, graph_name)) {
                if (2 == i) {
                    memcpy(bits + 16, binary, 24);
                }
                else {
                    for (int k = 1; k < 24; k++){
                        bits[64 - 1 - k] = binary[k];
                    }
                }
            }
            else{
                ret = 0;
                break;
            }
        }
    }

    return ret;
}

int do_wave2bits112(unsigned char* pcurve[4], int curve_len[4], unsigned char bits[112])
{
    int ret = 1;

    for (int i = 0; i < 4; i++) {
        char graph_name[32];
        sprintf(graph_name, "Curve%d", i);

        unsigned char binary[42];
        if (0 == i || 1 == i) {
            if (wave2bits112_1(pcurve[i], curve_len[i], binary, graph_name)){
                memcpy(bits + i * 14, binary, 14);
            }
            else {
                ret = 0;
                break;
            }
        }
        if (2 == i || 3 == i) {
            if (wave2bits112_2(pcurve[i], curve_len[i], binary, graph_name)) {
                if (2 == i) {
                    memcpy(bits + 28, binary, 42);
                }
                else {
                    for (int k = 0; k < 42; k++){
                        bits[112 - 1 - k] = binary[k];
                    }
                }
            }
            else {
                ret = 0;
                break;
            }
        }
    }

    return ret;
}

