#include "BSPatternMatch.h"
#include "ISLIIconDecoder.h"
#include <cmath>

static const int B1 = 135;
static const int S1 = 133;
static const int B2 = 452;
static const int S2 = 136;
static const int BS_LEN = B1 + S1 + B2 + S2;
static const int EDGE2EDGE = 2975;

static const int MIN_B     = 5;
static const int FRAME_VAR = 115;

static float g_bs_confidence = 0.0f;
float islii_get_bs_confidence() { return g_bs_confidence; }
void  islii_reset_bs_confidence() { g_bs_confidence = 0.0f; }

int do_bspatternmatch(unsigned short* bs, int bs_len, int* pos1, int* pos2, double* frame_size)
{
    g_bs_confidence = 0.0f;
    static const float VAR = 0.10f;
    int C1_L = int((B1+S1)*1000*(1-VAR)/BS_LEN), C1_R = int((B1+S1)*1000*(1+VAR)/BS_LEN);
    int C2_L = int((S1+B2)*1000*(1-VAR)/BS_LEN), C2_R = int((S1+B2)*1000*(1+VAR)/BS_LEN);
    int C3_L = int((B2+S2)*1000*(1-VAR)/BS_LEN), C3_R = int((B2+S2)*1000*(1+VAR)/BS_LEN);
    int RATIO_L = int(EDGE2EDGE*100/B1*(1-VAR));
    int RATIO_R = int(EDGE2EDGE*100/B1*(1+VAR));
    int RATIO_IDEAL = int(EDGE2EDGE*100/B1);
    int C1_IDEAL = (C1_L+C1_R)/2, C2_IDEAL = (C2_L+C2_R)/2, C3_IDEAL = (C3_L+C3_R)/2;
    int left_c1=0,left_c2=0,left_c3=0; //保存左标记匹配比值供置信度计算

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
                left_c1=c1; left_c2=c2; left_c3=c3;
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
            //匹配置信度：c1,c2,c3 和 r2 偏离理想中心的平均归一化距离，0=完美 1=容差边缘
            float d1 = (float)abs(left_c1-C1_IDEAL)/((C1_R-C1_L)/2.0f);
            float d2 = (float)abs(left_c2-C2_IDEAL)/((C2_R-C2_L)/2.0f);
            float d3 = (float)abs(left_c3-C3_IDEAL)/((C3_R-C3_L)/2.0f);
            float d4 = (float)abs(r2-RATIO_IDEAL)/((RATIO_R-RATIO_L)/2.0f);
            float avg_d = (d1+d2+d3+d4)/4.0f;
            g_bs_confidence = avg_d < 1.0f ? (1.0f - avg_d) : 0.0f;
            return 1;
        }
    }

    return 0;
}

//宽容差版本（±13%），仅用于定位回退——倾斜/透视场景下轻微条宽变形
int do_bspatternmatch_wide(unsigned short* bs, int bs_len, int* pos1, int* pos2, double* frame_size)
{
    static const float VAR = 0.13f;
    int C1_L = int((B1+S1)*1000*(1-VAR)/BS_LEN), C1_R = int((B1+S1)*1000*(1+VAR)/BS_LEN);
    int C2_L = int((S1+B2)*1000*(1-VAR)/BS_LEN), C2_R = int((S1+B2)*1000*(1+VAR)/BS_LEN);
    int C3_L = int((B2+S2)*1000*(1-VAR)/BS_LEN), C3_R = int((B2+S2)*1000*(1+VAR)/BS_LEN);
    int RATIO_L = int(EDGE2EDGE*100/B1*(1-VAR)), RATIO_R = int(EDGE2EDGE*100/B1*(1+VAR));
    int ofst = bs[0], i = 0, left_match = 0, right_match = 0, size1 = 0, size2 = 0, sizef = 0;
    for (i = 1; i < bs_len - 4; i += 2) {
        int b1=bs[i], s1=bs[i+1], b2=bs[i+2], s2=bs[i+3];
        if (b1 >= MIN_B) {
            int bsl = b1+s1+b2+s2;
            int c1=(b1+s1)*1000/bsl, c2=(s1+b2)*1000/bsl, c3=(b2+s2)*1000/bsl;
            if (c1>C1_L&&c1<C1_R && c2>C2_L&&c2<C2_R && c3>C3_L&&c3<C3_R) {
                *pos1 = ofst+(b1+1)/2; size1=bsl; sizef=b1+s1; left_match=1; break;
            }
        }
        ofst += (b1+s1);
    }
    if (!left_match) return 0;
    if (i+12 < bs_len) { for (int k=0;k<9;k++) ofst+=bs[i++]; } else return 0;
    for (; i < bs_len - 4; i += 2) {
        int b1=bs[i+3], s1=bs[i+2], b2=bs[i+1], s2=bs[i+0];
        if (b1 >= MIN_B) {
            int bsl = b1+s1+b2+s2;
            int c1=(b1+s1)*1000/bsl, c2=(s1+b2)*1000/bsl, c3=(b2+s2)*1000/bsl;
            if (c1>C1_L&&c1<C1_R && c2>C2_L&&c2<C2_R && c3>C3_L&&c3<C3_R) {
                *pos2 = ofst+s2+b2+s1+(b1+1)/2; size2=bsl; sizef+=(b1+s1); right_match=1; break;
            }
        }
        ofst += (b2+s2);
    }
    if (right_match) {
        int r1 = size1>size2 ? (size1*100/size2) : (size2*100/size1);
        int r2 = int((*pos2-*pos1)*100/((double)sizef/4)+0.5);
        if (r1 < FRAME_VAR && r2>RATIO_L && r2<RATIO_R) {
            *frame_size = (double)(*pos2-*pos1)/((double)EDGE2EDGE/(double)B1);
            return 1;
        }
    }
    return 0;
}

