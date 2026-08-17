#include "BSPatternMatch.h"

static const int B1 = 135;//基于http://da.mprtimes.home:8443/svn/MPRCodeEmbedder/ISLIIconWatermarkEmbedder/doc/ISLI图标矢量图设计稿.pdf
static const int S1 = 133;//放大40倍测量得到
static const int B2 = 452;
static const int S2 = 136;
static const int BS_LEN = B1 + S1 + B2 + S2;
static const int EDGE2EDGE = 2975; //边框中心到边框中心距离

static const int MIN_B     = 5;    //最小边框宽度
static const int FRAME_VAR = 115;  //左右两个变框的宽度差异阈值

//bar space组合比例，容错范围±10%
static const float VAR = 0.1f;
static const int C1_L = int((B1 + S1) * 1000 * (1 - VAR) / BS_LEN);
static const int C1_R = int((B1 + S1) * 1000 * (1 + VAR) / BS_LEN);
static const int C2_L = int((S1 + B2) * 1000 * (1 - VAR) / BS_LEN);
static const int C2_R = int((S1 + B2) * 1000 * (1 + VAR) / BS_LEN);
static const int C3_L = int((B2 + S2) * 1000 * (1 - VAR) / BS_LEN);
static const int C3_R = int((B2 + S2) * 1000 * (1 + VAR) / BS_LEN);

//标志码的宽度与边框宽度比例，±10%的容错范围
static const int RATIO_L = int(EDGE2EDGE * 100 / B1 * (1 - 0.1));
static const int RATIO_R = int(EDGE2EDGE * 100 / B1 * (1 + 0.1));

// solid solid
int do_bspatternmatch(unsigned short* bs, int bs_len, int* pos1, int* pos2, double* frame_size)
{
    int left_match = 0;
    int right_match = 0;
    int size1 = 0;
    int size2 = 0;
    int sizef = 0;
    int ofst = bs[0];
    int i = 0;

    for (i = 1; i < bs_len - 4; i += 2) {
        int b1 = bs[i];
        int s1 = bs[i + 1];
        int b2 = bs[i + 2];
        int s2 = bs[i + 3];

        if (b1 >= MIN_B){
            int bs_len = b1 + s1 + b2 + s2;
            int c1 = (b1 + s1) * 1000 / bs_len;
            int c2 = (s1 + b2) * 1000 / bs_len;
            int c3 = (b2 + s2) * 1000 / bs_len;

            if (c1 > C1_L && c1 < C1_R &&
                c2 > C2_L && c2 < C2_R &&
                c3 > C3_L && c3 < C3_R) {
                *pos1 = ofst + (b1 + 1) / 2;
                size1 = bs_len;
                sizef = b1 + s1;
                left_match = 1;
                break;
            }
        }
        ofst += (b1 + s1);
    }
    if (!left_match)
        return 0;

    //跳过中间9个bar-space,匹配对称的另一个pattern
    if (i + 9 + 3 < bs_len) {
        for (int k = 0; k < 9; k++){
            ofst += bs[i++];
        }
    }
    else {
        return 0;
    }

    for (; i < bs_len - 4; i += 2) {
        int b1 = bs[i + 3];
        int s1 = bs[i + 2];
        int b2 = bs[i + 1];
        int s2 = bs[i + 0];

        if (b1 >= MIN_B){
            int bs_len = b1 + s1 + b2 + s2;
            int c1 = (b1 + s1) * 1000 / bs_len;
            int c2 = (s1 + b2) * 1000 / bs_len;
            int c3 = (b2 + s2) * 1000 / bs_len;

            if (c1 > C1_L && c1 < C1_R &&
                c2 > C2_L && c2 < C2_R &&
                c3 > C3_L && c3 < C3_R) {
                *pos2 = ofst + s2 + b2 + s1 + (b1 + 1) / 2;
                size2 = bs_len;
                sizef += (b1 + s1);
                right_match = 1;
                break;
            }
        }
        ofst += (b2 + s2);
    }

    if (right_match) {
        int r1 = size1 > size2 ? (size1 * 100 / size2) : (size2 * 100 / size1);
        int r2 = int((*pos2 - *pos1) * 100 / ((double)sizef / 4) + 0.5);
        
        //r1:两边边框尺寸差异小于等于15%
        //r2:标识码的宽度与边框宽度比例
        if (r1 < FRAME_VAR && (r2 > RATIO_L && r2 < RATIO_R)){
            *frame_size = (double)(*pos2 - *pos1) / ((double)EDGE2EDGE / (double)B1);
            return 1;
        }
    }

    return 0;
}

// hollow hollow
int do_bspatternmatch_hollow1(unsigned short* bs, int bs_len, int* pos1, int* pos2, double* frame_size)
{
    int left_match = 0;
    int right_match = 0;
    int size1 = 0;
    int size2 = 0;
    int sizef = 0;
    int ofst = bs[0];
    int i = 0;

    for (i = 1; i + 5 < bs_len; i += 2) {
        int b1 = bs[i] + bs[i + 1] + bs[i + 2];
        int s1 = bs[i + 3];
        int b2 = bs[i + 4];
        int s2 = bs[i + 5];

        if (b1 >= MIN_B){
            int bs_len = b1 + s1 + b2 + s2;
            int c1 = (b1 + s1) * 1000 / bs_len;
            int c2 = (s1 + b2) * 1000 / bs_len;
            int c3 = (b2 + s2) * 1000 / bs_len;

            if (c1 > C1_L && c1 < C1_R &&
                c2 > C2_L && c2 < C2_R &&
                c3 > C3_L && c3 < C3_R) {
                *pos1 = ofst + (b1 + 1) / 2;
                size1 = bs_len;
                sizef = b1 + s1;
                left_match = 1;
                break;
            }
        }
        ofst += (b1 + s1);
    }
    if (!left_match)
        return 0;

    //跳过中间9个bar-space,匹配对称的另一个pattern
    if (i + 9 + 5 < bs_len) {
        for (int k = 0; k < 9; k++){
            ofst += bs[i++];
        }
    }
    else {
        return 0;
    }

    for (; i + 5 < bs_len; i += 2) {
        int b1 = bs[i + 5] + bs[i + 4] + bs[i + 3];
        int s1 = bs[i + 2];
        int b2 = bs[i + 1];
        int s2 = bs[i + 0];

        if (b1 >= MIN_B){
            int bs_len = b1 + s1 + b2 + s2;
            int c1 = (b1 + s1) * 1000 / bs_len;
            int c2 = (s1 + b2) * 1000 / bs_len;
            int c3 = (b2 + s2) * 1000 / bs_len;

            if (c1 > C1_L && c1 < C1_R &&
                c2 > C2_L && c2 < C2_R &&
                c3 > C3_L && c3 < C3_R) {
                *pos2 = ofst + s2 + b2 + s1 + (b1 + 1) / 2;
                size2 = bs_len;
                sizef += (b1 + s1);
                right_match = 1;
                break;
            }
        }
        ofst += (b2 + s2);
    }

    if (right_match) {
        int r1 = size1 > size2 ? (size1 * 100 / size2) : (size2 * 100 / size1);
        int r2 = int((*pos2 - *pos1) * 100 / ((double)sizef / 4) + 0.5);

        //r1:两边边框尺寸差异小于等于15%
        //r2:标识码的宽度与边框宽度比例
        if (r1 < FRAME_VAR && (r2 > RATIO_L && r2 < RATIO_R)){
            *frame_size = (double)(*pos2 - *pos1) / ((double)EDGE2EDGE / (double)B1);
            return 1;
        }
    }

    return 0;
}

// solid hollow
int do_bspatternmatch_hollow2(unsigned short* bs, int bs_len, int* pos1, int* pos2, double* frame_size)
{
    int left_match = 0;
    int right_match = 0;
    int size1 = 0;
    int size2 = 0;
    int sizef = 0;
    int ofst = bs[0];
    int i = 0;

    for (i = 1; i + 3 < bs_len; i += 2) {
        int b1 = bs[i];
        int s1 = bs[i + 1];
        int b2 = bs[i + 2];
        int s2 = bs[i + 3];

        if (b1 >= MIN_B){
            int bs_len = b1 + s1 + b2 + s2;
            int c1 = (b1 + s1) * 1000 / bs_len;
            int c2 = (s1 + b2) * 1000 / bs_len;
            int c3 = (b2 + s2) * 1000 / bs_len;

            if (c1 > C1_L && c1 < C1_R &&
                c2 > C2_L && c2 < C2_R &&
                c3 > C3_L && c3 < C3_R) {
                *pos1 = ofst + (b1 + 1) / 2;
                size1 = bs_len;
                sizef = b1 + s1;
                left_match = 1;
                break;
            }
        }
        ofst += (b1 + s1);
    }
    if (!left_match)
        return 0;

    //跳过中间9个bar-space,匹配对称的另一个pattern
    if (i + 9 + 5 < bs_len) {
        for (int k = 0; k < 9; k++){
            ofst += bs[i++];
        }
    }
    else {
        return 0;
    }

    for (; i + 5 < bs_len; i += 2) {
        int b1 = bs[i + 5] + bs[i + 4] + bs[i + 3];
        int s1 = bs[i + 2];
        int b2 = bs[i + 1];
        int s2 = bs[i + 0];

        if (b1 >= MIN_B){
            int bs_len = b1 + s1 + b2 + s2;
            int c1 = (b1 + s1) * 1000 / bs_len;
            int c2 = (s1 + b2) * 1000 / bs_len;
            int c3 = (b2 + s2) * 1000 / bs_len;

            if (c1 > C1_L && c1 < C1_R &&
                c2 > C2_L && c2 < C2_R &&
                c3 > C3_L && c3 < C3_R) {
                *pos2 = ofst + s2 + b2 + s1 + (b1 + 1) / 2;
                size2 = bs_len;
                sizef += (b1 + s1);
                right_match = 1;
                break;
            }
        }
        ofst += (b2 + s2);
    }

    if (right_match) {
        int r1 = size1 > size2 ? (size1 * 100 / size2) : (size2 * 100 / size1);
        int r2 = int((*pos2 - *pos1) * 100 / ((double)sizef / 4) + 0.5);

        //r1:两边边框尺寸差异小于等于15%
        //r2:标识码的宽度与边框宽度比例
        if (r1 < FRAME_VAR && (r2 > RATIO_L && r2 < RATIO_R)){
            *frame_size = (double)(*pos2 - *pos1) / ((double)EDGE2EDGE / (double)B1);
            return 1;
        }
    }

    return 0;
}

// hollow solid
int do_bspatternmatch_hollow3(unsigned short* bs, int bs_len, int* pos1, int* pos2, double* frame_size)
{
    int left_match = 0;
    int right_match = 0;
    int size1 = 0;
    int size2 = 0;
    int sizef = 0;
    int ofst = bs[0];
    int i = 0;

    for (i = 1; i + 5 < bs_len; i += 2) {
        int b1 = bs[i] + bs[i + 1] + bs[i + 2];
        int s1 = bs[i + 3];
        int b2 = bs[i + 4];
        int s2 = bs[i + 5];

        if (b1 >= MIN_B){
            int bs_len = b1 + s1 + b2 + s2;
            int c1 = (b1 + s1) * 1000 / bs_len;
            int c2 = (s1 + b2) * 1000 / bs_len;
            int c3 = (b2 + s2) * 1000 / bs_len;

            if (c1 > C1_L && c1 < C1_R &&
                c2 > C2_L && c2 < C2_R &&
                c3 > C3_L && c3 < C3_R) {
                *pos1 = ofst + (b1 + 1) / 2;
                size1 = bs_len;
                sizef = b1 + s1;
                left_match = 1;
                break;
            }
        }
        ofst += (b1 + s1);
    }
    if (!left_match)
        return 0;

    //跳过中间9个bar-space,匹配对称的另一个pattern
    if (i + 9 + 3 < bs_len) {
        for (int k = 0; k < 9; k++){
            ofst += bs[i++];
        }
    }
    else {
        return 0;
    }

    for (; i + 3 < bs_len; i += 2) {
        int b1 = bs[i + 3];
        int s1 = bs[i + 2];
        int b2 = bs[i + 1];
        int s2 = bs[i + 0];

        if (b1 >= MIN_B){
            int bs_len = b1 + s1 + b2 + s2;
            int c1 = (b1 + s1) * 1000 / bs_len;
            int c2 = (s1 + b2) * 1000 / bs_len;
            int c3 = (b2 + s2) * 1000 / bs_len;

            if (c1 > C1_L && c1 < C1_R &&
                c2 > C2_L && c2 < C2_R &&
                c3 > C3_L && c3 < C3_R) {
                *pos2 = ofst + s2 + b2 + s1 + (b1 + 1) / 2;
                size2 = bs_len;
                sizef += (b1 + s1);
                right_match = 1;
                break;
            }
        }
        ofst += (b2 + s2);
    }

    if (right_match) {
        int r1 = size1 > size2 ? (size1 * 100 / size2) : (size2 * 100 / size1);
        int r2 = int((*pos2 - *pos1) * 100 / ((double)sizef / 4) + 0.5);

        //r1:两边边框尺寸差异小于等于15%
        //r2:标识码的宽度与边框宽度比例
        if (r1 < FRAME_VAR && (r2 > RATIO_L && r2 < RATIO_R)){
            *frame_size = (double)(*pos2 - *pos1) / ((double)EDGE2EDGE / (double)B1);
            return 1;
        }
    }

    return 0;
}