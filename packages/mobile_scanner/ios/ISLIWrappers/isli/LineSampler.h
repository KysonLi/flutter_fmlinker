#ifndef __LINESAPMLER_H__
#define __LINESAMPLER_H__

int do_line_sample(unsigned char* bits, int w, int h, int bpl,
                   int* px, int* py, int pn,
                   unsigned short* psample_buf, int buf_len);

#endif


