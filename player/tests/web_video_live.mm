// GPL-2.0-or-later. Explicit URL preparation probe, never opens USB or changes routes.
#import <AVFoundation/AVFoundation.h>
#include "../src/WebVideo.mm"
#include <cstdio>
int main(int argc,char**argv){@autoreleasepool{
 if(argc!=3)return 64;NSURL* app=[NSURL fileURLWithPath:@(argv[1])];NSURL* bin=[app URLByAppendingPathComponent:@"Contents/MacOS" isDirectory:YES];NSURL* cache=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"shuttle-web-live-test"] isDirectory:YES];
 __block BOOL done=NO;__block int status=1;PlayerWebVideo* job=[PlayerWebVideo new];job.progress=^(NSString* s,double percent){printf("%s\n",s.UTF8String);fflush(stdout);};job.completion=^(NSURL* file,NSString* title,NSString* error){if(file){AVURLAsset* a=[AVURLAsset URLAssetWithURL:file options:nil];printf("RESULT title=%s duration=%.3f video=%lu audio=%lu\nFILE %s\n",title.UTF8String,CMTimeGetSeconds(a.duration),(unsigned long)[a tracksWithMediaType:AVMediaTypeVideo].count,(unsigned long)[a tracksWithMediaType:AVMediaTypeAudio].count,file.path.UTF8String);status=([a tracksWithMediaType:AVMediaTypeVideo].count&&[a tracksWithMediaType:AVMediaTypeAudio].count&&CMTimeGetSeconds(a.duration)>0)?0:2;}else printf("ERROR %s\n",error.UTF8String?:"cancelled");done=YES;};
 [job startURL:playerWebURL(@(argv[2])) tools:[bin URLByAppendingPathComponent:@"WebTools"] worker:[bin URLByAppendingPathComponent:@"ShuttleWebWorker"] cache:cache];NSDate* deadline=[NSDate dateWithTimeIntervalSinceNow:180];while(!done&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];if(!done){[job cancel];while(!done)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}return status;
}}
