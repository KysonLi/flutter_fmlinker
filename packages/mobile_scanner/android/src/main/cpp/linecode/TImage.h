#ifndef __ILD_TIMAGE_H__
#define __ILD_TIMAGE_H__

#include <assert.h>
#include <vector>
#include "Common.h"

struct TImage
{
    unsigned char* pixel;
    int            w;
    int            h;
    int            bpl;
    bool           bCleanup;

    TImage();

    TImage(unsigned char* p,
          int            width,
          int            height,
          int            bytesPerLine);

    ~TImage();

    unsigned char &at(int x, int y)
    {
        assert(x < this->w && y < this->h);
        return this->pixel[y * bpl + x];
    }
    inline unsigned char &replicated(int x, int y, int border);

    void allocate(int w, int h);
    void free();

    void clear(unsigned char value);

    int byteCount();
};

#endif

