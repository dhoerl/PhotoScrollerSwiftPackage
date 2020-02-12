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

#import "TiledImageBuilder-Private.h"

#if 0	// 0 == no debug, 1 == lots of mesages
#define LOG(...) NSLog(@"TB-Tile: " __VA_ARGS__)
#else
#define LOG(...)
#endif

@implementation TiledImageBuilder (Tile)

- (BOOL)tileBuilder:(imageMemory *)im useMMAP:(BOOL )useMMAP
{
	unsigned char *optr = im->map.emptyAddr;
	unsigned char *iptr = im->map.addr;
	
	// LOG(@"tile...");
	// Now, we are going to pre-tile the image in 256x256 tiles, so we can map in contigous chunks of memory
	for(size_t row=im->row; row<im->rows; ++row) {
		unsigned char *tileIptr;
		if(useMMAP) {
			im->map.mappedSize = im->map.emptyTileRowSize*2;	// two tile rows
			im->map.emptyAddr = mmap(NULL, im->map.mappedSize, PROT_READ | PROT_WRITE, MAP_FILE | MAP_SHARED, im->map.fd, row*im->map.emptyTileRowSize);  /*| MAP_NOCACHE */
			if(im->map.emptyAddr == MAP_FAILED) return NO;
#if MMAP_DEBUGGING == 1
			LOG(@"MMAP[%d]: addr=%p 0x%X bytes", im->map.fd, im->map.emptyAddr, (NSUInteger)im->map.mappedSize);
#endif	
			im->map.addr = im->map.emptyAddr + im->map.emptyTileRowSize;
			
			iptr = im->map.addr;
			optr = im->map.emptyAddr;
			tileIptr = im->map.emptyAddr;
		} else {
			tileIptr = iptr;
		}
		for(size_t col=0; col<im->cols; ++col) {
			unsigned char *lastIptr = iptr;
			for(size_t i=0; i<tileDimension; ++i) {
				memcpy(optr, iptr, tileBytesPerRow);
				iptr += im->map.bytesPerRow;
				optr += tileBytesPerRow;
			}
			iptr = lastIptr + tileBytesPerRow;	// move to the next image
		}
		if(useMMAP) {
			//int mret = msync(im->map.emptyAddr, im->map.mappedSize, MS_ASYNC);
			//assert(mret == 0);
			int ret = munmap(im->map.emptyAddr, im->map.mappedSize);
#if MMAP_DEBUGGING == 1
			LOG(@"UNMAP[%d]: addr=%p 0x%X bytes", im->map.fd, im->map.emptyAddr, (NSUInteger)im->map.mappedSize);
#endif
			if(ret) self.failed = YES;
		} else {
			iptr = tileIptr + im->map.emptyTileRowSize;
		}
	}
	//LOG(@"...tile");

	if(!useMMAP) {
		// OK we're done with this memory now
		//int mret = msync(im->map.emptyAddr, im->map.mappedSize, MS_ASYNC);
		//assert(mret == 0);
		int ret = munmap(im->map.emptyAddr, im->map.mappedSize);
#if MMAP_DEBUGGING == 1
		LOG(@"UNMAP[%d]: addr=%p 0x%X bytes", im->map.fd, im->map.emptyAddr, (NSUInteger)im->map.mappedSize);
#endif
		if(ret) self.failed = YES;
        [self writeToFileSystem:im];
	}
	
	return YES;
}

- (void )truncateEmptySpace:(imageMemory *)im
{
	// don't need the scratch space now
	off_t properLen = lseek(im->map.fd, 0, SEEK_END) - im->map.emptyTileRowSize;
	int ret = ftruncate(im->map.fd, properLen);
	if(ret) {
		LOG(@"Failed to truncate file!");
		self.failed = YES;
	}
	im->map.mappedSize = 0;	// force errors if someone tries to use mmap now
}

- (void)createLevelsAndTile
{
	mapper *lastMap = NULL;
	mapper *currMap = NULL;

	for(NSUInteger idx=0; idx < self.zoomLevels; ++idx) {
		lastMap = currMap;	// unused first loop
		currMap = &self.ims[idx].map;
		if(idx) {
			[self mapMemoryForIndex:idx width:lastMap->width/2 height:lastMap->height/2];
			if(self.failed) return;

//dumpIMS("RUN", &ims[idx]);

			// Take every other pixel, every other row, to "down sample" the image. This is fast but has known problems.
			// Got a better idea? Submit a pull request.
			madvise(lastMap->addr, lastMap->mappedSize-lastMap->emptyTileRowSize, MADV_SEQUENTIAL);
			madvise(currMap->addr, currMap->mappedSize-currMap->emptyTileRowSize, MADV_SEQUENTIAL);

			{
				size_t oddColOffset = 0;
				size_t oddRowOffset = 0;
				if(lastMap->col0offset && (lastMap->width & 1)) oddColOffset = bytesPerPixel;			// so rightmost pixels the same
				if(lastMap->row0offset && (lastMap->height & 1)) oddRowOffset = lastMap->bytesPerRow;	// so we use the bottom row
				
				uint32_t *inPtr = (uint32_t *)(lastMap->addr + lastMap->col0offset + oddColOffset + lastMap->row0offset*lastMap->bytesPerRow + oddRowOffset);
				uint32_t *outPtr = (uint32_t *)(currMap->addr + currMap-> col0offset + currMap->row0offset*currMap->bytesPerRow);
				for(size_t row=0; row<currMap->height; ++row) {
					unsigned char *lastInPtr = (unsigned char *)inPtr;
					unsigned char *lastOutPtr = (unsigned char *)outPtr;
					for(size_t col = 0; col < currMap->width; ++col) {
						*outPtr++ = *inPtr;
						inPtr += 2;
					}
					inPtr = (uint32_t *)(lastInPtr + lastMap->bytesPerRow*2);
					outPtr = (uint32_t *)(lastOutPtr + currMap->bytesPerRow);
				}
			}

			madvise(lastMap->addr, lastMap->mappedSize-lastMap->emptyTileRowSize, MADV_FREE);
			madvise(currMap->addr, currMap->mappedSize-currMap->emptyTileRowSize, MADV_FREE);

			// make tiles
			BOOL ret = [self tileBuilder:&self.ims[idx-1] useMMAP:NO];
			if(!ret) goto eRR;
		}
	}
	assert(self.zoomLevels);
	self.failed = ![self tileBuilder:&self.ims[self.zoomLevels-1] useMMAP:NO];
	return;
	
  eRR:
	self.failed = YES;
	return;
}

@end
