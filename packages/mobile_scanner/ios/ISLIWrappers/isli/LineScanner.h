#ifndef __LINESCANNER_H__
#define __LINESCANNER_H__

#include "ImageType.h"

void do_vertical_scan(IMAGE* image, int x, unsigned char* pline);


struct SKEW_LINE
{
    int    sx;
    int    sy;
    double dx;
    double dy;
    int    len;
};

void do_skew_scan(IMAGE* image, SKEW_LINE* line, unsigned char* out_wave);

#endif

