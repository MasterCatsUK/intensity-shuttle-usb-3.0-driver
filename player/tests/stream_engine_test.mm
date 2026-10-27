// GPL-2.0-or-later. Actual streaming Engine/preview/controls; no USB.
#import <Foundation/Foundation.h>
#include "../src/PlayerEngine.hpp"
#include <cassert>
#include <thread>
int main(int argc,char**argv){@autoreleasepool{
 assert(argc==3);setenv("SHUTTLE_STREAM_TEST_BIN",argv[2],1);NSURL* root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"shuttle-stream-engine-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];NSURL* file=[root URLByAppendingPathComponent:@"stream.json"];NSDictionary* config=@{@"version":@1,@"duration":@10,@"inputs":@[@{@"url":[NSURL fileURLWithPath:@(argv[1])].absoluteString}],@"video":@0,@"audio":@0};[[NSJSONSerialization dataWithJSONObject:config options:0 error:nil] writeToURL:file atomically:YES];
 {
 player::Engine engine(file.path.UTF8String,shuttle_output::Mode::PAL576i50,shuttle_output::Sizing::Stretch,true,true);engine.command("loop 1");assert(!engine.loop);engine.command("volume .5");std::vector<uint8_t> image;std::vector<int32_t> audio;bool checked=false;unsigned wire=0;auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(25);
 while(!engine.ended&&std::chrono::steady_clock::now()<deadline){auto begin=std::chrono::steady_clock::now();engine.render(wire++,image,audio);assert(std::chrono::steady_clock::now()-begin<std::chrono::milliseconds(100));assert(image.size()==720*576*2&&audio.size()==1920*8);
  if(!checked&&engine.position()>=1.04){double peak=0;for(auto sample:audio)peak=std::max(peak,std::abs(double(sample)));assert(engine.position()<1.12&&peak>900000&&peak<1200000);assert(image[(288*720+360)*2+1]>220);auto held=image;auto position=engine.position();engine.command("pause 1");engine.render(wire++,image,audio);assert(image==held&&engine.position()==position);for(auto sample:audio)assert(sample==0);engine.command("volume 0");engine.command("pause 0");checked=true;}
  if(checked)for(auto sample:audio)assert(sample==0);std::this_thread::sleep_for(std::chrono::milliseconds(1));
 }
 assert(checked&&engine.ended&&engine.position()>9.9);auto held=image;engine.render(wire++,image,audio);assert(image==held&&engine.ended);engine.command("stop");assert(engine.stopping);
 player::Mapping map([root URLByAppendingPathComponent:@"preview"].fileSystemRepresentation,true);engine.publish(map,image,audio);assert(map.lock());assert(map.data->published==engine.generation);map.unlock();
 }
 [NSFileManager.defaultManager removeItemAtURL:root error:nil];puts("PASS: streaming Engine uses paired frames/audio, ignores Loop, gain/mute, pause/hold/resume, wire cadence, bounded render, EOF hold, Stop and preview IPC. No USB.");
}}
