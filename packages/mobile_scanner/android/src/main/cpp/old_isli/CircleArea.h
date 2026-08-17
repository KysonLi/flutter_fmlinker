#ifndef __CIRCLEAREA_H__
#define __CIRCLEAREA_H__

struct CircleArea {
    short r;   //半径
    short *x0; //扫描线起始x坐标，扫描线总数为2*r+1
    short *len;//扫描线长度 == (x1 - x0 + 1)
    int   area;//面积
};

CircleArea* init_CircleArea(CircleArea* ca, short r);

void uninit_CircleArea(CircleArea* ca);


#endif

