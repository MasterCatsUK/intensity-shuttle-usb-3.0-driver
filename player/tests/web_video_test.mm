// GPL-2.0-or-later. No network/USB/subprocesses; exercise URL/args/stream lifecycle.
#import <Foundation/Foundation.h>
#include <cassert>
@interface FakeWebTask:NSObject
@property NSURL* executableURL;
@property NSArray* arguments;
@property id standardInput,standardOutput,standardError;
@property BOOL running;
@property int terminationStatus;
@property int processIdentifier;
@property(copy) void (^terminationHandler)(FakeWebTask*);
@end
static bool launchFails=false;static unsigned launches=0,stops=0;
@implementation FakeWebTask
- (BOOL)launchAndReturnError:(NSError**)error{++launches;self.running=!launchFails;return !launchFails;}
- (void)terminate{++stops;self.running=NO;}
@end
#define NSTask FakeWebTask
#include "../src/WebVideo.mm"
#undef NSTask
static NSData* bytes(NSString* s){return [s dataUsingEncoding:NSUTF8StringEncoding];}
int main(){@autoreleasepool{
 for(NSString* s in @[@"https://youtube.com/watch?v=abc",@"https://m.youtube.com/watch?v=abc",@"youtu.be/abc",@"https://www.dailymotion.com/video/x5kesuj",@"https://dai.ly/x5kesuj",@"https://player.vimeo.com/video/123"]){assert(playerWebURL(s));}
 for(NSString* s in @[@"file:///tmp/a.mp4",@"javascript:alert(1)",@"https://youtube.com.evil.test/a",@"https://notyoutube.com/a",@"https://youtube.com@evil.test/a",@"https://user:secret@vimeo.com/a",@"https://vimeo.com:444/a",@"https://127.0.0.1/a",@"--exec touch /tmp/bad"]){assert(!playerWebURL(s));}
 assert([playerWebURL(@"https://vimeo.com/1234").absoluteString isEqual:@"https://player.vimeo.com/video/1234"]);assert([playerWebURL(@"https://vimeo.com/1234/abc123?autoplay=1").absoluteString containsString:@"h=abc123"]);
 NSURL* root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
 for(NSString* name in @[@"worker",@"yt-dlp",@"ffmpeg",@"ffprobe",@"qjs"]){NSURL* p=[root URLByAppendingPathComponent:name];[bytes(@"fixture") writeToURL:p atomically:YES];[NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0700} ofItemAtPath:p.path error:nil];}
 NSURL* web=playerWebURL(@"https://youtube.com/watch?v=abc&label=$(touch%20/tmp/bad)");NSArray* arguments=playerWebArguments(web,root,root);assert([arguments.lastObject isEqual:web.absoluteString]);assert([arguments[arguments.count-2] isEqual:@"--"]);assert([arguments containsObject:@"--ignore-config"]&&[arguments containsObject:@"--no-plugin-dirs"]&&[arguments containsObject:@"--no-remote-components"]);
 __block unsigned completed=0;__block NSURL* result=nil;__block NSString* title=nil;__block NSString* error=nil;__block NSString* progress=nil;__block double percent=-2;
 auto make=^{PlayerWebVideo* job=[PlayerWebVideo new];job.completion=^(NSURL* f,NSString* t,NSString* e){++completed;result=f;title=t;error=e;};job.progress=^(NSString* s,double p){progress=s;percent=p;};[job startURL:web tools:root worker:[root URLByAppendingPathComponent:@"worker"] cache:root];return job;};
 PlayerWebVideo* job=make();assert(job.task&&launches==1);NSURL* media=[job.directory URLByAppendingPathComponent:@"video.mp4"];[bytes(@"fixture") writeToURL:media atomically:YES];
 NSString* pathJSON=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:media.path options:NSJSONWritingFragmentsAllowed error:nil] encoding:NSUTF8StringEncoding];
 NSData* output=bytes([NSString stringWithFormat:@"SHUTTLE_PROGRESS: 12.5%%\nSHUTTLE_TITLE:\"Test ü clip\"\nSHUTTLE_FILE:%@\n",pathJSON]);
 for(NSUInteger n=0;n<output.length;n++)[job consume:[output subdataWithRange:NSMakeRange(n,1)]];
 assert([progress containsString:@"12.5%"]&&percent==12.5);
 [job consume:bytes(@"SHUTTLE_PROGRESS: NA%\n")];assert(percent==-1);[job consume:bytes(@"SHUTTLE_PROGRESS: 101%\n")];assert(percent==-1);[job consume:bytes(@"SHUTTLE_PROGRESS: 100%\n")];assert(percent==100);[job consume:bytes(@"[Merger] Merging formats\n")];assert(percent==-1&&[progress containsString:@"picture and sound"]);job.exited=YES;job.exitStatus=0;[job finishIfReady];assert(completed==0);job.eof=YES;[job finishIfReady];[job finishIfReady];assert(completed==1&&[result isEqual:media]&&[title isEqual:@"Test ü clip"]&&!error);
 job=make();[job consume:bytes(@"ERROR: This format is DRM protected\n")];assert([job.lastError containsString:@"protected and cannot"]);[job consume:bytes(@"SHUTTLE_FILE:\"/etc/passwd\"\n")];assert(!job.result);job.exited=job.eof=YES;job.exitStatus=0;NSURL* failed=job.directory;[job finishIfReady];assert(completed==2&&!result&&error&&![NSFileManager.defaultManager fileExistsAtPath:failed.path]);
 job=make();[job cancel];[job cancel];assert(job.cancelled&&stops==1);job.exited=job.eof=YES;job.exitStatus=137;[job finishIfReady];assert(completed==3&&!result&&!error);
 NSDictionary* metadata=@{@"title":@"Stream test",@"duration":@10,@"live_status":@"not_live",@"requested_formats":@[@{@"url":@"https://cdn.example/video.m3u8",@"vcodec":@"avc1",@"acodec":@"none",@"http_headers":@{@"User-Agent":@"public player",@"Cookie":@"not permitted"}},@{@"url":@"https://cdn.example/audio.m4a",@"vcodec":@"none",@"acodec":@"mp4a"}]};
 NSMutableDictionary* unknownAudio=[metadata mutableCopy];NSMutableArray* unknownFormats=[metadata[@"requested_formats"] mutableCopy];NSMutableDictionary* audioFormat=[unknownFormats[1] mutableCopy];[audioFormat removeObjectForKey:@"acodec"];unknownFormats[1]=audioFormat;unknownAudio[@"requested_formats"]=unknownFormats;assert([playerStreamConfig(unknownAudio)[@"audio"] isEqual:@1]);
 NSDictionary* config=playerStreamConfig(metadata);assert(config&&[config[@"video"] isEqual:@0]&&[config[@"audio"] isEqual:@1]);assert(!config[@"inputs"][0][@"headers"][@"Cookie"]);
 NSMutableDictionary* bad=[metadata mutableCopy];bad[@"duration"]=NSNull.null;assert(!playerStreamConfig(bad));bad=[metadata mutableCopy];bad[@"live_status"]=@"is_live";assert(!playerStreamConfig(bad));bad=[metadata mutableCopy];bad[@"requested_formats"]=@[@{@"url":@"file:///etc/passwd",@"vcodec":@"avc1"}];assert(!playerStreamConfig(bad));
 NSArray* streamingArgs=playerStreamArguments(web,root,root);assert([streamingArgs containsObject:@"--skip-download"]&&[streamingArgs containsObject:@"--simulate"]&&[streamingArgs.lastObject isEqual:web.absoluteString]);
 __block BOOL resolved=NO;PlayerWebVideo* stream=[PlayerWebVideo new];stream.streaming=YES;stream.completion=^(NSURL* file,NSString* title,NSString* error){assert(file&&!error);resolved=YES;};[stream startURL:web tools:root worker:[root URLByAppendingPathComponent:@"worker"] cache:root];NSString* json=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:metadata options:0 error:nil] encoding:NSUTF8StringEncoding];[stream consume:bytes([@"SHUTTLE_STREAM:" stringByAppendingFormat:@"%@\n",json])];stream.exited=stream.eof=YES;[stream finishIfReady];assert(resolved&&[stream.result.lastPathComponent isEqual:@"stream.json"]);NSDictionary* saved=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:stream.result] options:0 error:nil];assert([saved isEqual:config]);
 launchFails=true;job=make();assert(completed==4&&job.finished&&!job.task&&error);
 [NSFileManager.defaultManager removeItemAtURL:root error:nil];puts("PASS: supported URLs/shortlinks; rejected local/credential/lookalike URLs; shell-free arguments; split UTF-8/JSON/progress; EOF/exit ordering; one completion; cache containment; failure/cancel cleanup; launch failure. All tasks fake.");
}}
