// GPL-2.0-or-later. Validate Apple's per-buffer SMPTE attachment.
#pragma once
#include "Timecode.hpp"
#include <CoreMediaIO/CMIOSampleBuffer.h>
#include <CoreAudio/CoreAudioTypes.h>
namespace shuttle_sink {
inline Timecode sampleTimecode(CMSampleBufferRef sample){
    Timecode result;auto raw=CMGetAttachment(sample,kCMIOSampleBufferAttachmentKey_SMPTETime,nullptr);
    if(!raw||CFGetTypeID(raw)!=CFDataGetTypeID()||CFDataGetLength(static_cast<CFDataRef>(raw))!=sizeof(SMPTETime))return result;
    SMPTETime t;std::memcpy(&t,CFDataGetBytePtr(static_cast<CFDataRef>(raw)),sizeof(t));
    if(!(t.mFlags&kSMPTETimeValid)||t.mHours<0||t.mHours>23||t.mMinutes<0||t.mMinutes>59||t.mSeconds<0||t.mSeconds>59||t.mFrames<0)return result;
    unsigned rate=0;bool drop=false;
    switch(t.mType){
        case kSMPTETimeType24:case kSMPTETimeType2398:rate=24;break;
        case kSMPTETimeType25:rate=25;break;
        case kSMPTETimeType30:case kSMPTETimeType2997:rate=30;break;
        case kSMPTETimeType30Drop:case kSMPTETimeType2997Drop:rate=30;drop=true;break;
        case kSMPTETimeType50:rate=50;break;
        case kSMPTETimeType60:case kSMPTETimeType5994:rate=60;break;
        case kSMPTETimeType60Drop:case kSMPTETimeType5994Drop:rate=60;drop=true;break;
        default:return result;
    }
    if(unsigned(t.mFrames)>=rate)return result;
    result={1,uint8_t(t.mHours),uint8_t(t.mMinutes),uint8_t(t.mSeconds),uint8_t(t.mFrames),uint8_t(drop),uint8_t(rate),0};return result;
}
}
