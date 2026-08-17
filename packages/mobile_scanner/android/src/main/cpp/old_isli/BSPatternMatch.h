#ifndef __BSPATTERNMATCH_H__
#define __BSPATTERNMATCH_H__

int do_bspatternmatch(unsigned short* bs, int bs_len, int* pos1, int* pos2, double* frame_size);
int do_bspatternmatch_hollow1(unsigned short* bs, int bs_len, int* pos1, int* pos2, double* frame_size);
int do_bspatternmatch_hollow2(unsigned short* bs, int bs_len, int* pos1, int* pos2, double* frame_size);
int do_bspatternmatch_hollow3(unsigned short* bs, int bs_len, int* pos1, int* pos2, double* frame_size);

#endif

