// GPL-2.0-or-later. Prepare a single web movie without changing playback/USB.
#import <Foundation/Foundation.h>
#include <signal.h>
#include <cmath>
static NSURL* playerWebURL(NSString* text) {
    text=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!text.length||text.length>4096)return nil;
    if([text rangeOfString:@"://"].location==NSNotFound)text=[@"https://" stringByAppendingString:text];
    NSURLComponents* c=[NSURLComponents componentsWithString:text];NSString* host=c.host.lowercaseString;
    if(![@[@"https",@"http"] containsObject:c.scheme.lowercaseString]||!host.length||c.user||c.password||(c.port&&c.port.integerValue!=443&&c.port.integerValue!=80))return nil;
    BOOL allowed=NO;for(NSString* site in @[@"youtube.com",@"youtu.be",@"youtube-nocookie.com",@"dailymotion.com",@"dai.ly",@"vimeo.com"])if([host isEqual:site]||[host hasSuffix:[@"." stringByAppendingString:site]])allowed=YES;
    if(!allowed)return nil;c.scheme=@"https";c.port=nil;
    // Standard public Vimeo links use its embeddable player without browser login.
    if([@[@"vimeo.com",@"www.vimeo.com"] containsObject:host]){
        NSArray<NSString*>* parts=c.path.pathComponents;NSString* video=parts.count>1?parts[1]:@"";
        BOOL digits=video.length&&[video rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location==NSNotFound;
        if(digits&&(parts.count==2||parts.count==3)){
            NSMutableArray<NSURLQueryItem*>* query=[c.queryItems mutableCopy]?:[NSMutableArray array];
            if(parts.count==3){BOOL hashPresent=NO;for(NSURLQueryItem* item in query)if([item.name isEqual:@"h"])hashPresent=YES;if(!hashPresent)[query addObject:[NSURLQueryItem queryItemWithName:@"h" value:parts[2]]];}
            c.host=@"player.vimeo.com";c.path=[@"/video/" stringByAppendingString:video];c.queryItems=query.count?query:nil;
        }
    }
    return c.URL;
}
static NSArray<NSString*>* playerWebArguments(NSURL* url,NSURL* tools,NSURL* directory) {
    return @[@"--ignore-config",@"--no-plugin-dirs",@"--no-remote-components",@"--no-playlist",@"--playlist-items",@"1",@"--lazy-playlist",@"--cache-dir",[directory URLByAppendingPathComponent:@"extractor-cache"].path,@"--check-formats",@"--no-wait-for-video",@"--match-filter",@"!is_live & !is_upcoming",@"--socket-timeout",@"20",@"--retries",@"3",@"--fragment-retries",@"3",@"--max-filesize",@"4G",@"--hls-prefer-native",@"--concurrent-fragments",@"2",@"--no-simulate",@"--newline",@"--progress",@"--progress-delta",@"0.5",@"--progress-template",@"download:SHUTTLE_PROGRESS:%(progress._percent_str)s",@"--print",@"after_move:SHUTTLE_FILE:%(filepath)j",@"--print",@"after_move:SHUTTLE_TITLE:%(title)j",@"--ffmpeg-location",tools.path,@"--js-runtimes",[@"quickjs:" stringByAppendingString:[tools URLByAppendingPathComponent:@"qjs"].path],@"--format",@"bv*[ext=mp4][vcodec^=avc1][height<=1080]+(ba[ext=m4a]/ba[ext=mp4])/b[ext=mp4][height<=1080]/bv[ext=mp4][vcodec^=avc1][height<=1080]",@"--merge-output-format",@"mp4",@"--remux-video",@"mp4",@"--output",[directory URLByAppendingPathComponent:@"video.%(ext)s"].path,@"--",url.absoluteString];
}
static NSString* playerJSONText(NSString* json) {
    id value=[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingFragmentsAllowed error:nil];return [value isKindOfClass:NSString.class]?value:nil;
}
// Resolve public on-demand streams without downloading the movie or reading cookies.
static NSArray<NSString*>* playerStreamArguments(NSURL* url,NSURL* tools,NSURL* directory) {
    return @[@"--ignore-config",@"--no-plugin-dirs",@"--no-remote-components",@"--no-playlist",@"--playlist-items",@"1",@"--lazy-playlist",@"--cache-dir",[directory URLByAppendingPathComponent:@"extractor-cache"].path,@"--check-formats",@"--no-wait-for-video",@"--match-filter",@"!is_live & !is_upcoming",@"--socket-timeout",@"20",@"--retries",@"3",@"--skip-download",@"--simulate",@"--print",@"SHUTTLE_STREAM:%(.{title,duration,live_status,url,http_headers,requested_formats,vcodec,acodec})j",@"--js-runtimes",[@"quickjs:" stringByAppendingString:[tools URLByAppendingPathComponent:@"qjs"].path],@"--format",@"bv[ext=mp4][vcodec^=avc1][height<=1080]+(ba[ext=m4a]/ba[ext=mp4])/b[ext=mp4][height<=1080]/bv[ext=mp4][vcodec^=avc1][height<=1080]",@"--",url.absoluteString];
}
static NSDictionary* playerStreamConfig(NSDictionary* metadata) {
    if(![metadata isKindOfClass:NSDictionary.class])return nil;
    if(![metadata[@"duration"] isKindOfClass:NSNumber.class])return nil;double duration=[metadata[@"duration"] doubleValue];if(!std::isfinite(duration)||duration<=0)return nil;
    if([@[@"is_live",@"is_upcoming",@"post_live"] containsObject:metadata[@"live_status"]])return nil;
    NSArray* formats=[metadata[@"requested_formats"] isKindOfClass:NSArray.class]?metadata[@"requested_formats"]:@[metadata];
    if(formats.count<1||formats.count>2)return nil;NSMutableArray* inputs=[NSMutableArray array];NSInteger video=-1,audio=-1;
    for(id value in formats){if(![value isKindOfClass:NSDictionary.class])return nil;NSDictionary* format=value;NSString* address=format[@"url"];NSURL* url=[address isKindOfClass:NSString.class]?[NSURL URLWithString:address]:nil;
        if(!url||![@[@"https",@"http"] containsObject:url.scheme.lowercaseString]||!url.host.length||url.user||url.password)return nil;
        NSDictionary* rawHeaders=[format[@"http_headers"] isKindOfClass:NSDictionary.class]?format[@"http_headers"]:metadata[@"http_headers"];
        NSMutableDictionary* headers=[NSMutableDictionary dictionary];if([rawHeaders isKindOfClass:NSDictionary.class])for(NSString* key in @[@"User-Agent",@"Referer",@"Origin",@"Accept"]){NSString* header=rawHeaders[key];if([header isKindOfClass:NSString.class]&&header.length<4096&&[header rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location==NSNotFound)headers[key]=header;}
        NSInteger index=inputs.count;[inputs addObject:@{@"url":address,@"headers":headers}];
        NSString* v=format[@"vcodec"],*a=format[@"acodec"];if([v isKindOfClass:NSString.class]&&![v isEqual:@"none"])video=index;if(![a isEqual:@"none"]&&(([a isKindOfClass:NSString.class]&&a.length)||[v isEqual:@"none"]||formats.count==1))audio=index;
    }
    if(video<0)return nil;return @{@"version":@1,@"duration":@(duration),@"title":[metadata[@"title"] isKindOfClass:NSString.class]?metadata[@"title"]:@"Web video",@"inputs":inputs,@"video":@(video),@"audio":@(audio)};
}
@interface PlayerWebVideo:NSObject
@property NSTask* task;
@property NSURL* directory;
@property NSURL* result;
@property NSString* title;
@property NSString* lastError;
@property NSMutableData* partial;
@property BOOL cancelled,exited,eof,finished;
@property int exitStatus;
@property BOOL streaming;
@property(copy) void (^progress)(NSString*,double);
@property(copy) void (^completion)(NSURL*,NSString*,NSString*);
- (void)startURL:(NSURL*)url tools:(NSURL*)tools worker:(NSURL*)worker cache:(NSURL*)cache;
- (void)cancel;
- (void)consume:(NSData*)data;
- (void)finishIfReady;
@end
@implementation PlayerWebVideo
- (void)startURL:(NSURL*)url tools:(NSURL*)tools worker:(NSURL*)worker cache:(NSURL*)cache {
    if(self.task||self.finished)return;
    url=playerWebURL(url.absoluteString);if(!url){if(self.completion)self.completion(nil,nil,@"Enter a YouTube, Dailymotion or Vimeo video URL.");self.finished=YES;return;}
    for(NSURL* executable in @[worker,[tools URLByAppendingPathComponent:@"yt-dlp"],[tools URLByAppendingPathComponent:@"qjs"],[tools URLByAppendingPathComponent:@"ffmpeg"],[tools URLByAppendingPathComponent:@"ffprobe"]])if(![NSFileManager.defaultManager isExecutableFileAtPath:executable.path]){self.finished=YES;if(self.completion)self.completion(nil,nil,@"Web video tools are missing. Reinstall this version of Shuttle Player.");return;}
    self.directory=[cache URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];NSError* error=nil;
    if(![NSFileManager.defaultManager createDirectoryAtURL:self.directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]){self.finished=YES;if(self.completion)self.completion(nil,nil,@"Could not create the video cache. Check free disk space.");return;}
    self.partial=[NSMutableData data];self.lastError=@"The site did not provide a playable video. Try another public, on-demand video.";
    NSTask* task=[NSTask new];self.task=task;task.executableURL=worker;task.arguments=[@[[tools URLByAppendingPathComponent:@"yt-dlp"].path] arrayByAddingObjectsFromArray:self.streaming?playerStreamArguments(url,tools,self.directory):playerWebArguments(url,tools,self.directory)];task.standardInput=NSFileHandle.fileHandleWithNullDevice;
    NSPipe* output=NSPipe.pipe;task.standardOutput=output;task.standardError=output;
    __weak PlayerWebVideo* owner=self;
    output.fileHandleForReading.readabilityHandler=^(NSFileHandle* handle){NSData* data=handle.availableData;if(!data.length)handle.readabilityHandler=nil;dispatch_async(dispatch_get_main_queue(),^{PlayerWebVideo* job=owner;if(!job||job.finished)return;if(data.length)[job consume:data];else {job.eof=YES;[job finishIfReady];}});};
    task.terminationHandler=^(NSTask* ended){dispatch_async(dispatch_get_main_queue(),^{PlayerWebVideo* job=owner;if(!job||job.finished)return;job.exited=YES;job.exitStatus=ended.terminationStatus;[job finishIfReady];});};
    if(![task launchAndReturnError:&error]){output.fileHandleForReading.readabilityHandler=nil;self.exited=self.eof=YES;self.exitStatus=1;self.lastError=@"Could not start the web video tools. Reinstall Shuttle Player.";[self finishIfReady];}
}
- (void)line:(NSString*)line {
    if(self.streaming&&[line hasPrefix:@"SHUTTLE_STREAM:"]){
        NSData* data=[[line substringFromIndex:15] dataUsingEncoding:NSUTF8StringEncoding];NSDictionary* config=playerStreamConfig([NSJSONSerialization JSONObjectWithData:data options:0 error:nil]);
        if(config){NSURL* path=[self.directory URLByAppendingPathComponent:@"stream.json"];NSData* json=[NSJSONSerialization dataWithJSONObject:config options:0 error:nil];if([json writeToURL:path options:NSDataWritingAtomic error:nil]){[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path.path error:nil];self.result=path;self.title=config[@"title"];}}
        else self.lastError=@"This link cannot be streamed. Try Download first with a public on-demand video.";
    }
    else if([line hasPrefix:@"SHUTTLE_PROGRESS:"]){NSString* percent=[[line substringFromIndex:17] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];double value=0;NSScanner* scanner=[NSScanner scannerWithString:percent];BOOL known=[scanner scanDouble:&value]&&[scanner scanString:@"%" intoString:nil]&&scanner.isAtEnd&&std::isfinite(value)&&value>=0&&value<=100;if(self.progress)self.progress(known?[NSString stringWithFormat:@"Downloading video/audio… %@",percent]:@"Downloading video/audio…",known?value:-1);}
    else if([line hasPrefix:@"SHUTTLE_FILE:"]){NSString* path=playerJSONText([line substringFromIndex:13]);if(path){NSURL* file=[NSURL fileURLWithPath:path];NSString* base=[self.directory.URLByResolvingSymlinksInPath.path stringByAppendingString:@"/"];if([file.URLByResolvingSymlinksInPath.path hasPrefix:base])self.result=file;}}
    else if([line hasPrefix:@"SHUTTLE_TITLE:"])self.title=playerJSONText([line substringFromIndex:14]);
    else if([line containsString:@"ERROR:"]){NSString* lower=line.lowercaseString;
        if([lower containsString:@"drm"]||[lower containsString:@"protected"])self.lastError=@"This video is protected and cannot be opened in Shuttle Player.";
        else if([lower containsString:@"logged"]||[lower containsString:@"login"]||[lower containsString:@"sign in"]||[lower containsString:@"password"]||[lower containsString:@"private"])self.lastError=@"This video needs a sign-in or password. Try a public video.";
        else if([lower containsString:@"format"])self.lastError=@"The site did not offer a compatible MP4 video. Try another video.";
        else if([lower containsString:@"unavailable"]||[lower containsString:@"not available"])self.lastError=@"This video is unavailable. Check the link or try another video.";
        else self.lastError=@"Could not prepare the video. Check the link and internet connection, then try again.";
    }
    else if([line containsString:@"[Merger]"]||[line containsString:@"[VideoRemuxer]"]){if(self.progress)self.progress(@"Preparing picture and sound…",-1);}
}
- (void)consume:(NSData*)data {
    [self.partial appendData:data];NSData* newline=[@"\n" dataUsingEncoding:NSUTF8StringEncoding];
    for(;;){NSRange range=[self.partial rangeOfData:newline options:0 range:NSMakeRange(0,self.partial.length)];if(range.location==NSNotFound)break;NSData* line=[self.partial subdataWithRange:NSMakeRange(0,range.location)];[self.partial replaceBytesInRange:NSMakeRange(0,range.location+1) withBytes:nullptr length:0];NSString* text=[[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];if(text)[self line:text];}
    if(self.partial.length>1024*1024)[self.partial setLength:0];
}
- (void)finishIfReady {
    if(self.finished||!self.exited||!self.eof)return;self.finished=YES;
    if(self.partial.length){NSString* text=[[NSString alloc] initWithData:self.partial encoding:NSUTF8StringEncoding];if(text)[self line:text];}
    self.task=nil;BOOL valid=!self.cancelled&&self.exitStatus==0&&self.result&&[NSFileManager.defaultManager fileExistsAtPath:self.result.path];
    if(!valid&&self.directory)[NSFileManager.defaultManager removeItemAtURL:self.directory error:nil];
    if(self.completion)self.completion(valid?self.result:nil,self.title,valid||self.cancelled?nil:self.lastError);
}
- (void)cancel {
    self.cancelled=YES;if(self.task.running){NSTask* task=self.task;[task terminate];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(self.task==task&&task.running)kill(-task.processIdentifier,SIGKILL);});}
}
@end
