#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Objective-C wrapper for the ISLI icon (2D shield) decoder C++ library.
/// Exposes class methods callable from Swift.
@interface ISLIDecoderWrapper : NSObject

/// Initialize the native decoder. Must be called once before any decode.
/// Returns YES on success, NO if already initialized or init failed.
+ (BOOL)initializeDecoder;

/// Uninitialize the native decoder. Frees BCH tables and other global state.
+ (void)uninitializeDecoder;

/// Decode an ISLI icon code from 8bpp grayscale pixel data.
///
/// @param pixels  Pointer to grayscale image data (8 bits per pixel).
/// @param w       Image width in pixels.
/// @param h       Image height in pixels.
/// @param bpl     Bytes per line (row stride, typically equal to w for tightly packed).
///
/// @return NSDictionary on success with keys:
///   - @"isliCode":      NSString — 11 or 19 digit ISLI code string
///   - @"featurePoints": NSArray<NSDictionary *> — 6 points, each with @"x" and @"y" (NSNumber int)
///   Returns nil on decode failure.
+ (nullable NSDictionary *)decodeGrayscalePixels:(nonnull const unsigned char *)pixels
                                           width:(NSInteger)w
                                          height:(NSInteger)h
                                    bytesPerLine:(NSInteger)bpl;

+ (void)setLogLevel:(int)level;

@end

NS_ASSUME_NONNULL_END
