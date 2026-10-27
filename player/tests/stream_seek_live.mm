// GPL-2.0-or-later. Public on-demand seek probe through the real Engine; no USB.
#import <Foundation/Foundation.h>
#include "../src/WebVideo.mm"
#include "../src/PlayerEngine.hpp"
#include <thread>
#include <chrono>
#include <cassert>
int main(int argc,char**argv){@autoreleasepool{
 if(argc<3||argc>4)return 64;unsigned sustained=argc==4?unsigned(std::max(0.,atof(argv[3]))*25):0;NSURL* app=[NSURL fileURLWithPath:@(argv[1])];NSURL* bin=[app URLByAppendingPathComponent:@"Contents/MacOS" isDirectory:YES];setenv("SHUTTLE_STREAM_TEST_BIN",bin.path.UTF8String,1);NSURL* root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"stream-seek-live"] isDirectory:YES];__block BOOL done=NO;__block NSURL* config=nil;PlayerWebVideo* job=[PlayerWebVideo new];job.streaming=YES;job.completion=^(NSURL* file,NSString* title,NSString* error){config=file;printf("Resolved %s: %s\n",title.UTF8String?:"",file?"ready":error.UTF8String?:"cancelled");fflush(stdout);done=YES;};[job startURL:playerWebURL(@(argv[2])) tools:[bin URLByAppendingPathComponent:@"WebTools"] worker:[bin URLByAppendingPathComponent:@"ShuttleWebWorker"] cache:root];NSDate* deadline=[NSDate dateWithTimeIntervalSinceNow:90];while(!done&&deadline.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];if(!done){[job cancel];while(!done)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}if(!config)return 1;
 int result=1;try{
 player::Engine engine(config.path.UTF8String,shuttle_output::Mode::HD1080p25,shuttle_output::Sizing::Stretch,true,true);std::vector<uint8_t> image;std::vector<int32_t> audio;unsigned wire=0;double worst=0;
 auto render=[&]{auto start=std::chrono::steady_clock::now();engine.render(wire++,image,audio);worst=std::max(worst,std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count());std::this_thread::sleep_for(std::chrono::milliseconds(10));};
 auto wait=[&](double target){auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(30);while(std::chrono::steady_clock::now()<deadline){render();if(std::abs(engine.position()-target)<.025)return true;}return false;};
 if(!wait(.08))throw std::runtime_error("Initial playback did not start");
 for(auto target:{60.,10.,120.}){bool paused=target==120;engine.command(paused?"pause 1":"pause 0");auto start=std::chrono::steady_clock::now();engine.command(std::string("seek ")+std::to_string(target));if(!wait(target))throw std::runtime_error("Seek did not reach target");double peak=0;
  for(int n=0;n<25;++n){render();for(auto sample:audio)peak=std::max(peak,std::abs(double(sample)));}
  if(paused){for(auto sample:audio)if(sample)throw std::runtime_error("Paused audio not silent");engine.command("pause 0");for(int n=0;n<25;++n){render();for(auto sample:audio)peak=std::max(peak,std::abs(double(sample)));}}
  printf("SEEK %.2f reached in %.2fs; resumed stereo peak %.0f; paused seek %d\n",target,std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count(),peak,paused);fflush(stdout);if(!peak)throw std::runtime_error("No audio after seek");
 }
 if(sustained){unsigned held=0;auto next=std::chrono::steady_clock::now();for(unsigned n=0;n<sustained;++n){double before=engine.position();engine.render(wire++,image,audio);if(engine.position()==before)++held;next+=std::chrono::milliseconds(40);std::this_thread::sleep_until(next);}printf("Post-seek real-time playback %.1fs, held/rebuffer ticks %u\n",sustained/25.,held);if(held)throw std::runtime_error("Post-seek real-time playback stalled");}
 printf("PASS public streaming forward/backward/paused seeks at1080p25; bounded render %.4fs; no USB or full movie cache.\n",worst);result=worst<.1?0:2;
 }catch(const std::exception& e){printf("FAIL %s\n",e.what());}
 if(!result)[NSFileManager.defaultManager removeItemAtURL:job.directory error:nil];return result;
}}
