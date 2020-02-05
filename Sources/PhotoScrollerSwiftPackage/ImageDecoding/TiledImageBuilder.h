/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *
 * This file is part of PhotoScrollerNetwork -- An iOS project that smoothly and efficiently
 * renders large images in progressively smaller ones for display in a CATiledLayer backed view.
 * Images can either be local, or more interestingly, downloaded from the internet.
 * Images can be rendered by an iOS CGImageSource, libjpeg-turbo, or incrmentally by
 * libjpeg (the turbo version) - the latter gives the best speed.
 *
 * Parts taken with minor changes from Apple's PhotoScroller sample code, the
 * ConcurrentOp from my ConcurrentOperations github sample code, and TiledImageBuilder
 * was completely original source code developed by me.
 *
 * Copyright 2012-2020 David Hoerl All Rights Reserved.
 *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
 *
 *
 * Notes:
 * 1) How to use the "size" init parameter.
 *    You should set the height and width of the size parameter to the smallest dimension used 
 *    to display the image. For instance, if you will only display the image in a view of 200, 300,
 *    then use those numbers. If you support both landscape and portrait, then use 200, 200, since 
 *    at some point each dimension will have a minimum of 200 points. If doing full screen then the
 *    numbers will be 320,480 for portrait only, or 320,320 if you support multiple orientations.
 * 
 * 2) Orientation.
 *    JPEG images often have an "orientation" property which defines how the image is oriented.
 *    You can find references to this online, and will see that images can be rotated and flipped in
 *    one of 8 ways, with "1" being as laid out in memory. This class lets you define one of 9 values
 *    to orientation, 0-8. Use "0" if you want this class to look in the properties dictionary, and
 *    set orientation to the specified value (if any). Or, if you want to force an orientation, pass
 *    that value in during initialization, and the image will be forced to that orientation. For
 *    instance, set it to "1" to force the images to be shown as they are stored in memory.
 *
 *      1        2       3      4         5            6           7          8
 * 
 *    888888  888888      88  88      8888888888  88                  88  8888888888
 *    88          88      88  88      88  88      88  88          88  88      88  88
 *    8888      8888    8888  8888    88          8888888888  8888888888          88
 *    88          88      88  88
 *    88          88  888888  888888
 *
 */

@import UIKit;

#import "PhotoScrollerCommon.h"

NS_ASSUME_NONNULL_BEGIN

@interface TiledImageBuilder : NSOutputStream
@property (nonatomic, strong, readonly) NSDictionary *properties;	// image properties from CGImageSourceCopyPropertiesAtIndex()
@property (nonatomic, assign) NSInteger orientation;				// 0 == automatically set using EXIF orientation from image
@property (nonatomic, assign) NSUInteger zoomLevels;				// explose the init setting
@property (nonatomic, assign) uint64_t startTime;					// time stamp of when this operation started decoding
@property (nonatomic, assign) uint64_t finishTime;					// time stamp of when this operation finished  decoding
@property (nonatomic, assign) uint32_t milliSeconds;				// elapsed time
@property (nonatomic, assign) int32_t ubc_threshold;				// UBC threshold above which outstanding writes are flushed to the file system (dynamic default)
@property (nonatomic, assign, readonly) BOOL failed;                // global Error flags
@property (nonatomic, assign, readonly) BOOL finished;              // image was successfully decoded!

+ (void)setUbcThreshold:(float)val;									// default is 0.5 - Image disk cache can use half of the available free memory pool


#if LEVELS_INIT == 0
- (instancetype)initWithSize:(CGSize)sz orientation:(NSInteger)orientation queue:(dispatch_queue_t)queue delegate:(NSObject<NSStreamDelegate> *)delegate;

#else
- (instancetype)initWithLevels:(NSUInteger)levels orientation:(NSInteger)orientation queue:(dispatch_queue_t)queue delegate:(NSObject<NSStreamDelegate> *)delegate);
#endif

- (void)writeToImageFile:(NSData *)data;    // incremental update
- (CGSize)imageSize;                        // orientation modifies what is downloaded

@end

@interface TiledImageBuilder (Draw)

- (__nullable CGImageRef)newImageForScale:(CGFloat)scale location:(CGPoint)pt box:(CGRect)box;
- (UIImage *)tileForScale:(CGFloat)scale location:(CGPoint)pt; // used when doing drawRect, and now for getImageColor ???
- (CGAffineTransform)transformForRect:(CGRect)box; //  scale:(CGFloat)scale;
- (CGPoint)translateTileForScale:(CGFloat)scale location:(CGPoint)origPt;

@end

@interface TiledImageBuilder (JPEG_PUB)

- (BOOL)jpegAdvance:(NSData *)data;

@end

NS_ASSUME_NONNULL_END

/*
 @interface MyOutputStream ()

 //@property (nonatomic, strong, readwrite) NSMutableData *data;

 @end

 @implementation MyOutputStream

 - (instancetype)initToMemory {
	 self = [super initToMemory];
	 //_data = [NSMutableData new];
	 return self;
 }

 - (void)open {
	 [super open];
 }

 - (BOOL)hasSpaceAvailable {
	 return YES;
 }

 - (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len {
 //	[self.data appendBytes:buffer length:len];
	 return len;
 }

 @end

*/
