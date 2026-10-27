// GPL-2.0-or-later. Controlled producer starvation/cancellation; never opens USB.
#import <Foundation/Foundation.h>
#include "../src/StreamingSource.hpp"
#include <cassert>
#include <chrono>
#include <thread>
#include <cstdio>
int main(int argc,char**argv){@autoreleasepool{
 assert(argc==2);setenv("SHUTTLE_STREAM_TEST_BIN",argv[1],1);
 NSURL* root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"shuttle-stream-stall-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];NSURL* file=[root URLByAppendingPathComponent:@"stream.json"];
 NSDictionary* config=@{@"version":@1,@"duration":@7.2,@"inputs":@[@{@"url":@"file:///dev/null"}],@"video":@0,@"audio":@0};[[NSJSONSerialization dataWithJSONObject:config options:0 error:nil] writeToURL:file atomically:YES];
 unsigned frames=0;bool starvation=false,resumed=false,ended=false;std::vector<uint8_t> image,held;std::vector<int32_t> audio;
 {
  StreamingSource source(file.path.UTF8String,shuttle_output::Mode::PAL576i50,shuttle_output::Sizing::Stretch);auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(15);
  while(std::chrono::steady_clock::now()<deadline){auto state=source.read(false,frames,image,audio);
   if(state.advanced){if(!frames)assert(state.buffered>=3.);if(starvation)resumed=true;++frames;assert(audio.size()==1920*8&&audio[0]==1048576&&audio[1]==-1048576);held=image;}
   else {assert(audio.empty());if(frames>=80&&frames<180){starvation=true;assert(state.buffering&&image==held);}std::this_thread::sleep_for(std::chrono::milliseconds(3));}
   if(state.ended){ended=true;break;}
  }
 }
 assert(frames==180&&starvation&&resumed&&ended);
 auto start=std::chrono::steady_clock::now();{
  StreamingSource source(file.path.UTF8String,shuttle_output::Mode::PAL576i50,shuttle_output::Sizing::Stretch);auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);while(std::chrono::steady_clock::now()<deadline){auto state=source.read(false,0,image,audio);if(state.advanced)break;std::this_thread::sleep_for(std::chrono::milliseconds(3));}
 }assert(std::chrono::steady_clock::now()-start<std::chrono::seconds(6));
 setenv("SHUTTLE_STREAM_SHORT_AUDIO","1",1);{StreamingSource source(file.path.UTF8String,shuttle_output::Mode::PAL576i50,shuttle_output::Sizing::Stretch);unsigned count=0;bool done=false;auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(8);while(std::chrono::steady_clock::now()<deadline){auto state=source.read(false,count,image,audio);if(state.advanced){if(count>65)for(auto sample:audio)assert(sample==0);++count;}else std::this_thread::sleep_for(std::chrono::milliseconds(2));if(state.ended){done=true;break;}}assert(done&&count==180);}unsetenv("SHUTTLE_STREAM_SHORT_AUDIO");
 setenv("SHUTTLE_STREAM_FAKE_FAIL","1",1);bool failed=false;try{StreamingSource source(file.path.UTF8String,shuttle_output::Mode::PAL576i50,shuttle_output::Sizing::Stretch);for(int n=0;n<500;++n){source.read(false,0,image,audio);std::this_thread::sleep_for(std::chrono::milliseconds(3));}}catch(const std::exception& e){failed=true;}assert(failed);unsetenv("SHUTTLE_STREAM_FAKE_FAIL");
 assert([NSFileManager.defaultManager contentsOfDirectoryAtPath:root.path error:nil].count==1);[NSFileManager.defaultManager removeItemAtURL:root error:nil];
 puts("PASS: 3-second start buffer, forced starvation holds exact picture/silence, refill resumes paired audio/video without losing frames, stereo channels, stop during stall, failed decoder and private pipe cleanup.");
}}
