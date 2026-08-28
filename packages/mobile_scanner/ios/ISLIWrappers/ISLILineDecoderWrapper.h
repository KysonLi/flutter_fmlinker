#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C wrapper for the ISLI line (1D barcode) decoder C++ library.
/// Exposes class methods callable from Swift.
@interface ISLILineDecoderWrapper : NSObject

/// Initialize the native decoder. Must be called once before any decode.
/// Returns YES on success, NO if already initialized or init failed.
+ (BOOL)initializeDecoder;

/// Uninitialize the native decoder. Frees BCH tables and other global state.
+ (void)uninitializeDecoder;

/// Decode an ISLI line code from 8bpp grayscale pixel data.
///
/// @param pixels  Pointer to grayscale image data (8 bits per pixel).
/// @param w       Image width in pixels.
/// @param h       Image height in pixels.
/// @param bpl     Bytes per line (row stride, typically equal to w for tightly packed).
///
/// @return NSDictionary on success with keys:
///   - @"isliCode":      NSString — 11 or 19 digit ISLI code string
///   - @"featurePoints": NSArray<NSDictionary *> — 2 points, each with @"x" and @"y" (NSNumber int)
///   - @"brightness":    NSNumber — 0..255 image brightness
///   - @"isBlur":        NSNumber — boolean, non-zero if image is blurry
///   Returns nil on decode failure.
+ (nullable NSDictionary *)decodeGrayscalePixels:(nonnull const unsigned char *)pixels
                                           width:(NSInteger)w
                                          height:(NSInteger)h
                                    bytesPerLine:(NSInteger)bpl;

+ (nullable NSDictionary *)decodeGrayscalePixelsRotated:(nonnull const unsigned char *)pixels
                                                  width:(NSInteger)w
                                                 height:(NSInteger)h
                                           bytesPerLine:(NSInteger)bpl;

+ (void)setLogLevel:(int)level;

@end

NS_ASSUME_NONNULL_END
