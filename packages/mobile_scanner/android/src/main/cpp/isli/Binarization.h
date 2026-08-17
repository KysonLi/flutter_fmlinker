#ifndef __BINARIZATION_H__
#define __BINARIZATION_H__

int do_binarizaiton(unsigned char* gray_line, int gray_len, unsigned short* bs, int bs_len);

//快速二值化：仅使用全局均值阈值，不做自适应阈值精化
//适用于扫描线定位阶段，在90%+场景下足够用于BSPatternMatch
int do_binarizaiton_fast(unsigned char* gray_line, int gray_len, unsigned short* bs, int bs_len);

#endif

