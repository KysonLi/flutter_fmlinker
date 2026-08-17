#ifndef __IMAGETYPE_H__
#define __IMAGETYPE_H__

struct IMAGE
{
    unsigned char* pixel;
    int            w;
    int            h;
    int            bpl;


    IMAGE(unsigned char* p,
          int            width,
          int            height,
          int            bytesPerLine)
    {
        pixel = p;
        w = width;
        h = height;
        bpl = bytesPerLine;
    }
};
#endif

