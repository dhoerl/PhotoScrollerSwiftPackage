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

#import <stdatomic.h>

#import "PhotoScrollerCommon.h"
#import "TiledImageBuilder-Private.h"

#if 0	// 0 == no debug, 1 == lots of mesages
#define LOG(...) NSLog(@"TB: " __VA_ARGS__)	   // joins the string here and the first varargs
#else
#define LOG(...)
#endif

static size_t	calcDimension(size_t d) { return(d + (tileDimension-1)) & ~(tileDimension-1); }
static size_t	calcBytesPerRow(size_t row) { return calcDimension(row) * bytesPerPixel; }

static BOOL dump_memory_usage(struct task_basic_info *info);
static uint64_t freeFileSpace();
static freeMemory memoryStats();

#ifndef NDEBUG
//static void dumpMapper(const char *str, mapper *m)
//{
//	printf("MAP: %s\n", str);
//	printf(" fd = %d\n", m->fd);
//	printf(" emptyAddr = %p\n", m->emptyAddr);
//	printf(" addr = %p\n", m->addr);
//	printf(" mappedSize = %lu\n", m->mappedSize);
//	printf(" height = %lu\n", m->height);
//	printf(" width = %lu\n", m->width);
//	printf(" bytesPerRow = %lu\n", m->bytesPerRow);
//	printf(" emptyTileRowSize = %lu\n", m->emptyTileRowSize);
//	putchar('\n');
//}
#endif

#ifndef NDEBUG
//static void dumpIMS(const char *str, imageMemory *i)
//{
//	printf("IMS: %s\n", str);
//	dumpMapper("map:", &i->map);
//
//	printf(" idx = %ld\n", i->index);
//	printf(" cols = %ld\n", i->cols);
//	printf(" rows = %ld\n", i->rows);
//	printf(" outline = %ld\n", i->outLine);
//	printf(" col = %ld\n", i->col);
//	printf(" row = %ld\n", i->row);
//	putchar('\n');
//}
#endif

// Create one and use it everywhere
static CGColorSpaceRef colorSpace;

// Compliments to Rainer Brockerhoff
static uint64_t DeltaMAT(uint64_t then, uint64_t now)
{
	uint64_t delta = now - then;

	/* Get the timebase info */
	mach_timebase_info_data_t info;
	mach_timebase_info(&info);

	/* Convert to nanoseconds */
	delta *= info.numer;
	delta /= info.denom;

	return (uint64_t)((double)delta / 1e6); // ms
}

/*
 * We use a dispatch_grpoup so we can "block" on access to it, when memory pressure looks high.
 * A heuritc is employed: the max of some percentage of free memory or a lower percentage of all memory
 * The queue is simply used as a place to attach the group to - you cannot suspend or resume a group
 * The suspended flag sets and resets the current queue state.
 * When a file is sync'd to disk, usage goes up by its size, and decremented when the sync is complete.
 * The ratio is used to compute a threshold (see the code).
 */

static atomic_int_fast64_t	ubc_usage = ATOMIC_VAR_INIT(0); // rough idea of what our buffer cache usage is
static dispatch_semaphore_t ucbSema;
static float				ubc_threshold_ratio;

@implementation TiledImageBuilder
{
	NSString			*_imagePath;
	BOOL				mapWholeFile;
	NSMutableData		*bufferedData;
	NSStreamStatus		_streamStatus;
	NSError				*_streamError;
	BOOL				_hasSpaceAvailable;
	BOOL				preDeterminedLevels;
}

+ (void)initialize
{
	if(self == [TiledImageBuilder class]) {
		colorSpace = CGColorSpaceCreateDeviceRGB();
		ubc_threshold_ratio = 0.5f;					// default ratio - can override with class method below
		ucbSema = dispatch_semaphore_create(1);		// See "mapMemoryForIndex" - wait for this to be "1"
	}
}

+ (CGColorSpaceRef)colorSpace
{
	return colorSpace;
}

+ (void)setUbcThreshold:(float)val
{
	ubc_threshold_ratio = val;
}

+ (int64_t)ubcUsage
{
	return atomic_load(&ubc_usage);
}
+ (void)updateUbc:(int64_t)value {
	atomic_fetch_add(&ubc_usage, value);

	LOG(@"UBC=%lld M", self.ubcUsage/(1024*1024));
}
//+ (bool)compareFlushGroupSuspendedExpected:(bool )expectedValue desired:(bool)desired {
//	  bool expected = expectedValue;
//	  //bool *expectedP = expected ? &atomicTrue : &atomicFalse;
//	  return atomic_compare_exchange_strong(&fileFlushGroupSuspended, &expected, desired);
//}

- (instancetype)initWithSize:(CGSize)sz
{
	self = [self initWithSize:sz orientation:0];
	return self;
}

- (instancetype)initWithSize:(CGSize)sz orientation:(NSInteger)orient /* queue:(dispatch_queue_t)queue	delegate:(NSObject<NSStreamDelegate> *)del */
{
	self = [super init];
	_size = sz;
	_orientation = orient;
	[self commonInit];
	return self;
}

- (void)commonInit {
#if TIMING_STATS == 1 && !defined(NDEBUG)
	_startTime = [self timeStamp];
#endif
	bufferedData	= [NSMutableData new];
	_streamStatus	= NSStreamStatusNotOpen;
	_pageSize		 = getpagesize();

	freeMemory fm = [self freeMemory:@"Initialize"];
	float freeThresh = (float)fm.freeMemory*ubc_threshold_ratio;
	_ubc_threshold = (int64_t)lrintf(freeThresh);
	LOG(@"B: freeThresh=%ld ubc_thresh=%ld", (long)(freeThresh/(1024*1024)), (long)(_ubc_threshold/(1024*1024)));
	LOG(@"C: freeFileSpace=%lld", freeFileSpace());
	_src_mgr = calloc(1, sizeof(co_jpeg_source_mgr));
}

- (instancetype)initWithLevels:(NSInteger)levels
{
	self = [self initWithLevels:levels orientation:0];
	return self;
}

- (instancetype)initWithLevels:(NSInteger)levels orientation:(NSInteger)orient
{
	self = [super init];

	assert(levels > 0);
	_zoomLevels = levels;
	_ims = calloc(_zoomLevels, sizeof(imageMemory));

	_orientation = orient;
	[self commonInit];
	return self;
}

- (void)dealloc
{
	[self cancel];
}

- (void)cancel
{
	self.isCancelled = YES;
	_streamStatus = NSStreamStatusError;

	//[[NSNotificationCenter defaultCenter] removeObserver:self];
	if(_ims) {
		for(NSUInteger idx=0; idx<_zoomLevels;++idx) {
			int fd = _ims[idx].map.fd;
			if(fd>0) close(fd);
		}
		free(_ims); _ims = nil;
	}

	if(_imageFile) { fclose(_imageFile); _imageFile = nil; }
	if(_imagePath) { unlink([_imagePath fileSystemRepresentation]); _imagePath = nil; }
	if(_src_mgr) {
		if(_src_mgr->cinfo.src) { jpeg_destroy_decompress(&_src_mgr->cinfo); }
		free(_src_mgr); _src_mgr = nil;
	}
}

#if 0
- (void)lowMemory:(NSNotification *)note
{
	LOG(@"YIKES LOW MEMORY: ubc_threshold=%lld ubc_usage=%lld", _ubc_threshold, [TiledImageBuilder ubcUsage]);
	_ubc_threshold = (int32_t)lrintf((float)_ubc_threshold * ubc_threshold_ratio);
	
	[self freeMemory:@"Yikes!"];
}		
#endif

- (NSUInteger)zoomLevelsForSize:(CGSize)imageSize;
{
	int zLevels = 1;	// Must always have "1"
	while(YES) {
		imageSize.width /= 2.0f;
		imageSize.height /= 2.0f;
		//LOG(@"zoomLevelsForSize: TEST IF reducedHeight=%f <= height=%f || reductedWidth=%f < width=%f zLevels=%d", imageSize.height, size.height, imageSize.width, size.width, zLevels);
		
		// We don't want to define levels that could only be magnified when viewed, not reduced.
		if(imageSize.height < _size.height || imageSize.width < _size.width) break;
		++zLevels;
	}
	//LOG(@"ZLEVELS=%d", zLevels);
	return zLevels;
}

- (int)createTempFile:(BOOL)unlinkFile size:(size_t)sz
{
	char *template = strdup([[NSTemporaryDirectory() stringByAppendingPathComponent:@"imXXXXXX"] fileSystemRepresentation]);
	int fd = mkstemp(template);
	//LOG(@"CREATE TMP FILE: %s fd=%d", template, fd);
	if(fd == -1) {
		_failed = YES;
		LOG(@"OPEN failed file %s %s", template, strerror(errno));
	} else {
		if(unlinkFile) {
			unlink(template);	// so it goes away when the fd is closed or on a crash

			int ret = fcntl(fd, F_RDAHEAD, 0);	// don't clog up the system's disk cache
			if(ret == -1) {
				LOG(@"Warning: cannot turn off F_RDAHEAD for input file (errno %s).", strerror(errno) );
			}

			fstore_t fst;
			fst.fst_flags	   = 0;					/* iOS10 broke F_ALLOCATECONTIG;*/	// could add F_ALLOCATEALL?
			fst.fst_posmode	   = F_PEOFPOSMODE;		// allocate from EOF (0)
			fst.fst_offset	   = 0;					// offset relative to the EOF
			fst.fst_length	   = sz;
			fst.fst_bytesalloc = 0;					// why not but is not needed

			ret = ftruncate(fd, sz);				// Now the file is there for sure
			if(ret == -1) {
				LOG(@"Warning: cannot ftruncate input file (errno %s).", strerror(errno) );
			}
		} else {
			_imagePath = [NSString stringWithCString:template encoding:NSASCIIStringEncoding];
			
			int ret = fcntl(fd, F_NOCACHE, 1);	// don't clog up the system's disk cache
			if(ret == -1) {
				LOG(@"Warning: cannot turn off cacheing for input file (errno %s).", strerror(errno) );
			}
		}
	}
	free(template);

	return fd;
}
- (void)mapMemoryForIndex:(size_t)idx width:(size_t)w height:(size_t)h
{
	// Don't open another file til memory pressure has dropped
	assert(!NSThread.isMainThread);
	//dispatch_group_wait(fileFlushGroup, DISPATCH_TIME_FOREVER);
	dispatch_semaphore_wait(ucbSema, DISPATCH_TIME_FOREVER);	// decrements
	dispatch_semaphore_signal(ucbSema);							// restores old value


	imageMemory *imsP = &_ims[idx];
	
	imsP->map.width = w;
	imsP->map.height = h;
	
	imsP->index = idx;
	imsP->rows = calcDimension(imsP->map.height)/tileDimension;
	imsP->cols = calcDimension(imsP->map.width)/tileDimension;
	[self mapMemory:&imsP->map];
	
	{
		BOOL colOffset = NO;
		BOOL rowOffset = NO; 
		switch(_orientation) {
		case 0:
		case 1:
		case 5:
			break;
		case 2:
		case 8:
			colOffset = YES;
			break;
		case 3:
		case 7:
			colOffset = YES;
			rowOffset = YES;
			break;
		case 4:
		case 6:
			rowOffset = YES;
			break;
		}
		if(colOffset) {
			imsP->map.col0offset = imsP->map.bytesPerRow - imsP->map.width*bytesPerPixel;
		}
		if(rowOffset) {
			imsP->map.row0offset = imsP->rows * tileDimension - imsP->map.height;
			// LOG(@"ROW OFFSET = %ld", imsP->map.row0offset);
		}
		if(_orientation >= 5 && _orientation <= 8) imsP->rotated = YES;
	}
}

- (void)mapMemory:(mapper *)mapP
{
	mapP->bytesPerRow = calcBytesPerRow(mapP->width);
	mapP->emptyTileRowSize = mapP->bytesPerRow * tileDimension;
	mapP->mappedSize = mapP->bytesPerRow * calcDimension(mapP->height) + mapP->emptyTileRowSize;
	// LOG(@"CALC: %lu", calcDimension(mapP->height));

	//dumpMapper("Yikes!", mapP);

	//LOG(@"mapP->fd = %d", mapP->fd);
	if(mapP->fd <= 0) {
		//LOG(@"Was 0 so call create");
		mapP->fd = [self createTempFile:YES size:mapP->mappedSize];
		if(mapP->fd == -1) return;
	}

	if(mapWholeFile && !mapP->emptyAddr) {	
		mapP->emptyAddr = mmap(NULL, mapP->mappedSize, PROT_READ | PROT_WRITE, MAP_FILE | MAP_SHARED | MAP_NOCACHE, mapP->fd, 0);	//	| MAP_NOCACHE
		mapP->addr = mapP->emptyAddr + mapP->emptyTileRowSize;
		if(mapP->emptyAddr == MAP_FAILED) {
			_failed = YES;
			LOG(@"FAILED to allocate %lu bytes - errno3=%s", mapP->mappedSize, strerror(errno) );
			mapP->emptyAddr = NULL;
			mapP->addr = NULL;
			mapP->mappedSize = 0;
		}
#if MMAP_DEBUGGING == 1
		LOG(@"MMAP[%d]: addr=%p 0x%X bytes", mapP->fd, mapP->emptyAddr, (NSUInteger)mapP->mappedSize);
#endif
	}
}

- (CGSize)imageSize
{
	switch(self.orientation) {
	case 5:
	case 6:
	case 7:
	case 8:
		return CGSizeMake(_ims[0].map.height, _ims[0].map.width);
	default:
		return CGSizeMake(_ims[0].map.width, _ims[0].map.height);
	}
}

- (void)drawImage:(CGImageRef)image
{
	if(image && !_failed) {
		assert(_ims[0].map.addr);

#if MEMORY_DEBUGGING == 1
		[self freeMemory:@"drawImage start"];
#endif
		madvise(_ims[0].map.addr, _ims[0].map.mappedSize-_ims[0].map.emptyTileRowSize, MADV_SEQUENTIAL);

		unsigned char *addr = _ims[0].map.addr + _ims[0].map.col0offset + _ims[0].map.row0offset*_ims[0].map.bytesPerRow;
		CGContextRef context = CGBitmapContextCreate(addr, _ims[0].map.width, _ims[0].map.height, bitsPerComponent, _ims[0].map.bytesPerRow, colorSpace,
			kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);	// kCGImageAlphaNoneSkipFirst kCGImageAlphaNoneSkipLast	  kCGBitmapByteOrder32Big kCGBitmapByteOrder32Little
		assert(context);
		CGContextSetBlendMode(context, kCGBlendModeCopy); // Apple uses this in QA1708
		CGRect rect = CGRectMake(0, 0, _ims[0].map.width, _ims[0].map.height);
		CGContextDrawImage(context, rect, image);
		CGContextRelease(context);

		madvise(_ims[0].map.addr, _ims[0].map.mappedSize-_ims[0].map.emptyTileRowSize, MADV_FREE); // MADV_DONTNEED
#if MEMORY_DEBUGGING == 1
		[self freeMemory:@"drawImage done"];
#endif
	}
}

#pragma mark Memory Management

- (void)writeToFileSystem:(imageMemory *)im {
	// don't need the scratch space now
	[self truncateEmptySpace:im];

	int fd = im->map.fd;
	assert(fd != -1);
	size_t file_size = lseek(fd, 0, SEEK_END);
	[TiledImageBuilder updateUbc:file_size];

	int64_t threshold = self.ubc_threshold;

	BOOL didWait;
	if([TiledImageBuilder ubcUsage] > threshold) {
		dispatch_semaphore_wait(ucbSema, 0);
		didWait = YES;
	} else {
		didWait = NO;
	}

	__typeof__(self) __weak weakSelf = self;
	//dispatch_group_async(fileFlushGroup, fileFlushQueue, ^
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^
		{
			// Always do this - keep the usage correct even if cancelled
			[TiledImageBuilder updateUbc:-file_size];
			if(didWait) { dispatch_semaphore_signal(ucbSema); }

			// only reason for this is to not sync the file if we're getting cancelled
			__typeof__(self) strongSelf = weakSelf;
			if(!strongSelf || strongSelf.isCancelled) return;
			// need to make sure file is kept open til we flush - who knows what will happen otherwise
			int ret = fcntl(fd,	 F_FULLFSYNC);
			if(ret == -1) LOG(@"ERROR: failed to sync fd=%d", fd);
		} );
}

#pragma mark Utilities

- (uint64_t)timeStamp
{
	return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

- (freeMemory)freeMemory:(NSString *)msg {
#ifndef NDEBUG
	LOG(@"%@", msg);
	memoryStats();
#endif
}

@end

#if 0
// http://stackoverflow.com/questions/5182924/where-is-my-ipad-runtime-memory-going
# include <mach/mach.h>
# include <mach/mach_host.h>

void dump_memory_usage() {
  task_basic_info info;
  mach_msg_type_number_t size = sizeof( info );
  kern_return_t kerr = task_info( mach_task_self(), TASK_BASIC_INFO, (task_info_t)&info, &size );
  if ( kerr == KERN_SUCCESS ) {
	LOG( @"task_info: 0x%08lx 0x%08lx\n", info.virtual_size, info.resident_size );
  }
  else {
	LOG( @"task_info failed with error %ld ( 0x%08lx ), '%s'\n", kerr, kerr, mach_error_string( kerr ) );
  }
}
#endif


static BOOL dump_memory_usage(struct task_basic_info *info) {
  mach_msg_type_number_t size = sizeof( struct task_basic_info );
  kern_return_t kerr = task_info( mach_task_self(), TASK_BASIC_INFO, (task_info_t)info, &size );
  return ( kerr == KERN_SUCCESS );
}

static uint64_t freeFileSpace() {
	// http://stackoverflow.com/questions/5712527
	float totalFreeSpace = 0;
	__autoreleasing NSError *error = nil;
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error: &error];

	if (dictionary) {
		NSNumber *freeFileSystemSizeInBytes = [dictionary objectForKey:NSFileSystemFreeSize];
		totalFreeSpace = [freeFileSystemSizeInBytes unsignedLongLongValue];
	} else {
		LOG(@"Error Obtaining System Memory Info: Domain = %@, Code = %ld", [error domain], (long)[error code]);
	}

	return totalFreeSpace;
}

static freeMemory memoryStats() {
	// http://stackoverflow.com/questions/5012886
	mach_port_t host_port;
	mach_msg_type_number_t host_size;
	vm_size_t pagesize;
	freeMemory fm = { 0, 0, 0, 0, 0 };

	host_port = mach_host_self();
	host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
	host_page_size(host_port, &pagesize);

	vm_statistics_data_t vm_stat;

	if (host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size) != KERN_SUCCESS) {
		LOG(@"Failed to fetch vm statistics");
	} else {
		/* Stats in bytes */
		uint64_t mem_used = (uint64_t)((vm_stat.active_count + vm_stat.wire_count) * pagesize);
		uint64_t mem_free = (uint64_t)((vm_stat.free_count + vm_stat.inactive_count) * pagesize);
		uint64_t mem_total = mem_used + mem_free;

		fm.freeMemory = mem_free;
		fm.usedMemory = mem_used;
		fm.totlMemory = mem_total;

		struct task_basic_info info;
		if(dump_memory_usage(&info)) {
			fm.resident_size = info.resident_size;
			fm.virtual_size = info.virtual_size;
		}

		LOG(@"%@:	"
			"total: %lu "
			"used: %lu "
			"FREE: %lu "
			"  [resident=%lu virtual=%lu]",
			msg,
			(unsigned long)mem_total,
			(unsigned long)mem_used,
			(unsigned long)mem_free,
			(unsigned long)fm.resident_size,
			(unsigned long)fm.virtual_size
		);
	}
	return fm;
}

@implementation TiledImageBuilder (NSStreamDelegate)

- (NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len {
	if(len == 0 || _streamStatus != NSStreamStatusOpen) { LOG(@"TIB BOGUS WRITE"); return 0; }
	_streamStatus = NSStreamStatusWriting;

	// We need to get enough to decompress the header. If its not enought, buffer the data
	NSData *data;
	NSData *thisData = [[NSData alloc] initWithBytes:buffer length:len];
	if([bufferedData length]) {
		[bufferedData appendData:thisData];
		data = bufferedData;
		LOG(@"TIB BUFFERED WRITE %d", (int)bufferedData.length);
	} else {
		LOG(@"TIB INPUT WRITE %d", (int)thisData.length);
		data = thisData;
	}


	BOOL consumed = [self jpegAdvance:data];
	if(consumed) {
		[bufferedData setLength:0];
	} else {
		if([bufferedData length] == 0) {
			[bufferedData appendData:thisData];
		}
	}
	if(self.failed) {
		_streamStatus = NSStreamStatusError;
	} else
	if(self.finished) {
		_streamStatus = NSStreamStatusAtEnd;
	} else {
		_streamStatus = NSStreamStatusOpen;
	}
	return len;
}

- (void)open {
	LOG(@"TIB OPEN");
	[self jpegInitNetwork];
	_streamStatus = NSStreamStatusOpen;
}

- (void)close {
	if( _streamStatus != NSStreamStatusOpen) { return; }
	_streamStatus = NSStreamStatusClosed;
}

- (nullable id)propertyForKey:(NSStreamPropertyKey)key { return nil; }
- (BOOL)setProperty:(nullable id)property forKey:(NSStreamPropertyKey)key { }

- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode { return nil; }
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSRunLoopMode)mode { return nil; }

- (BOOL)hasSpaceAvailable {
	return _hasSpaceAvailable;
}

- (NSStreamStatus)streamStatus {
	return _streamStatus;
}
- (NSError *)streamError {
	return _streamError;
}

@end
