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

#import <QuartzCore/CATiledLayer.h>

#import "PhotoScrollerCommon.h"
#import "TilingView.h"
#import "../ImageDecoding/TiledImageBuilder.h"

#define LOG NSLog

@interface FastCATiledLayer : CATiledLayer
@end

@implementation FastCATiledLayer

+ (CFTimeInterval)fadeDuration
{
  return 0;
}

@end

@implementation TilingView
{
	TiledImageBuilder *tb;
}

+ (Class)layerClass
{
	return [FastCATiledLayer class];
}

- (id)initWithImageBuilder:(TiledImageBuilder *)imageBuilder
{
	CGRect rect = { CGPointMake(0, 0), [imageBuilder imageSize] };
	
    if ((self = [super initWithFrame:rect])) {
        tb = imageBuilder;

        CATiledLayer *tiledLayer = (CATiledLayer *)[self layer];
        tiledLayer.levelsOfDetail = imageBuilder.zoomLevels;
		
		self.opaque = YES;
		self.clearsContextBeforeDrawing = NO;
    }
    return self;
}

//static inline long offsetFromScale(CGFloat scale) { long s = lrintf(1/scale); long idx = 0; while(s > 1) s /= 2.0f, ++idx; return idx; }

- (void)drawLayer:(CALayer*)layer inContext:(CGContextRef)context
{
	if(tb.failed) return;

    CGFloat scale = CGContextGetCTM(context).a;

	// Fetch clip box in *view* space; context's CTM is preconfigured for view space->tile space transform
	CGRect box = CGContextGetClipBoundingBox(context);

	// Calculate tile index
	CGSize tileSize = [(CATiledLayer*)layer tileSize];
	CGFloat col = (CGFloat)rint(box.origin.x * scale / tileSize.width);
	CGFloat row = (CGFloat)rint(box.origin.y * scale / tileSize.height);

	//LOG(@"scale=%f 1/scale=%f levelsOfDetail=%ld levelsOfDetailBias=%ld row=%f col=%f offsetFromScale=%ld", scale, 1/scale, ((CATiledLayer *)layer).levelsOfDetail, ((CATiledLayer *)layer).levelsOfDetailBias, row, col, offsetFromScale(scale));


	CGImageRef image = [tb newImageForScale:scale location:CGPointMake(col, row) box:box];

#if 0 // had this happen, think its fixed
if(!image) {
	LOG(@"YIKES! No Image!!! row=%f col=%f", row, col);
	return;
}
if(CGImageGetWidth(image) == 0 || CGImageGetHeight(image) == 0) {
	LOG(@"Yikes! Image has a zero dimension! row=%f col=%f", row, col);
	return;
}
#endif

	assert(image);

	CGContextTranslateCTM(context, box.origin.x, box.origin.y + box.size.height);
	CGContextScaleCTM(context, 1.0, -1.0);
	box.origin.x = 0;
	box.origin.y = 0;
	//LOG(@"Draw: scale=%f row=%d col=%d", scale, (int)row, (int)col);

	CGAffineTransform transform = [tb transformForRect:box /* scale:scale */];
	CGContextConcatCTM(context, transform);

	// Detect Rotation
	if(isnormal(transform.b) && isnormal(transform.c)) {
		CGSize s = box.size;
		box.size = CGSizeMake(s.height, s.width);
	}

	// LOG(@"BOX: %@", NSStringFromCGRect(box));

	CGContextSetBlendMode(context, kCGBlendModeCopy);	// no blending! from QA 1708
//if(row==0 && col==0)	
	CGContextDrawImage(context, box, image);
	//CGImageRelease(image);

	if(self.annotates) {
		CGContextSetStrokeColorWithColor(context, [[UIColor whiteColor] CGColor]);
		CGContextSetLineWidth(context, 6.0f / scale);
		CGContextStrokeRect(context, box);
	}
}

- (CGSize)imageSize
{
	return [tb imageSize];
}

-(UIColor *)getColorAtPosition:(CGPoint)pt
{
	CATiledLayer *tiledLayer = (CATiledLayer *)[self layer];
	CGSize tileSize = tiledLayer.tileSize;

	UIGraphicsBeginImageContextWithOptions(tileSize, YES, 0);

#if __LP64__
	long col = lrint( floor(pt.x / tileSize.width) );
	long row = lrint( floor(pt.y / tileSize.height) );
	CGPoint offsetPt = CGPointMake( round(pt.x - col * tileSize.width), round(  (pt.y - row * tileSize.height) ) );
#else
	long col = lrintf( floorf(pt.x / tileSize.width) );
	long row = lrintf( floorf(pt.y / tileSize.height) );
	CGPoint offsetPt = CGPointMake( roundf(pt.x - col * tileSize.width), roundf(  (pt.y - row * tileSize.height) ) );
#endif

	CGRect tileRect = CGRectMake(0, 0, tileSize.width, tileSize.height);
	UIImage *tile = [tb tileForScale:1 location:CGPointMake(col, row)];
	[tile drawInRect:tileRect];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	
	UIGraphicsEndImageContext();

	CGRect sourceRect = CGRectMake(offsetPt.x, offsetPt.y, 1, 1);
	CGImageRef imageRef = CGImageCreateWithImageInRect(image.CGImage, sourceRect);

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
	unsigned char *buffer = malloc(4);
	CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big;
	CGContextRef context = CGBitmapContextCreate(buffer, 1, 1, 8, 4, colorSpace, bitmapInfo);
	//CGColorSpaceRelease(colorSpace);
	CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), imageRef);
	//CGImageRelease(imageRef);
	//CGContextRelease(context);

	CGFloat d = 255;
	CGFloat r = buffer[0] / d;
	CGFloat g = buffer[1] / d;
	CGFloat b = buffer[2] / d;
	CGFloat a = buffer[3] / d;

	free(buffer);
		
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

#if 0 

// How to render it http://stackoverflow.com/questions/5526545/render-large-catiledlayer-into-smaller-area

- (UIImage *)image
{
    UIGraphicsBeginImageContextWithOptions(self.bounds.size, YES, 0);
	
    [self.layer renderInContext:UIGraphicsGetCurrentContext()];

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();

    UIGraphicsEndImageContext();

    return img;
}
#endif

@end
