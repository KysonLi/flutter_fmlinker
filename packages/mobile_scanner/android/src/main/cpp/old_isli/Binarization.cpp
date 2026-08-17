#include "Binarization.h"
#include <string.h>

#define REMOTE_DRAW 0
#if REMOTE_DRAW
#include "canvas.h"
#endif

static unsigned char average(unsigned char* data, int len)
{
    if (len > 0) {
        unsigned long sum = 0;
        for (int i = 0; i < len; i++) {
            sum += data[i];
        }

        return (unsigned char)((sum + len / 2) / len);
    }
    else {
        return 0;
    }
}


static int gray2bs(unsigned char* gray_line, int gray_len, unsigned short* bs, int* bs_len)
{
    unsigned char avg = average(gray_line, gray_len);

    int k = 0;
    int cur_sign = +1;
    unsigned short cnt = 0;

    for (int i = 0; i < gray_len; i++) {
        int dif = gray_line[i] - avg;
        if (dif >= 0) {
            if (cur_sign > 0) {
                cnt++;
            }
            else{
                bs[k++] = cnt;
                cur_sign = +1;
                cnt = 1;
                if (k >= *bs_len){
                    return k;
                }
            }
        }
        else {
            if (cur_sign < 0) {
                cnt++;
            }
            else {
                bs[k++] = cnt;
                cur_sign = -1;
                cnt = 1;
                if (k >= *bs_len){
                    return k;
                }
            }
        }
    }
    bs[k++] = cnt;
    *bs_len = k;

    return avg;
}

static void gray2bs2(unsigned char* gray_line, int gray_len, unsigned char* th, unsigned short* bs, int* bs_len)
{
    int k = 0;
    int cur_sign = +1;
    unsigned short cnt = 0;

    for (int i = 0; i < gray_len; i++) {
        int dif = gray_line[i] - th[i];
        if (dif >= 0) {
            if (cur_sign > 0) {
                cnt++;
            }
            else{
                bs[k++] = cnt;
                cur_sign = +1;
                cnt = 1;
                if (k >= *bs_len){
                    return;
                }
            }
        }
        else {
            if (cur_sign < 0) {
                cnt++;
            }
            else {
                bs[k++] = cnt;
                cur_sign = -1;
                cnt = 1;
                if (k >= *bs_len){
                    return;
                }
            }
        }
    }
    bs[k++] = cnt;
    *bs_len = k;
}

static unsigned char find_max(unsigned char* data, int ofst, int len)
{
    unsigned char max = data[ofst];

    for (int i = 1; i < len; i++) {
        if (data[ofst + i] > max) {
            max = data[ofst + i];
        }
    }

    return max;
}

static unsigned char find_min(unsigned char* data, int ofst, int len)
{
    unsigned char min = data[ofst];

    for (int i = 1; i < len; i++) {
        if (data[ofst + i] < min) {
            min = data[ofst + i];
        }
    }

    return min;
}

struct pair {
    unsigned char value;
    int pos;
};

static void linear_interpolation(pair* pv0, pair* pv1, unsigned char* th)
{
    int dv = (pv1->value - pv0->value);
    int dp = (pv1->pos - pv0->pos);
    float step = float(dv) / dp;
    int k = 0;
    for (int i = pv0->pos; i < pv1->pos; i++, k++){
        float v = pv0->value + k * step;
        th[i] = (unsigned char)(v + 0.5);
    }
}

static void threshold(unsigned char avg, unsigned char* gray_line, int gray_len, unsigned short* bs, int bs_num, unsigned char* th)
{
    pair* pv = new pair[(size_t)(bs_num - 1)];

    int ofst = 0;
    unsigned char peak = avg, vally = avg;
    unsigned char last_peak = avg, last_vally = avg;
    int k = 0;

    for (int i = 0; i < bs_num; i++) {
        if (0 == (i & 1)) {
            peak = find_max(gray_line, ofst, bs[i]);
            if (i >= 1){
                unsigned char t = (unsigned char)((peak + last_vally + 1) / 2);
                int pos = ofst - bs[i - 1] / 2;
                pv[k].value = t;
                pv[k].pos = pos;
                //__canvas.DrawDot("profile", "shape=plus;size=3;color=0xff0000", pos, 256 - t);
                k++;
            }
            if (0 == i && 0 == bs[i]){
                //第一个bar可能为0，即“黑块”打头
                last_peak = avg;
            }
            else{
                last_peak = peak;
            }
        }
        else {
            vally = find_min(gray_line, ofst, bs[i]);
            if (i >= 1){
                unsigned char t = (unsigned char)((last_peak + vally + 1) / 2);
                int pos = ofst - bs[i - 1] / 2;
                pv[k].value = t;
                pv[k].pos = pos;
                //__canvas.DrawDot("profile", "shape=plus;size=3;color=0xff0000", pos, 256 - t);
                k++;
            }
            last_vally = vally;
        }
        ofst += bs[i];
    }
    /*__canvas.DrawLine("profile", "color=0x7f7f", 0, 256 - pv[0].value, pv[0].pos, 256 - pv[0].value);
    __canvas.DrawLine("profile", "color=0x7f7f", gray_len, 256 - pv[k - 1].value, pv[k - 1].pos, 256 - pv[k - 1].value);
    for (int i = 1; i < k; i++) {
        __canvas.DrawLine("profile", "color=0x7f7f", pv[i].pos, 256 - pv[i].value, pv[i - 1].pos, 256 - pv[i - 1].value);
    }*/
    for (int i = 0; i < pv[0].pos; i++){
        th[i] = pv[0].value;
    }
    for (int i = pv[k - 1].pos; i < gray_len; i++){
        th[i] = pv[k - 1].value;
    }
    for (int i = 1; i < k; i++){
        linear_interpolation(&pv[i - 1], &pv[i], th);
    }
    delete[] pv;
}

int do_binarizaiton(unsigned char* gray_line, int gray_len, unsigned short* bs, int bs_len)
{
    int bs_num = bs_len;
    
    int avg = gray2bs(gray_line, gray_len, bs, &bs_num);

    if (bs_num <= 2) {
        return bs_num;
    }

    unsigned char* th = new unsigned char[(size_t)gray_len];
    threshold((unsigned char)avg, gray_line, gray_len, bs, bs_num, th);
    //for (int i = 0; i < gray_len; i++){
    //    __canvas.DrawDot("profile", "color=0xff0000", i, 256 - th[i]);
    //}
    bs_num = bs_len;
    gray2bs2(gray_line, gray_len, th, bs, &bs_num);
    delete[] th;

    return bs_num;
}

