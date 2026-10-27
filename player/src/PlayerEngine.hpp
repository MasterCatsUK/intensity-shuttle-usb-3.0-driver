// GPL-2.0-or-later. Shuttle Player, 19 October 2026.
#pragma once
#include "MovieSource.hpp"
#include "StreamingSource.hpp"
#include "PlayerIPC.hpp"
#include <sstream>
#include <limits>
#include <cstdio>
#include <future>
#include <chrono>
namespace player {
class Engine {
    std::string filename;shuttle_output::Mode mode;shuttle_output::Sizing sizing;
    std::unique_ptr<MovieSource> movie;
    std::unique_ptr<StreamingSource> stream;bool streamingMode=false,streamNeedsFrame=false;int streamState=-1;uint64_t streamReport=0;
    std::vector<uint8_t> held;
    std::unique_ptr<Preview> previewScratch;
    uint64_t mediaFrame=0,heldFrame=0;double requestedSeek=-1;
    float gain=1;bool hasHeld=false,asyncSeek=false;
    struct SeekResult {std::unique_ptr<MovieSource> movie;std::vector<uint8_t> picture;std::vector<int32_t> audio;uint64_t frame;};
    std::future<SeekResult> pendingSeek;
    struct StreamSeekResult {std::unique_ptr<StreamingSource> source;uint64_t frame;};
    std::future<StreamSeekResult> pendingStreamSeek;
public:
    bool paused=false,ended=false,loop=false,stopping=false;
    double duration=0;uint64_t generation=0;
    Engine(const std::string& file,shuttle_output::Mode m,shuttle_output::Sizing s,bool asynchronous=false,bool streaming=false):filename(file),mode(m),sizing(s),asyncSeek(asynchronous){
        streamingMode=streaming;if(streaming){stream.reset(new StreamingSource(file,mode,sizing));duration=stream->duration();}else {movie.reset(new MovieSource(file,mode,sizing));duration=movie->duration();}previewScratch.reset(new Preview{});
    }
    double rate()const{auto p=shuttle_output::profile(mode);return double(p.rateNom)/p.rateDen;}
    double position()const{return hasHeld?std::min(duration,double(heldFrame)/rate()):0;}
    void command(const std::string& line){
        std::istringstream in(line);std::string key,extra;double value=0;in>>key;
        if(key=="stop"){if(!(in>>extra))stopping=true;return;}
        if(!(in>>value)||!std::isfinite(value)||(in>>extra))return;
        if(streamingMode&&key=="loop")return;
        if(key=="pause"){paused=value!=0;if(!paused&&ended){requestedSeek=0;ended=false;}}
        else if(key=="seek"){requestedSeek=std::max(0.0,std::min(duration,value));if(streamingMode)ended=false;}
        else if(key=="volume")gain=float(std::max(0.0,std::min(1.0,value)));
        else if(key=="loop")loop=value!=0;
    }
    void render(uint64_t wireFrame,std::vector<uint8_t>& picture,std::vector<int32_t>& pcm){
        auto p=shuttle_output::profile(mode);
        if(streamingMode){
            if(pendingStreamSeek.valid()&&pendingStreamSeek.wait_for(std::chrono::seconds(0))==std::future_status::ready){
                auto result=pendingStreamSeek.get();stream=std::move(result.source);
                if(requestedSeek<0){mediaFrame=result.frame;streamNeedsFrame=true;ended=false;}
            }
            if(requestedSeek>=0&&!pendingStreamSeek.valid()){
                const uint64_t count=std::max<uint64_t>(1,uint64_t(std::ceil(duration*rate())));
                uint64_t target=std::min(count-1,uint64_t(std::floor(requestedSeek*rate())));auto file=filename;auto m=mode;auto size=sizing;double seconds=double(target)/rate();
                // Only this background task retires the old decoder. USB keeps held picture/silence.
                pendingStreamSeek=std::async(std::launch::async,[old=std::move(stream),file,m,size,seconds,target]()mutable{
                    StreamSeekResult result;result.frame=target;result.source.reset(new StreamingSource(file,m,size,seconds));old.reset();return result;
                });
                requestedSeek=-1;ended=false;streamNeedsFrame=true;streamState=4;
                printf("STREAM_SEEKING %.9f\n",seconds);fflush(stdout);
            }
            StreamingSource::State state;
            if(pendingStreamSeek.valid()){pcm.clear();}
            else {
                state=stream->read(paused&&!streamNeedsFrame,mediaFrame,held,pcm);
                if(state.advanced){heldFrame=mediaFrame++;hasHeld=true;if(streamNeedsFrame){streamNeedsFrame=false;printf("STREAM_SEEKED %.9f %llu\n",double(heldFrame)/rate(),(unsigned long long)(generation+1));fflush(stdout);}}
                ended=state.ended;if(ended&&streamNeedsFrame){streamNeedsFrame=false;printf("STREAM_SEEK_EMPTY %.9f %llu\n",double(mediaFrame)/rate(),(unsigned long long)(generation+1));fflush(stdout);}
                int status=ended?3:state.buffering?0:paused?2:1;
                if(status!=streamState||(status==0&&wireFrame-streamReport>=uint64_t(rate()/2))){
                    if(status==0)printf("STREAM_BUFFER %.3f video=%.3f audio=%.3f\n",state.buffered,state.videoSeconds,state.audioSeconds);else puts(status==1?"STREAM_PLAYING":status==2?"STREAM_PAUSED":"STREAM_ENDED");fflush(stdout);streamState=status;streamReport=wireFrame;
                }
            }
            if(held.empty()){held.resize(size_t(p.width)*p.height*2);for(size_t n=0;n<held.size();n+=4){held[n]=held[n+2]=128;held[n+1]=held[n+3]=16;}}
            picture=held;pcm.resize(p.audioFrames(wireFrame)*8,0);if(!state.advanced||paused)std::fill(pcm.begin(),pcm.end(),0);else if(gain!=1)for(auto& sample:pcm)sample=int32_t(double(sample)*gain);++generation;return;
        }
        const uint64_t count=std::max<uint64_t>(1,uint64_t(std::ceil(duration*rate())));
        bool fresh=false,waiting=false;
        if(pendingSeek.valid()&&pendingSeek.wait_for(std::chrono::seconds(0))==std::future_status::ready){
            auto result=pendingSeek.get();
            if(requestedSeek<0){movie=std::move(result.movie);held=std::move(result.picture);pcm=std::move(result.audio);heldFrame=result.frame;mediaFrame=result.frame+1;hasHeld=true;ended=false;fresh=true;}
        }
        if(requestedSeek>=0&&!pendingSeek.valid()){
            uint64_t target=std::min(count-1,uint64_t(std::floor(requestedSeek*rate())));
            if(asyncSeek){
                auto file=filename;auto m=mode;auto size=sizing;double seconds=double(target)/rate();
                pendingSeek=std::async(std::launch::async,[file,m,size,seconds,target]{
                    SeekResult result;result.frame=target;result.movie.reset(new MovieSource(file,m,size,true,seconds));
                    result.movie->read(unsigned(target),result.picture,result.audio);return result;
                });
            }else{
                mediaFrame=target;movie.reset(new MovieSource(filename,mode,sizing,true,double(mediaFrame)/rate()));hasHeld=false;
            }
            requestedSeek=-1;ended=false;
        }
        waiting=pendingSeek.valid();
        if(!paused&&!ended&&!waiting&&!fresh&&mediaFrame>=count){
            if(loop){
                if(asyncSeek){requestedSeek=0;waiting=true;}
                else {movie.reset(new MovieSource(filename,mode,sizing));mediaFrame=0;hasHeld=false;}
            }else ended=true;
        }
        bool advance=!paused&&!ended&&!waiting;
        if(waiting){if(!hasHeld){held.resize(size_t(p.width)*p.height*2);for(size_t n=0;n<held.size();n+=4){held[n]=held[n+2]=128;held[n+1]=held[n+3]=16;}}pcm.clear();}
        else if(!fresh&&(!hasHeld||advance)){
            movie->read(unsigned(mediaFrame),held,pcm);heldFrame=mediaFrame;hasHeld=true;++mediaFrame;
        }else if(!fresh)pcm.clear();
        picture=held;pcm.resize(p.audioFrames(wireFrame)*8,0);
        if(!advance)std::fill(pcm.begin(),pcm.end(),0);
        else if(gain!=1)for(auto& sample:pcm)sample=int32_t(double(sample)*gain);
        ++generation;
    }
    void publish(Mapping& mapping,const std::vector<uint8_t>& picture,const std::vector<int32_t>& pcm){
        // Convert into reusable private storage before locking shared memory.
        // A busy UI reader can skip a preview publication; it never stalls USB.
        auto p=shuttle_output::profile(mode);auto& out=*previewScratch;
        out.position=ended?duration:position();out.duration=duration;out.paused=paused;out.ended=ended;
        out.left=out.right=0;
        for(size_t n=0;n+1<pcm.size();n+=8){out.left=std::max(out.left,float(std::abs(double(pcm[n]))/8388607));out.right=std::max(out.right,float(std::abs(double(pcm[n+1]))/8388607));}
        const double aspect=p.width*p.pixelAspect()/p.height;
        out.width=Width;out.height=std::min(Height,uint32_t(std::lround(Width/aspect)));
        const bool hd=p.width>720;
        auto clamp=[](double x){return uint8_t(std::max(0.0,std::min(255.0,x)));};
        for(unsigned y=0;y<out.height;++y)for(unsigned x=0;x<out.width;++x){
            unsigned sx=std::min(p.width-1,unsigned(uint64_t(x)*p.width/out.width)),sy=std::min(p.height-1,unsigned(uint64_t(y)*p.height/out.height));
            auto q=&picture[(size_t(sy)*p.width+(sx&~1u))*2];
            double Y=(q[sx%2?3:1]-16)*1.164383,U=int(q[0])-128,V=int(q[2])-128;
            auto d=&out.pixels[(size_t(y)*out.width+x)*4];
            d[0]=clamp(Y+(hd?1.792741:1.596027)*V);d[1]=clamp(Y-(hd?.213249:.391762)*U-(hd?.532909:.812968)*V);d[2]=clamp(Y+(hd?2.112402:2.017232)*U);d[3]=255;
        }
        out.generation=generation;
        if(!mapping.lock())return;
        auto& channel=*mapping.data;
        channel.rateNom=p.rateNom;channel.rateDen=p.rateDen;
        memcpy(&channel.frames[(generation-1)%PreviewFrames],&out,sizeof(Preview));
        channel.published=generation;mapping.unlock();
    }
};
}
