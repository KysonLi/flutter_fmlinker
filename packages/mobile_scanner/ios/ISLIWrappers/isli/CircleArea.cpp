#include "CircleArea.h"
#include <string.h>


//Bresenham's circle algorithm
CircleArea* init_CircleArea(CircleArea* ca, short r)
{
    int area = 0;
    size_t size = (size_t)(2 * r + 1);
    short* x0 = new short[size];
    short* len = new short[size];
    memset(x0, 0, sizeof(short)* (size));

    short x = 0, y = r;
    short d = 3 - 2 * r;

    while (x <= y) {
        {
            if (-x < x0[r + y])//-x, +y;
            x0[r + y] = -x;
            if (-x < x0[r - y])//-x, -y;
                x0[r - y] = -x;
            if (-y < x0[r + x])//-y, +x;
                x0[r + x] = -y;
            if (-y < x0[r - x])//-y, -x;
                x0[r - x] = -y;
        }
        if (d < 0) {
            d = d + 4 * x + 6;
        }
        else {
            d = d + 4 * (x - y) + 10;
            y--;
        }
        x++;
    }
    for (unsigned short i = 0; i < 2 * r + 1; i++){
        len[i] = -x0[i] * 2 + 1;
        area += len[i];
    }

    ca->r = (short)r;
    ca->x0 = x0;
    ca->len = len;
    ca->area = area;

    return ca;
}

void uninit_CircleArea(CircleArea* ca)
{
    delete[] ca->x0;
    delete[] ca->len;
    memset(ca, 0, sizeof(*ca));
}

