#include "LineScanner.h"

void do_vertical_scan(IMAGE* image, int x, unsigned char* pline)
{
    unsigned char* psrc = image->pixel + x;
    unsigned char* pdst = pline;
    int bpl = image->bpl;
    int h = image->h;

    for (int v = 0; v < h; v++){
        *pdst++ = *psrc;
        psrc += bpl;
    }
}

void do_skew_scan(IMAGE* image, SKEW_LINE* line, unsigned char* out_wave)
{
    int sx = line->sx;
    int sy = line->sy;
    double dx = line->dx;
    double dy = line->dy;
    int out_len = line->len;
    
    double x = sx;
    double y = sy;

    unsigned char* pixel = image->pixel;
    int w = image->w;
    int h = image->h;
    int bpl = image->bpl;


    for (int i = 0; i < out_len; i++) {
        int X = int(x + 0.5);
        int Y = int(y + 0.5);

        if (X >= 1 && X < (w - 1) && Y >= 1 && Y < (h - 1)) {
            int ofst = Y * bpl + X;
            int v = 0;
            
            v += pixel[ofst] + pixel[ofst + 1] + pixel[ofst - 1];

            ofst -= bpl;
            v += pixel[ofst] + pixel[ofst + 1] + pixel[ofst - 1];

            ofst += 2 * bpl;
            v += pixel[ofst] + pixel[ofst + 1] + pixel[ofst - 1];

            out_wave[i] = (unsigned char)((v + 4) / 9);
        }
        else{
            out_wave[i] = 0;
        }
        x += dx;
        y += dy;
    }
}

