// GPL-2.0-or-later. Per-picture timeline timecode; never inferred from PTS.
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
namespace shuttle_sink {
struct Timecode {
    uint8_t valid=0,hours=0,minutes=0,seconds=0,frames=0,drop=0,rate=0,reserved=0;
};
static_assert(sizeof(Timecode)==8,"Timecode wire layout");
inline bool validTimecode(const Timecode& t){
    return t.valid==1&&t.hours<24&&t.minutes<60&&t.seconds<60&&
        (t.rate==24||t.rate==25||t.rate==30||t.rate==50||t.rate==60)&&
        t.frames<t.rate&&t.drop<=1&&(!t.drop||(t.rate==30||t.rate==60))&&!t.reserved;
}
inline void timecodeText(const Timecode& t,char (&text)[16]){
    if(!validTimecode(t)){std::snprintf(text,sizeof(text),"--:--:--:--");return;}
    std::snprintf(text,sizeof(text),"%02u:%02u:%02u:%02u%s",t.hours,t.minutes,t.seconds,t.frames,t.drop?" DF":"");
}
enum class TimecodePosition : unsigned {TopLeft,TopRight,BottomRight,BottomLeft,TopCenter,BottomCenter};
inline unsigned validTimecodePosition(long value){return value>=0&&value<6?unsigned(value):5;}
inline unsigned savedTimecodePosition(long value){return value>=1&&value<=6?unsigned(value-1):5;}
struct TimecodeBox {unsigned x,y,width,height;};
void prepareTimecodeOverlay();
TimecodeBox timecodeOverlayBox(unsigned width,unsigned height,const Timecode& code,unsigned position=5);
void overlayTimecode(std::vector<uint8_t>& image,unsigned width,unsigned height,const Timecode& code,unsigned position=5);
}
