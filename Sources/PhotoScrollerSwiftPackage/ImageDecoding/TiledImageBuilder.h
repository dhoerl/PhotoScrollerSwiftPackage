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
@property (nonatomic, assign, readonly) NSInteger orientation;		// 0 == automatically set using EXIF orientation from image
@property (nonatomic, assign, readonly) NSUInteger zoomLevels;		// explose the init setting
@property (nonatomic, assign, readonly) uint64_t startTime;			// time stamp of when this operation started decoding
@property (nonatomic, assign, readonly) uint64_t finishTime;		// time stamp of when this operation finished  decoding
@property (nonatomic, assign, readonly) uint32_t milliSeconds;		// elapsed time
@property (atomic, assign, readonly) BOOL failed;                   // global Error flags
@property (atomic, assign, readonly) BOOL finished;                 // image was successfully decoded!
@property (atomic, assign, readonly) BOOL isCancelled;              // image was successfully decoded!

@property (nonatomic, assign) int64_t ubc_threshold;                // UBC threshold above which outstanding writes are flushed to the file system (dynamic default)
@property (class, assign, readonly) int64_t ubcUsage;               // current outstanding fil;e system writes

+ (void)setUbcThreshold:(float)val;									// default is 0.5 - Image disk cache can use half of the available free memory pool

- (instancetype)initWithSize:(CGSize)sz;                                                // orientation determined by the image
- (instancetype)initWithSize:(CGSize)sz orientation:(NSInteger)orientation;             // size == the hosting scrollview bounds.size
- (instancetype)initWithLevels:(NSInteger)levels;                                       // orientation determined by the image
- (instancetype)initWithLevels:(NSInteger)levels orientation:(NSInteger)orientation;    // force possibly more levels

- (void)cancel;
- (CGSize)imageSize;

@end

// Used by the TiledView - not for other uses
@interface TiledImageBuilder (Draw)

- (__nullable CGImageRef)newImageForScale:(CGFloat)scale location:(CGPoint)pt box:(CGRect)box;
- (UIImage *)tileForScale:(CGFloat)scale location:(CGPoint)pt; // used when doing drawRect, and now for getImageColor ???
- (CGAffineTransform)transformForRect:(CGRect)box; //  scale:(CGFloat)scale;

@end

NS_ASSUME_NONNULL_END
