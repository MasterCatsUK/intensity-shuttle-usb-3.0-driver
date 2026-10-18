// GPL-2.0-or-later. Bounded sequential AVFoundation movie decoding.
#import <AVFoundation/AVFoundation.h>
#include "MovieSource.hpp"
#include <cmath>
#include <algorithm>
struct MovieSource::Impl {
    AVAssetReader* reader;
    AVAssetReaderVideoCompositionOutput* video;
    AVAssetReaderAudioMixOutput* audio;
    CMSampleBufferRef pendingAudio=nullptr;
    shuttle_output::Profile profile;
    double seconds;
    std::vector<uint8_t> lastPicture;
    ~Impl(){if(pendingAudio)CFRelease(pendingAudio);[reader cancelReading];}
};
MovieSource::MovieSource(const std::string& file,shuttle_output::Mode mode):impl(new Impl) { @autoreleasepool {
    auto& s=*impl;s.profile=shuttle_output::profile(mode);
    AVURLAsset* asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:@(file.c_str())] options:nil];
    auto tracks=[asset tracksWithMediaType:AVMediaTypeVideo];if(!tracks.count)throw std::runtime_error("The file has no readable video track");
    AVAssetTrack* track=tracks.firstObject;
    s.seconds=CMTimeGetSeconds(asset.duration);if(!std::isfinite(s.seconds)||s.seconds<=0)throw std::runtime_error("Invalid movie duration");
    NSError* error=nil;s.reader=[[AVAssetReader alloc] initWithAsset:asset error:&error];
    if(!s.reader)throw std::runtime_error(error.localizedDescription.UTF8String?:"Cannot create movie reader");
    s.video=[[AVAssetReaderVideoCompositionOutput alloc] initWithVideoTracks:tracks videoSettings:@{(__bridge NSString*)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_422YpCbCr8)}];
    s.video.alwaysCopiesSampleData=NO;
    AVMutableVideoComposition* composition=[AVMutableVideoComposition videoComposition];
    composition.renderSize=CGSizeMake(s.profile.width,s.profile.height);composition.frameDuration=CMTimeMake(s.profile.rateDen,s.profile.rateNom);
    composition.colorPrimaries=AVVideoColorPrimaries_ITU_R_709_2;
    composition.colorTransferFunction=AVVideoTransferFunction_ITU_R_709_2;
    composition.colorYCbCrMatrix=s.profile.width==720?AVVideoYCbCrMatrix_ITU_R_601_4:AVVideoYCbCrMatrix_ITU_R_709_2;
    AVMutableVideoCompositionInstruction* instruction=[AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange=CMTimeRangeMake(kCMTimeZero,asset.duration);instruction.backgroundColor=CGColorGetConstantColor(kCGColorBlack);
    AVMutableVideoCompositionLayerInstruction* layer=[AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
    double par=1;
    if(track.formatDescriptions.count) {
        auto f=(__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject;
        NSDictionary* p=(__bridge NSDictionary*)CMFormatDescriptionGetExtension(f,kCMFormatDescriptionExtension_PixelAspectRatio);
        double h=[p[(__bridge NSString*)kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing] doubleValue];
        double v=[p[(__bridge NSString*)kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing] doubleValue];if(h>0&&v>0)par=h/v;
    }
    auto transform=CGAffineTransformConcat(CGAffineTransformMakeScale(par,1),track.preferredTransform);
    CGRect bounds=CGRectApplyAffineTransform(CGRectMake(0,0,track.naturalSize.width,track.naturalSize.height),transform);
    if(bounds.size.width<=0||bounds.size.height<=0)throw std::runtime_error("Invalid video dimensions");
    const double outputPAR=s.profile.pixelAspect();
    double fit=std::min(s.profile.width*outputPAR/bounds.size.width,s.profile.height/bounds.size.height);
    transform=CGAffineTransformConcat(transform,CGAffineTransformMakeTranslation(-bounds.origin.x,-bounds.origin.y));
    transform=CGAffineTransformConcat(transform,CGAffineTransformMakeScale(fit/outputPAR,fit));
    transform=CGAffineTransformConcat(transform,CGAffineTransformMakeTranslation((s.profile.width-bounds.size.width*fit/outputPAR)/2,(s.profile.height-bounds.size.height*fit)/2));
    [layer setTransform:transform atTime:kCMTimeZero];instruction.layerInstructions=@[layer];composition.instructions=@[instruction];s.video.videoComposition=composition;
    if(![s.reader canAddOutput:s.video])throw std::runtime_error("Cannot decode movie video");[s.reader addOutput:s.video];
    auto audioTracks=[asset tracksWithMediaType:AVMediaTypeAudio];
    if(audioTracks.count) {
        s.audio=[[AVAssetReaderAudioMixOutput alloc] initWithAudioTracks:audioTracks audioSettings:@{AVFormatIDKey:@(kAudioFormatLinearPCM),AVSampleRateKey:@48000,AVNumberOfChannelsKey:@2,AVLinearPCMBitDepthKey:@32,AVLinearPCMIsFloatKey:@YES,AVLinearPCMIsNonInterleaved:@NO}];
        if(![s.reader canAddOutput:s.audio])throw std::runtime_error("Cannot decode movie audio");[s.reader addOutput:s.audio];
    }
    if(![s.reader startReading])throw std::runtime_error(s.reader.error.localizedDescription.UTF8String?:"Movie decoding failed");
    printf("Movie: %.3f seconds; letterbox fit to %ux%u; %.5f fps; stereo audio %s\n",s.seconds,s.profile.width,s.profile.height,double(s.profile.rateNom)/s.profile.rateDen,s.audio?"available":"absent");
} }
MovieSource::~MovieSource()=default;
double MovieSource::duration()const{return impl->seconds;}
void MovieSource::read(unsigned frame,std::vector<uint8_t>& picture,std::vector<int32_t>& pcm) { @autoreleasepool {
    auto& s=*impl;auto sample=[s.video copyNextSampleBuffer];
    if(sample) {
        auto image=CMSampleBufferGetImageBuffer(sample);
        if(!image||CVPixelBufferGetPixelFormatType(image)!=kCVPixelFormatType_422YpCbCr8||CVPixelBufferGetWidth(image)!=s.profile.width||CVPixelBufferGetHeight(image)!=s.profile.height) {CFRelease(sample);throw std::runtime_error("Unexpected decoded video format");}
        s.lastPicture.resize(s.profile.width*s.profile.height*2);CVPixelBufferLockBaseAddress(image,kCVPixelBufferLock_ReadOnly);
        for(unsigned y=0;y<s.profile.height;++y)memcpy(s.lastPicture.data()+y*s.profile.width*2,static_cast<const uint8_t*>(CVPixelBufferGetBaseAddress(image))+y*CVPixelBufferGetBytesPerRow(image),s.profile.width*2);
        CVPixelBufferUnlockBaseAddress(image,kCVPixelBufferLock_ReadOnly);CFRelease(sample);
    } else if(s.reader.status==AVAssetReaderStatusFailed)throw std::runtime_error(s.reader.error.localizedDescription.UTF8String?:"Video decode failure");
    if(s.lastPicture.empty())throw std::runtime_error("No decoded movie picture");picture=s.lastPicture;
    const int64_t begin=s.profile.audioStart(frame),end=s.profile.audioStart(frame+1);
    pcm.assign(size_t(end-begin)*8,0);if(!s.audio)return;
    for(;;) {
        if(!s.pendingAudio)s.pendingAudio=[s.audio copyNextSampleBuffer];if(!s.pendingAudio)break;
        int64_t start=llround(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(s.pendingAudio))*48000);
        size_t count=CMSampleBufferGetNumSamples(s.pendingAudio);
        if(start>=end)break;
        if(start+int64_t(count)>begin) {
            std::vector<float> data(count*2);AudioBufferList list{};list.mNumberBuffers=1;list.mBuffers[0]={2,UInt32(data.size()*sizeof(float)),data.data()};
            if(CMSampleBufferCopyPCMDataIntoAudioBufferList(s.pendingAudio,0,int32_t(count),&list))throw std::runtime_error("Cannot read decoded audio");
            for(int64_t t=std::max(start,begin);t<std::min(start+int64_t(count),end);++t)for(unsigned c=0;c<2;++c) {
                float value=data[size_t(t-start)*2+c];if(!std::isfinite(value))value=0;
                pcm[size_t(t-begin)*8+c]=int32_t(std::max(-1.0,std::min(1.0,double(value)))*8388607.0);
            }
        }
        if(start+int64_t(count)>end)break;
        CFRelease(s.pendingAudio);s.pendingAudio=nullptr;
    }
} }
