#ifndef __BSPATTERNMATCH_H__
#define __BSPATTERNMATCH_H__

int do_bspatternmatch(unsigned short* bs, int bs_len, int* pos1, int* pos2, double* frame_size);

//宽容差版本（±13%），仅在标准匹配失败后用作回退——倾斜/透视补偿
int do_bspatternmatch_wide(unsigned short* bs, int bs_len, int* pos1, int* pos2, double* frame_size);

//最近一次 BSPatternMatch 的匹配置信度（0~1，越高越可靠）
//用于判断定位结果是真实盾牌还是噪声，供后续 stage 门控
float islii_get_bs_confidence();
void  islii_reset_bs_confidence();

#endif

