#ifndef __ISLILINEDECODER_H__
#define __ISLILINEDECODER_H__

#include "Common.h"

struct IMAGE
{
    unsigned char* pixel;  // 输入图片数据 灰度图像 bpp:8
    int            w;      // 输入图片宽度
    int            h;      // 输入图片高度
    int            bpl;    // 每行字节数
    IMAGE() : pixel(nullptr), w(0), h(0), bpl(0) {}
    IMAGE(unsigned char* p, int width, int height, int bytesPerLine) : pixel(p), w(width), h(height), bpl(bytesPerLine) {}
};

struct TRect {
    int x;
    int y;
    int w;
    int h;
    TRect() : x(0), y(0), w(0), h(0) {}
    TRect(int x, int y, int w, int h) : x(x), y(y), w(w), h(h) {}
};

// 初始化
// 返回值: 非0成功
int isli_line_decoder_init();

// 反初始化
// 返回值: 非0成功
int isli_line_decoder_uninit();

// 解码一幅图片
// 返回值: 非0成功
int isli_line_decoder_do_image_decode(
    IMAGE *image,           // 输入图片 灰度图像 bpp:8
    char isli_code[20],     // 解码结果
    short *feax,            // 特征点 缓冲区大小为2 需要初始化为0
    short *feay,            // 特征点 缓冲区大小为2 需要初始化为0
    int *brightness,        // 图像总体亮度 缓冲区大小为1 结果范围 0 ~ 255
    int *is_blur);          // 图像是否模糊(已对焦) 缓冲区大小为1 结果非0为模糊

#endif