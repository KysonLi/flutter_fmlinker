#import "ISLILineDecoderWrapper.h"
#include "linecode/ISLILineDecoder.h"
#include "linecode/IldLog.h"

// Rotate a grayscale plane 90° clockwise: src (w x h, row stride bpl) -> dst (h x w).
// dst must hold w*h bytes; new row stride = h.
static void rotate_y90_cw(const unsigned char* src, int w, int h, int bpl, unsigned char* dst) {
    int nw = h;
    for (int y = 0; y < h; y++) {
        const unsigned char* srow = src + (size_t)y * bpl;
        for (int x = 0; x < w; x++) {
            dst[(size_t)x * nw + (h - 1 - y)] = srow[x];
        }
    }
}

@implementation ISLILineDecoderWrapper

+ (BOOL)initializeDecoder {
    int ret = isli_line_decoder_init();
    return ret != 0;
}

+ (void)uninitializeDecoder {
    isli_line_decoder_uninit();
}

+ (nullable NSDictionary *)decodeGrayscalePixels:(nonnull const unsigned char *)pixels
                                           width:(NSInteger)w
                                          height:(NSInteger)h
                                    bytesPerLine:(NSInteger)bpl {
    if (!pixels || w <= 0 || h <= 0) {
        return nil;
    }

    IMAGE image((unsigned char *)pixels, (int)w, (int)h, (int)bpl);
    char isli_code[20] = {0};
    short feax[2] = {0};
    short feay[2] = {0};
    int brightness = 0;
    int is_blur = 0;

    int ret = isli_line_decoder_do_image_decode(&image, isli_code, feax, feay, &brightness, &is_blur);
    if (ret != 1) {
        return nil;
    }

    NSString *codeString = [NSString stringWithUTF8String:isli_code];

    NSMutableArray<NSDictionary *> *featurePoints = [NSMutableArray arrayWithCapacity:2];
    for (int i = 0; i < 2; i++) {
        [featurePoints addObject:@{
            @"x": @(feax[i]),
            @"y": @(feay[i])
        }];
    }

    return @{
        @"isliCode": codeString,
        @"featurePoints": featurePoints,
        @"brightness": @(brightness),
        @"isBlur": @(is_blur)
    };
}

+ (nullable NSDictionary *)decodeGrayscalePixelsRotated:(nonnull const unsigned char *)pixels
                                                  width:(NSInteger)w
                                                 height:(NSInteger)h
                                           bytesPerLine:(NSInteger)bpl {
    if (!pixels || w <= 0 || h <= 0) {
        return nil;
    }

    // Rotate 90° CW then decode. New image dims: width=h, height=w, bpl=h.
    int nw = (int)h;
    int nh = (int)w;
    unsigned char* rotated = new unsigned char[(size_t)nw * nh];
    rotate_y90_cw(pixels, (int)w, (int)h, (int)bpl, rotated);

    IMAGE image(rotated, nw, nh, nw);
    char isli_code[20] = {0};
    short feax[2] = {0};
    short feay[2] = {0};
    int brightness = 0;
    int is_blur = 0;

    int ret = isli_line_decoder_do_image_decode(&image, isli_code, feax, feay, &brightness, &is_blur);
    delete[] rotated;

    if (ret != 1) {
        return nil;
    }

    // Back-rotate feature points: 90° CW sent orig(col=x,row=y) -> rot(col=h-1-y,row=x),
    // so rot(col=Rx,row=Ry) -> orig(col=Ry,row=h-1-Rx).
    for (int i = 0; i < 2; i++) {
        short rx = feax[i];
        short ry = feay[i];
        feax[i] = ry;
        feay[i] = (short)((int)h - 1 - rx);
    }

    NSString *codeString = [NSString stringWithUTF8String:isli_code];
    NSMutableArray<NSDictionary *> *featurePoints = [NSMutableArray arrayWithCapacity:2];
    for (int i = 0; i < 2; i++) {
        [featurePoints addObject:@{
            @"x": @(feax[i]),
            @"y": @(feay[i])
        }];
    }

    return @{
        @"isliCode": codeString,
        @"featurePoints": featurePoints,
        @"brightness": @(brightness),
        @"isBlur": @(is_blur)
    };
}

+ (void)setLogLevel:(int)level {
    ild_set_log_level(level);
}

@end
