#ifndef __ISLIICONDECODER_H__
#define __ISLIICONDECODER_H__

#include "ImageType.h"

//解码器初始化
//成功返回1
//失败返回0，原因是已经被初始化了
int isli_icon_decoder_init();

//解码器反初始化
//成功返回1
//失败返回0，原因是还未被初始化过或已经被反初始化了
int isli_icon_decoder_uninit();


static const int MAX_DECODE_ISLI_CODE_LEN = 20;
static const int MAX_FEATURE_POINT_NUM = 6;

//从ISLI标志码图标中解码读取标志码编码
//成功返回1，结果在出参中
//失败返回0
int isli_icon_decoder_do_image_decode(
        
        //IN,  包含ISLI标志码的图像数据，外框宽度至少5 pxiel
        IMAGE* image,
        
        //OUT, ISLI编码，11位十进制数（1位服务编码+10位前置码）
        //     或19位十进制数（编码结构参考ISLI应用指引），以字符'0'结尾
        //     全'0'结果仅用于算法测试之目的，App应丢弃之
        //     isli_code的内存长度必须大于等于20字节，否则栈内存会因为内存写溢出而被破坏！
        char isli_code[MAX_DECODE_ISLI_CODE_LEN],

        //OUT, 返回6个特征点坐标,
        //     无论解码成功与否，只要坐标值不为0均为有效特征点
        //     建议以坐标点为中心画小圆，以指导用户对准目标
        short feax[MAX_FEATURE_POINT_NUM], short feay[MAX_FEATURE_POINT_NUM],

        //OUT, 返回亮度值
        int *brightness,

        //OUT, 返回图像是否模糊
        int *is_blur
        );

#endif

