// Explicit native test only, with FCP A/V Output off and matching sender ready.
// Injects 01:02:03:00 onward as actual per-buffer SMPTE metadata, independent
// of PTS. Uses the existing cached-device native regression and its watchdog.
#import <CoreMediaIO/CoreMediaIO.h>
#import <CoreMediaIO/CMIOSampleBuffer.h>
#import <CoreAudio/CoreAudioTypes.h>
static OSStatus EnqueueWithTimecode(CMSimpleQueueRef queue,const void* object){
    auto sample=(CMSampleBufferRef)object;UInt64 seq=CMIOSampleBufferGetSequenceNumber(sample);
    unsigned frame=unsigned(seq%1000000);SMPTETime time{};time.mType=kSMPTETimeType25;time.mFlags=kSMPTETimeValid;
    time.mHours=1;time.mMinutes=2;time.mSeconds=3+frame/25;time.mFrames=frame%25;
    auto data=CFDataCreate(nullptr,reinterpret_cast<UInt8*>(&time),sizeof(time));
    CMSetAttachment(sample,kCMIOSampleBufferAttachmentKey_SMPTETime,data,kCMAttachmentMode_ShouldPropagate);CFRelease(data);
    return CMSimpleQueueEnqueue(queue,object);
}
#define CMSimpleQueueEnqueue EnqueueWithTimecode
#define main TimecodeSinkRegressionMain
#include "RestartTest.mm"
#undef main
#undef CMSimpleQueueEnqueue
int main(int argc,char** argv){return TimecodeSinkRegressionMain(argc,argv);}
