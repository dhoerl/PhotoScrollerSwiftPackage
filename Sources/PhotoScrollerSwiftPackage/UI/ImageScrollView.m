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
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

#import "PhotoScrollerCommon.h"
#import "ImageScrollView.h"
#import "TilingView.h"

#import "../ImageDecoding/TiledImageBuilder.h"


#if 0    // 0 == no debug, 1 == lots of mesages
#define LOG(...) NSLog(@"ISV: " __VA_ARGS__)
#else
#define LOG(...)
#endif

typedef struct {
    CGRect drawRect;
    CGSize imageSize;
} ImageSpecs;

static BOOL _annotateTiles;

@implementation ImageScrollView
{
    CGFloat scale;
    ImageSpecs imageSpecs;  // used when grabbing the displayed content
}

+ (BOOL)annotateTiles
{
  return _annotateTiles;
}
+ (void)setAnnotateTiles:(BOOL)value
{
    _annotateTiles = value;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.showsVerticalScrollIndicator = NO;
        self.showsHorizontalScrollIndicator = NO;
        self.bouncesZoom = YES;
        self.decelerationRate = UIScrollViewDecelerationRateNormal; // DFH UIScrollViewDecelerationRateFast;
        self.delegate = self;
    }
    return self;
}
- (void)dealloc {
    LOG(@"ImageScrollView DEALLOC!");
}

// When we get resized
- (void)setFrame:(CGRect)f {
//NSLog(@"FRAME %@", NSStringFromCGRect(f));
    super.frame = f;

    if(_imageView) {
        [self setMaxMinZoomScalesForCurrentBounds];
        self.zoomScale = self.minimumZoomScale;
    }
}

#pragma mark -
#pragma mark Override layoutSubviews to center content

- (void)layoutSubviews 
{
    [super layoutSubviews];

    if(!_imageView) { return; }

    // center the image as it becomes smaller than the size of the screen, and calculate specs for any drawn image
    CGSize boundsSize = self.bounds.size;
    CGRect frameToCenter = CGRectIntegral(_imageView.frame);
    CGRect imageFrame = CGRectMake(0, 0, self.frame.size.width, self.frame.size.height);

    // center horizontally
    if (frameToCenter.size.width < boundsSize.width) {
        CGFloat offset = rint(boundsSize.width - frameToCenter.size.width);
        frameToCenter.origin.x = offset / 2;
        boundsSize.width -= offset;
        imageFrame.origin.x = -frameToCenter.origin.x;
    } else {
        frameToCenter.origin.x = 0;
    }

    // center vertically
    if (frameToCenter.size.height < boundsSize.height) {
        CGFloat offset = rint(boundsSize.height - frameToCenter.size.height);
        frameToCenter.origin.y = offset / 2;
        boundsSize.height -= offset;
        imageFrame.origin.y = -frameToCenter.origin.y;
    } else {
        frameToCenter.origin.y = 0;
    }
    _imageView.frame = frameToCenter;
    
    if ([_imageView isKindOfClass:[TilingView class]]) {
        // to handle the interaction between CATiledLayer and high resolution screens, we need to manually set the
        // tiling view's contentScaleFactor to 1.0. (If we omitted this, it would be 2.0 on high resolution screens,
        // which would cause the CATiledLayer to ask us for tiles of the wrong scales.)
        _imageView.contentScaleFactor = 1.0;
    }

    imageSpecs.drawRect = imageFrame;
    imageSpecs.imageSize = boundsSize;
}

#pragma mark -
#pragma mark UIScrollView delegate methods

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    return _imageView;
}

#pragma mark -
#pragma mark Configure scrollView to display new image (tiled or not)

- (void)displayObject:(id)obj
{
	CGSize size;

	assert(obj);
	
    // clear the previous imageView
    [_imageView removeFromSuperview];
    
    // reset our zoomScale to 1.0 before doing any further calculations
    self.zoomScale = 1.0;

	if([obj isKindOfClass:[TiledImageBuilder class]]) {
		TiledImageBuilder *imageBuilder = (TiledImageBuilder *)obj;
        // make a new TilingView for the new image
        TilingView *view = [[TilingView alloc] initWithImageBuilder:imageBuilder];
        view.annotates = ImageScrollView.annotateTiles;
        self.imageView =  view;

        size = [imageBuilder imageSize];
		scale = [[UIScreen mainScreen] scale];
	} else
	if([obj isKindOfClass:[TilingView class]]) {
		TilingView *view = (TilingView *)obj;
		view.annotates = ImageScrollView.annotateTiles;
		self.imageView =  view;

        size = [view.imageBuilder imageSize];
		scale = [[UIScreen mainScreen] scale];
	} else
	if([obj isKindOfClass:[UIImageView class]]) {
		UIImageView *iv = (UIImageView *)obj;
        self.imageView = (UIView *)obj;

        size = iv.image.size;
		scale = 1;
	} else {
		NSLog(@"CLASS %@", NSStringFromClass([obj class]));
		assert("Not of the correct class" == NULL);
        exit(0);
	}
	
	[self addSubview:_imageView];
	self.contentSize = size;
	
    [self setMaxMinZoomScalesForCurrentBounds];
    self.zoomScale = self.minimumZoomScale;
}

- (void)setMaxMinZoomScalesForCurrentBounds
{
    if(!_imageView) { return; }

    CGSize boundsSize = self.bounds.size;
    CGSize imageSize = _imageView.bounds.size;
    //NSLog(@"CALC BOUNDS %@", NSStringFromCGRect(self.bounds));
    //NSLog(@"CALC IMAGE %@", NSStringFromCGRect(_imageView.bounds));

    // calculate min/max zoomscale
    CGFloat xScale = boundsSize.width / imageSize.width;    // the scale needed to perfectly fit the image width-wise
    CGFloat yScale = boundsSize.height / imageSize.height;  // the scale needed to perfectly fit the image height-wise

    CGFloat minScale;
	if(_aspectFill) {
		minScale = MAX(xScale, yScale);						// use max of these to allow the image to fill the screen
	} else {
		minScale = MIN(xScale, yScale);						// use minimum of these to allow the image to become fully visible
	}
    
    // screen pixel == image pixel
    CGFloat maxScale = 1.0f / scale;
    
    // don't let minScale exceed maxScale. (If the image is smaller than the screen, we don't want to force it to be zoomed.) 
    if (minScale > maxScale) {
        minScale = maxScale;
    }
    
    self.maximumZoomScale = maxScale;
    self.minimumZoomScale = minScale;
    //NSLog(@"CALC MAX %f MIN %f", self.maximumZoomScale, self.minimumZoomScale);
}

#pragma mark -
#pragma mark Methods called during rotation to preserve the zoomScale and the visible portion of the image

// returns the center point, in image coordinate space, to try to restore after rotation. 
- (CGPoint)pointToCenterAfterRotation
{
    CGPoint boundsCenter = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    return [self convertPoint:boundsCenter toView:_imageView];
}

// returns the zoom scale to attempt to restore after rotation. 
- (CGFloat)scaleToRestoreAfterRotation
{
    CGFloat contentScale = self.zoomScale;
    
    // If we're at the minimum zoom scale, preserve that by returning 0, which will be converted to the minimum
    // allowable scale when the scale is restored.
    if (contentScale <= self.minimumZoomScale + FLT_EPSILON) {
        contentScale = 0;
    }
    return contentScale;
}

- (CGPoint)maximumContentOffset
{
    CGSize contentSize = self.contentSize;
    CGSize boundsSize = self.bounds.size;
    return CGPointMake(contentSize.width - boundsSize.width, contentSize.height - boundsSize.height);
}

- (CGPoint)minimumContentOffset
{
    return CGPointZero;
}

// Adjusts content offset and scale to try to preserve the old zoomscale and center.
- (void)restoreCenterPoint:(CGPoint)oldCenter scale:(CGFloat)oldScale
{    
    // Step 1: restore zoom scale, first making sure it is within the allowable range.
    self.zoomScale = MIN(self.maximumZoomScale, MAX(self.minimumZoomScale, oldScale));
    
    // Step 2: restore center point, first making sure it is within the allowable range.
    
    // 2a: convert our desired center point back to our own coordinate space
    CGPoint boundsCenter = [self convertPoint:oldCenter fromView:_imageView];
    // 2b: calculate the content offset that would yield that center point
    CGPoint offset = CGPointMake(boundsCenter.x - self.bounds.size.width / 2.0f, 
                                 boundsCenter.y - self.bounds.size.height / 2.0f);
    // 2c: restore offset, adjusted to be within the allowable range
    CGPoint maxOffset = [self maximumContentOffset];
    CGPoint minOffset = [self minimumContentOffset];
    offset.x = MAX(minOffset.x, MIN(maxOffset.x, offset.x));
    offset.y = MAX(minOffset.y, MIN(maxOffset.y, offset.y));
    self.contentOffset = offset;
}

// This works even with CATiledLayers backing the enclosed view
// Inspired by https://gist.github.com/nitrag/b3117a4b6b8e89fdbc12b98029cf98f8
- (UIImage *)image
{
    UIGraphicsBeginImageContextWithOptions(imageSpecs.imageSize, YES, 0);       // if smaller than view size, clips (we want that)
    [self drawViewHierarchyInRect:imageSpecs.drawRect afterScreenUpdates:NO];  // must be same size as the view being drawn. Use NO otherwise iOS complains
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@end

//// Inspired by https://gist.github.com/nitrag/b3117a4b6b8e89fdbc12b98029cf98f8
//+ (UIImage *)imageFromView:(UIView *)view subsection:(CGRect)subRect
//{
//    // Image will be sized to the smaller rectangle
//    UIGraphicsBeginImageContextWithOptions(subRect.size, YES, 0);
//
//    // The primary view needs to shift up and left so the desired rect is visible
//    // But the rect passed below needs to be sized to the view, otherwise the image is compressed
//    CGRect drawRect = CGRectMake(-subRect.origin.x, -subRect.origin.x, view.bounds.size.width, view.bounds.size.height);
//
//    [view drawViewHierarchyInRect:drawRect afterScreenUpdates:NO];  // I got compiler complaints using YES ???
//
//    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
//    UIGraphicsEndImageContext();
//    return img;
//}

//- (ImageSpecs)frammer
//{
//NSLog(@"FRAME %@", NSStringFromCGRect(self.frame));
//NSLog(@"BOUNDS %@", NSStringFromCGRect(self.bounds));
//NSLog(@"CONTENT SIZE%@", NSStringFromCGSize(self.contentSize));
//NSLog(@"CONTENT OFFSET %@", NSStringFromCGPoint(self.contentOffset));
//NSLog(@"IV FRAME %@", NSStringFromCGRect(_imageView.frame));
//
