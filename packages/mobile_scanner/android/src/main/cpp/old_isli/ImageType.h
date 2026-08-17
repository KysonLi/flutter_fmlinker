#ifndef __IMAGETYPE_H__
#define __IMAGETYPE_H__

typedef struct IMAGE
{
    unsigned char* pixel;
    int            w;
    int            h;
    int            bpl;
} IMAGE;

#endif

