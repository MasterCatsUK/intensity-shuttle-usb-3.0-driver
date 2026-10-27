// GPL-2.0-or-later. Real network-style decoder restart/seek; no USB.
#import <Foundation/Foundation.h>
#include "../src/PlayerEngine.hpp"
#include <cassert>
#include <thread>
#include <functional>
static double peak(const std::vector<int32_t>& samples){double out=0;for(auto value:samples)out=std::max(out,std::abs(double(value)));return out;}
int main(int argc,char**argv){@autoreleasepool{
 assert(argc==3);setenv("SHUTTLE_STREAM_TEST_BIN",argv[2],1);NSURL* root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"stream-seek-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];NSURL* file=[root URLByAppendingPathComponent:@"stream.json"];NSDictionary* config=@{@"version":@1,@"duration":@10,@"inputs":@[@{@"url":[NSURL fileURLWithPath:@(argv[1])].absoluteString}],@"video":@0,@"audio":@0};[[NSJSONSerialization dataWithJSONObject:config options:0 error:nil] writeToURL:file atomically:YES];
 for(auto mode:{shuttle_output::Mode::HD1080p25,shuttle_output::Mode::NTSC480i5994}){
  if(mode==shuttle_output::Mode::NTSC480i5994){NSMutableDictionary* separate=[config mutableCopy];separate[@"inputs"]=@[config[@"inputs"][0],config[@"inputs"][0]];separate[@"audio"]=@1;[[NSJSONSerialization dataWithJSONObject:separate options:0 error:nil] writeToURL:file atomically:YES];}
  player::Engine engine(file.path.UTF8String,mode,shuttle_output::Sizing::Stretch,true,true);auto profile=shuttle_output::profile(mode);std::vector<uint8_t> image;std::vector<int32_t> pcm;unsigned wire=0;double worst=0;
  auto render=[&]{auto start=std::chrono::steady_clock::now();engine.render(wire,image,pcm);worst=std::max(worst,std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count());assert(pcm.size()==profile.audioFrames(wire)*8);++wire;};
  auto until=[&](std::function<bool()> ready,int seconds=14){auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(seconds);while(std::chrono::steady_clock::now()<deadline){render();if(ready())return true;std::this_thread::sleep_for(std::chrono::milliseconds(5));}return false;};
  assert(until([&]{return engine.position()>.08;}));engine.command("pause 1");render();auto held=image;auto old=engine.position();
  engine.command("seek 1.04");double target=std::floor(1.04*engine.rate())/engine.rate();
  assert(until([&]{if(std::abs(engine.position()-target)<.001)return true;assert(engine.position()==old&&image==held&&peak(pcm)==0);return false;}));
  assert(image[(size_t(profile.height/2)*profile.width+profile.width/2)*2+1]>220&&peak(pcm)==0);held=image;for(int n=0;n<3;++n){render();assert(image==held&&peak(pcm)==0);}
  engine.command("pause 0");render();assert(peak(pcm)>1000000);held=image;old=engine.position();engine.command("seek 2.04");target=std::floor(2.04*engine.rate())/engine.rate();
  assert(until([&]{if(std::abs(engine.position()-target)<.001)return true;assert(engine.position()==old&&image==held&&peak(pcm)==0);return false;}));assert(image[(size_t(profile.height/2)*profile.width+profile.width/2)*2+1]<40&&peak(pcm)==0);
  engine.command("pause 1");render();held=image;old=engine.position();engine.command("seek 7");render();engine.command("seek 2");render();engine.command("seek 3.08");target=std::floor(3.08*engine.rate())/engine.rate();
  assert(until([&]{if(std::abs(engine.position()-target)<.001)return true;assert(engine.position()==old&&image==held&&peak(pcm)==0);return false;}));assert(image[(size_t(profile.height/2)*profile.width+profile.width/2)*2+1]>220);
  engine.command("pause 0");render();assert(peak(pcm)>1000000);engine.command("seek 9.99");assert(until([&]{return engine.ended;}));engine.command("seek 3.08");engine.command("pause 0");target=std::floor(3.08*engine.rate())/engine.rate();assert(until([&]{return !engine.ended&&std::abs(engine.position()-target)<.001;}));engine.command("seek 9.99");assert(until([&]{return engine.ended;}));engine.command("pause 0");assert(until([&]{return !engine.ended&&engine.position()<.1;}));
  assert(worst<.1);printf("PASS streaming seek mode %d: paused/playing forwards/backwards, latest request wins, aligned picture/audio, EOF/replay; worst render %.4f seconds\n",int(mode),worst);fflush(stdout);
 }
 {NSMutableDictionary* longer=[config mutableCopy];longer[@"duration"]=@12;[[NSJSONSerialization dataWithJSONObject:longer options:0 error:nil] writeToURL:file atomically:YES];player::Engine engine(file.path.UTF8String,shuttle_output::Mode::PAL576i50,shuttle_output::Sizing::Stretch,true,true);std::vector<uint8_t> image;std::vector<int32_t> pcm;engine.command("seek 11.5");bool end=false;auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(14);unsigned wire=0;while(std::chrono::steady_clock::now()<deadline){engine.render(wire++,image,pcm);if(engine.ended){end=true;break;}std::this_thread::sleep_for(std::chrono::milliseconds(5));}assert(end);}
 [[NSJSONSerialization dataWithJSONObject:config options:0 error:nil] writeToURL:file atomically:YES];
 auto start=std::chrono::steady_clock::now();{player::Engine engine(file.path.UTF8String,shuttle_output::Mode::PAL576i50,shuttle_output::Sizing::Stretch,true,true);std::vector<uint8_t> image;std::vector<int32_t> pcm;engine.command("seek 5");engine.render(0,image,pcm);engine.command("stop");assert(engine.stopping);}assert(std::chrono::steady_clock::now()-start<std::chrono::seconds(8));
 [NSFileManager.defaultManager removeItemAtURL:root error:nil];puts("PASS stop/cleanup during pending streaming seek; no USB.");
}}
