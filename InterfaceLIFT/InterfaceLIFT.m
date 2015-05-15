//
//  InterfaceLIFT.m
//  InterfaceLIFT
//
//  Copyright (c) 2012 Matt Rajca. All rights reserved.
//

#import "InterfaceLIFT.h"

#import "Wallpaper.h"

static NSString *const kAPIKey = @"jcAdhn6vlvxiqecaNMo79UsESPicPFFcgNLmmKMJL1GXNkVcLS";
static NSString *const kURLBase = @"https://api.ifl.cc/v1";
static NSString *const kLimit = @"21";
static NSString *const kLatestIDKey = @"MRIL.LatestID";

static NSString *ParamStringWithDictionary(NSDictionary *dictionary) {
	NSMutableString *paramString = [NSMutableString stringWithString:@"?"];
	
	[dictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		[paramString appendFormat:@"%@=%@%@", key, obj, @"&"];
	}];
	
	return [paramString copy];
}

@implementation InterfaceLIFT {
	NSString *_latestID;
	NSOperationQueue *_thumbQueue;
	NSMutableArray *_wallpapers;
	NSUInteger _currentOffset;
	
	NSButton *_nextPageButton;
}

- (instancetype)initWithBundle:(NSBundle *)bundle {
	self = [super initWithBundle:bundle];
	if (self) {
		_wallpapers = [NSMutableArray new];
		
		_thumbQueue = [[NSOperationQueue alloc] init];
		_thumbQueue.maxConcurrentOperationCount = 1;
	}
	return self;
}

- (void)awakeFromNib {
	self.galleryView.footerView = self.nextPageButton;
}

- (NSButton *)nextPageButton {
	if (!_nextPageButton) {
		_nextPageButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 182, 32)];
		_nextPageButton.bezelStyle = NSSmallSquareBezelStyle;
		_nextPageButton.title = @"Load Next Page";
		_nextPageButton.target = self;
		_nextPageButton.action = @selector(loadNextPageOfWallpapers);
	}
	
	return _nextPageButton;
}

- (NSUInteger)numberOfImagesInGalleryView:(GalleryView *)view {
	return _wallpapers.count;
}

- (NSImage *)galleryView:(GalleryView *)view imageAtIndex:(NSUInteger)index {
	return [_wallpapers[index] thumbnail];
}

- (void)galleryView:(GalleryView *)view didSelectCellAtIndex:(NSUInteger)index {
	[[_galleryView imageCellAtIndex:index] showOverlay];
	[self loadWallpaper:_wallpapers[index]];
}

- (void)loadWallpaper:(Wallpaper *)wallpaper {
	NSRect screenRect = [NSScreen mainScreen].frame;
	NSString *resString = [NSString stringWithFormat:@"%dx%d", (int)screenRect.size.width, (int)screenRect.size.height];
	NSString *totalUrl = [NSString stringWithFormat:@"%@/wallpaper_download/%@/%@/", kURLBase, wallpaper.identifier, resString];
	
	NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:totalUrl]];
	[r setValue:kAPIKey forHTTPHeaderField:@"X-IFL-API-Key"];
	[r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	
	[NSURLConnection sendAsynchronousRequest:r queue:[NSOperationQueue mainQueue]
						   completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
							   
							   if (!data) {
								   NSLog(@"Could not fetch wallpaper! Error: %@", error);
								   return;
							   }
							   
							   [self parseWallpaperDownload:data wallpaper:wallpaper];
							   
						   }];
}

- (void)parseWallpaperDownload:(NSData *)data wallpaper:(Wallpaper *)wallpaper {
	NSError *error = nil;
	NSDictionary *wallpaperDownload = [NSJSONSerialization JSONObjectWithData:data
																	  options:0
																		error:&error];
	
	if (!wallpaperDownload) {
		NSLog(@"Could not parse wallpaper download. Error: %@", error);
		return;
	}
	
	NSURL *url = [NSURL URLWithString:wallpaperDownload[@"download_url"]];
	
	NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url];
	[r setValue:kAPIKey forHTTPHeaderField:@"X-IFL-API-Key"];
	[r setValue:@"image/jpeg" forHTTPHeaderField:@"Content-Type"];
	
	[NSURLConnection sendAsynchronousRequest:r queue:[NSOperationQueue mainQueue]
						   completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
							   
							   if (!data) {
								   NSLog(@"Could not fetch wallpaper! Error: %@", error);
								   return;
							   }
							   
							   NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"wallpaper-%@.jpg", wallpaper.identifier]];
							   
							   NSError *dataError = nil;
							   
							   if (![data writeToFile:path options:0 error:&dataError]) {
								   NSLog(@"Could not write wallpaper to disk. Error: %@", dataError);
							   }
							   else {
								   [[NSWorkspace sharedWorkspace] setDesktopImageURL:[NSURL fileURLWithPath:path]
																		   forScreen:[NSScreen mainScreen]
																			 options:nil
																			   error:&dataError];
								   
								   if (dataError) {
									   NSLog(@"Could not set wallpaper. Error: %@", dataError);
								   }
							   }
							   
							   const NSUInteger index = [_wallpapers indexOfObject:wallpaper];
							   [[_galleryView imageCellAtIndex:index] hideOverlay];
							   
						   }];
}

- (BOOL)galleryView:(GalleryView *)view isImageNewAtIndex:(NSUInteger)index {
	Wallpaper *wallpaper = _wallpapers[index];
	return [_latestID compare:wallpaper.identifier options:NSNumericSearch] == NSOrderedAscending;
}

- (NSString *)galleryView:(GalleryView *)view titleForImageAtIndex:(NSUInteger)index {
	Wallpaper *wallpaper = _wallpapers[index];
	return wallpaper.title;
}

- (void)mainViewDidLoad {
	[super mainViewDidLoad];
	
	_latestID = [[[NSUserDefaults standardUserDefaults] stringForKey:kLatestIDKey] copy];
	
	[self loadNextPageOfWallpapers];
}

- (void)loadNextPageOfWallpapers {
	NSMutableDictionary *params = [NSMutableDictionary dictionary];
	params[@"limit"] = kLimit;
	params[@"start"] = [NSString stringWithFormat:@"%ld", _currentOffset];
	params[@"sort_by"] = @"date";
	params[@"sort_order"] = @"desc";
	params[@"tag_id"] = @"614";
	
	NSRect screenRect = [NSScreen mainScreen].frame;
	NSString *resString = [NSString stringWithFormat:@"%dx%d", (int)screenRect.size.width, (int)screenRect.size.height];
	params[@"resolution"] = resString;
	
	NSString *paramString = ParamStringWithDictionary(params);
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/wallpapers/%@", kURLBase, paramString]];
	
	NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url];
	[r setValue:kAPIKey forHTTPHeaderField:@"X-IFL-API-Key"];
	[r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
	
	[NSURLConnection sendAsynchronousRequest:r queue:[NSOperationQueue mainQueue]
						   completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
							   
							   if (!data) {
								   NSLog(@"Could not fetch wallpapers! Error: %@", error);
								   return;
							   }
							   
							   [self parseWallpapersFeed:data];
							   
						   }];
	
	_currentOffset += 21;
}

- (void)parseWallpapersFeed:(NSData *)data {
	NSMutableIndexSet *indices = [NSMutableIndexSet indexSet];
	NSUInteger lastIndex = _wallpapers.count;
	
	NSError *error = nil;
	NSArray *wallpapers = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	
	if (!wallpapers) {
		NSLog(@"Could not parse wallpapers feed. Error: %@", error);
		return;
	}
	
	for (NSDictionary *item in wallpapers){
		NSURL *previewUrl = [NSURL URLWithString:item[@"preview_url"]];
		
		Wallpaper *wallpaper = [[Wallpaper alloc] init];
		wallpaper.identifier = [item[@"id"] stringValue];
		wallpaper.previewURL = previewUrl;
		wallpaper.title = item[@"title"];
		
		[_wallpapers addObject:wallpaper];
		
		[_thumbQueue addOperationWithBlock:^{
			NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:wallpaper.previewURL];
			
			NSError *error = nil;
			NSData *imageData = [NSURLConnection sendSynchronousRequest:request
													  returningResponse:nil
																  error:&error];
			
			if (!imageData) {
				NSLog(@"Could not load preview image. Error: %@", error);
				return;
			}
			
			NSImage *image = [[NSImage alloc] initWithData:imageData];
			
			[[NSOperationQueue mainQueue] addOperationWithBlock:^{
				
				wallpaper.thumbnail = image;
				
				NSUInteger index = [_wallpapers indexOfObject:wallpaper];
				[self.galleryView reloadImageCellAtIndex:index];
				
			}];
		}];
		
		[indices addIndex:lastIndex++];
	}
	
	if (_wallpapers.count > 0) {
		Wallpaper *newestWallpaper = _wallpapers.firstObject;
		
		if (newestWallpaper) {
			[[NSUserDefaults standardUserDefaults] setObject:newestWallpaper.identifier forKey:kLatestIDKey];
			[[NSUserDefaults standardUserDefaults] synchronize];
		}
	}
	
	[self.galleryView insertImagesAtIndices:indices];
}

@end
