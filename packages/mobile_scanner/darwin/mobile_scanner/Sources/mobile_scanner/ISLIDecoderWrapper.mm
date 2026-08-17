#import "ISLIDecoderWrapper.h"
#include "isli/ISLIIconDecoder.h"
#include "isli/ImageType.h"
#include "isli/IldLog.h"

@implementation ISLIDecoderWrapper

+ (BOOL)initializeDecoder {
    int ret = isli_icon_decoder_init();
    return ret != 0;
}

+ (void)uninitializeDecoder {
    isli_icon_decoder_uninit();
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
    short feax[6] = {0};
    short feay[6] = {0};

    int ret = isli_icon_decoder_do_image_decode(&image, isli_code, feax, feay);
    if (ret != 1) {
        return nil;
    }

    NSString *codeString = [NSString stringWithUTF8String:isli_code];

    NSMutableArray<NSDictionary *> *featurePoints = [NSMutableArray arrayWithCapacity:6];
    for (int i = 0; i < 6; i++) {
        [featurePoints addObject:@{
            @"x": @(feax[i]),
            @"y": @(feay[i])
        }];
    }

    return @{
        @"isliCode": codeString,
        @"featurePoints": featurePoints
    };
}

+ (void)setLogLevel:(int)level {
    islii_set_log_level(level);
}

@end
