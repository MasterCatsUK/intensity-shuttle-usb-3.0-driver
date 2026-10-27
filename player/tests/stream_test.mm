// GPL-2.0-or-later. Real decoder/buffer checks. No USB or system audio changes.
#import <Foundation/Foundation.h>
#include "../src/StreamingSource.hpp"
#include <cassert>
#include <chrono>
#include <thread>
#include <cstdio>
static double peak(const std::vector<int32_t>& samples){double v=0;for(auto x:samples)v=std::max(v,std::abs(double(x)));return v;}
int main(int argc,char**argv){@autoreleasepool{
    if(argc!=3)return 64;NSURL* fixture=[NSURL fileURLWithPath:@(argv[1])];setenv("SHUTTLE_STREAM_TEST_BIN",argv[2],1);
    NSURL* root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"shuttle-stream-test-" stringByAppendingString:NSUUID.UUID.UUIDString]] isDirectory:YES];[NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    NSURL* file=[root URLByAppendingPathComponent:@"stream.json"];NSDictionary* config=@{@"version":@1,@"duration":@10,@"inputs":@[@{@"url":fixture.absoluteString}],@"video":@0,@"audio":@0};
    [[NSJSONSerialization dataWithJSONObject:config options:0 error:nil] writeToURL:file atomically:YES];
    for(unsigned test=0;test<9;++test){unsigned mode=test<6?test:2;auto fit=test==6?shuttle_output::Sizing::Fit:test==7?shuttle_output::Sizing::Fill:shuttle_output::Sizing::Stretch;bool silent=test==8;NSMutableDictionary* settings=[config mutableCopy];if(silent)settings[@"audio"]=@(-1);[[NSJSONSerialization dataWithJSONObject:settings options:0 error:nil] writeToURL:file atomically:YES];auto m=shuttle_output::Mode(mode);auto p=shuttle_output::profile(m);double rate=double(p.rateNom)/p.rateDen;
        StreamingSource source(file.path.UTF8String,m,fit);uint64_t count=0;bool sawBuffer=false,flash=false,dark=false,paused=false,finished=false;std::vector<uint8_t> image;std::vector<int32_t> audio;
        auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(30);double worst=0;
        while(std::chrono::steady_clock::now()<deadline){
            auto start=std::chrono::steady_clock::now();auto state=source.read(false,count,image,audio);worst=std::max(worst,std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count());
            static unsigned probes=0;if(count==0&&++probes%500==0){printf("BUFFER video %.3f audio %.3f\n",state.videoSeconds,state.audioSeconds);fflush(stdout);}
            if(state.buffering){sawBuffer=true;assert(!state.advanced&&audio.empty());}
            if(state.advanced){assert(image.size()==size_t(p.width)*p.height*2);assert(audio.size()==p.audioFrames(count)*8);double time=count/rate;
                if(time>=1.04&&time<1.12){assert(image[(size_t(10)*p.width+p.width/2)*2+1]>200);assert(silent?peak(audio)==0:peak(audio)>1000000);unsigned edge=image[(size_t(10)*p.width+2)*2+1];assert((edge<25)==(fit==shuttle_output::Sizing::Fit));flash=true;}
                if(time>=2.04&&time<2.12){assert(image[(size_t(10)*p.width+p.width/2)*2+1]<40);assert(peak(audio)==0);dark=true;}
                if(!paused&&time>1.3){auto held=image;for(int n=0;n<5;++n){auto stopped=source.read(true,count+1,image,audio);assert(!stopped.advanced&&image==held&&peak(audio)==0);}paused=true;}
                ++count;
            }else std::this_thread::sleep_for(std::chrono::milliseconds(2));
            if(state.ended){finished=true;break;}
        }
        printf("STREAM TEST case=%u frames=%llu duration=%.3f maxRead=%.4f flash=%d dark=%d done=%d\n",test,(unsigned long long)count,count/rate,worst,flash,dark,finished);fflush(stdout);
        assert(sawBuffer&&flash&&dark&&paused&&finished&&std::abs(count/rate-10)<2/rate&&worst<.1);
    }
    // Cancellation with full queues must release pipes and descendants promptly.
    auto start=std::chrono::steady_clock::now();{StreamingSource source(file.path.UTF8String,shuttle_output::Mode::HD1080p25,shuttle_output::Sizing::Stretch);std::this_thread::sleep_for(std::chrono::milliseconds(700));}
    assert(std::chrono::steady_clock::now()-start<std::chrono::seconds(7));
    NSArray* remaining=[NSFileManager.defaultManager contentsOfDirectoryAtPath:root.path error:nil];assert(remaining.count==1);[NSFileManager.defaultManager removeItemAtURL:root error:nil];
    puts("PASS: six real streaming modes plus Fit/Fill and silent sources, bounded buffering, aligned flashes/beeps, pause/hold/silence, correct whole frames/stereo cadence, EOF, nonblocking reads and prompt cancellation/pipe cleanup. No USB.");
}}
