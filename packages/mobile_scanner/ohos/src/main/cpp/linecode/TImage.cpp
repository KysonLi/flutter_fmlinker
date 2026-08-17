#include "TImage.h"
#include <assert.h>
#include <string.h>

TImage::TImage(unsigned char* p, int width, int height, int bytesPerLine)
{
    pixel = p;
    w = width;
    h = height;
    bpl = bytesPerLine;
    bCleanup = false;
}

TImage::TImage()
{
    pixel = nullptr;
    w = 0;
    h = 0;
    bpl = 0;
    bCleanup = false;
}

unsigned char & TImage::replicated(int x, int y, int border)
{
    x -= border;
    y -= border;

    if (x < 0)
        x = 0;
    if (y < 0)
        y = 0;

    if (x >= this->w)
        x = this->w - 1;
    if (y >= this->h)
        y = this->h - 1;

    return this->pixel[y * bpl + x];
}

void TImage::allocate(int w, int h)
{
    delete[]pixel;
    pixel = new unsigned char[w * h];
    bpl = w;
    this->w = w;
    this->h = h;
    bCleanup = true;
}


void TImage::free()
{
    // TODO 这个最后都要改成RAII
    delete[] pixel;
    pixel = nullptr;
}

int TImage::byteCount()
{
    return bpl * h;
}

TImage::~TImage()
{
    if (bCleanup)
        delete[] pixel;
}

void TImage::clear(unsigned char value)
{
    memset(this->pixel, value, this->h * this->bpl);
}
