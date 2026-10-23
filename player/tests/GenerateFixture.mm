// GPL-2.0-or-later. Derived from project synthetic sync fixture. Modified19October2026: small offline player fixture.
// Native, deterministic audiovisual sync fixture. Build instructions are in
// fixtures/Sync-1080p25-10s-validation.json after running this program.
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreText/CoreText.h>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
#include <unistd.h>

static bool colourBars=false;
static constexpr int kWidth = 320, kHeight = 240, kFPS = 25;
static constexpr int kFrames = 250, kRate = 48000, kChannels = 2;
static constexpr int kSamplesPerFrame = kRate / kFPS;
static constexpr int kAudioFrames = 10 * kRate;

static void Require(bool condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "%s\n", message.UTF8String);
        exit(1);
    }
}

static bool IsFlash(int frame) {
    return frame >= 25 && ((frame - 25) % 50) < 5;
}

static bool IsBeep(int sample) {
    return sample >= kRate && ((sample - kRate) % (2 * kRate)) < kRate / 5;
}

static void DrawText(CGContextRef context, NSString *string, CGFloat x,
                     CGFloat y, CGFloat size, bool flash) {
    CTFontRef font = CTFontCreateWithName(CFSTR("Menlo-Bold"), size, nullptr);
    CGColorRef color = CGColorCreateGenericRGB(flash ? 0.02 : 0.9,
                                               flash ? 0.02 : 0.9,
                                               flash ? 0.02 : 0.9, 1);
    NSDictionary *attributes = @{
        (__bridge NSString *)kCTFontAttributeName: (__bridge id)font,
        (__bridge NSString *)kCTForegroundColorAttributeName: (__bridge id)color
    };
    NSAttributedString *text = [[NSAttributedString alloc] initWithString:string
                                                            attributes:attributes];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)text);
    CGContextSetTextPosition(context, x, y);
    CTLineDraw(line, context);
    CFRelease(line);
    CGColorRelease(color);
    CFRelease(font);
}

static CVPixelBufferRef MakeFrame(int frame) {
    CVPixelBufferRef pixel = nullptr;
    NSDictionary *attributes = @{
        (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    Require(CVPixelBufferCreate(kCFAllocatorDefault, kWidth, kHeight,
        kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attributes, &pixel)
        == kCVReturnSuccess, @"Could not allocate video frame");
    CVPixelBufferLockBaseAddress(pixel, 0);
    void *base = CVPixelBufferGetBaseAddress(pixel);
    size_t stride = CVPixelBufferGetBytesPerRow(pixel);
    bool flash = IsFlash(frame);
    uint8_t shade = flash ? 255 : 8;
    for (int y = 0; y < kHeight; ++y) {
        uint8_t *row = (uint8_t *)base + y * stride;
        for (int x = 0; x < kWidth; ++x) {
            row[x * 4 + 0] = row[x * 4 + 1] = row[x * 4 + 2] = shade;
            row[x * 4 + 3] = 255;
            if(colourBars){
                static const uint8_t rgb[8][3]={{220,220,220},{220,220,0},{0,220,220},{0,220,0},{220,0,220},{220,0,0},{0,0,220},{16,16,16}};
                auto c=rgb[x*8/kWidth];row[x*4]=c[2];row[x*4+1]=c[1];row[x*4+2]=c[0];
                if(y>kHeight*3/4&&y<kHeight*3/4+20&&x>frame%(kWidth-40)&&x<frame%(kWidth-40)+40)row[x*4]=row[x*4+1]=row[x*4+2]=255;
            }
        }
    }
    CGColorSpaceRef colors = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(base, kWidth, kHeight, 8, stride,
        colors, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    Require(context != nullptr, @"Could not create text drawing context");
    CGContextScaleCTM(context,double(kWidth)/1920,double(kHeight)/1080);
    DrawText(context, @"A/V SYNC — 1080p25 — SDR", 160, 830, 64, flash);
    DrawText(context, [NSString stringWithFormat:@"%02d:%02d:%02d:%02d   FRAME %03d / 249",
        0, 0, frame / kFPS, frame % kFPS, frame], 160, 680, 54, flash);
    DrawText(context, flash ? @"FLASH + 1 kHz BEEP" : @"DARK + SILENCE", 160, 480, 76, flash);
    DrawText(context, @"200 ms pulses at 1, 3, 5, 7, 9 seconds", 160, 280, 45, flash);
    DrawText(context, @"Both stereo channels identical; tone level -12 dBFS peak", 160, 180, 36, flash);
    CGContextRelease(context);
    CGColorSpaceRelease(colors);
    CVPixelBufferUnlockBaseAddress(pixel, 0);
    CVBufferSetAttachment(pixel, kCVImageBufferColorPrimariesKey,
        kCVImageBufferColorPrimaries_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel, kCVImageBufferTransferFunctionKey,
        kCVImageBufferTransferFunction_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    CVBufferSetAttachment(pixel, kCVImageBufferYCbCrMatrixKey,
        kCVImageBufferYCbCrMatrix_ITU_R_709_2, kCVAttachmentMode_ShouldPropagate);
    return pixel;
}

static CMSampleBufferRef MakeAudio(int start, CMAudioFormatDescriptionRef format) {
    std::vector<int16_t> samples(kSamplesPerFrame * kChannels, 0);
    constexpr double amplitude = 32767.0 * 0.251188643150958;
    constexpr double pi = 3.14159265358979323846;
    for (int i = 0; i < kSamplesPerFrame; ++i) {
        int position = start + i;
        if (IsBeep(position)) {
            int phase = (position - kRate) % (2 * kRate);
            int16_t value = (int16_t)std::lround(amplitude * std::sin(2 * pi * 1000 * phase / kRate));
            samples[i * 2] = samples[i * 2 + 1] = value;
        }
    }
    const size_t bytes = samples.size() * sizeof(int16_t);
    CMBlockBufferRef block = nullptr;
    Require(CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault, nullptr, bytes,
        kCFAllocatorDefault, nullptr, 0, bytes, 0, &block) == noErr,
        @"Could not allocate audio block");
    Require(CMBlockBufferReplaceDataBytes(samples.data(), block, 0, bytes) == noErr,
        @"Could not fill audio block");
    CMSampleTimingInfo timing = { CMTimeMake(1, kRate), CMTimeMake(start, kRate), kCMTimeInvalid };
    const size_t sampleSize = 4;
    CMSampleBufferRef buffer = nullptr;
    Require(CMSampleBufferCreateReady(kCFAllocatorDefault, block, format,
        kSamplesPerFrame, 1, &timing, 1, &sampleSize, &buffer) == noErr,
        @"Could not create audio sample buffer");
    CFRelease(block);
    return buffer;
}

static void WriteMovie(NSURL *url) {
    NSError *error = nil;
    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:url
        fileType:AVFileTypeQuickTimeMovie error:&error];
    Require(writer != nil, [NSString stringWithFormat:@"Writer: %@", error]);
    NSDictionary *videoSettings = @{
        AVVideoCodecKey: AVVideoCodecTypeH264,
        AVVideoWidthKey: @(kWidth), AVVideoHeightKey: @(kHeight),
        AVVideoColorPropertiesKey: @{
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
        },
        AVVideoCompressionPropertiesKey: @{
            AVVideoAverageBitRateKey: @6000000,
            AVVideoExpectedSourceFrameRateKey: @(kFPS),
            AVVideoMaxKeyFrameIntervalKey: @(kFPS),
            AVVideoAllowFrameReorderingKey: @NO,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
        }
    };
    AVAssetWriterInput *video = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                    outputSettings:videoSettings];
    video.expectsMediaDataInRealTime = NO;
    video.mediaTimeScale = kFPS;
    AVAssetWriterInputPixelBufferAdaptor *adaptor =
        [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:video
            sourcePixelBufferAttributes:@{(NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                (NSString *)kCVPixelBufferWidthKey: @(kWidth),
                (NSString *)kCVPixelBufferHeightKey: @(kHeight)}];
    NSDictionary *audioSettings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM), AVSampleRateKey: @(kRate),
        AVNumberOfChannelsKey: @(kChannels), AVLinearPCMBitDepthKey: @16,
        AVLinearPCMIsBigEndianKey: @NO, AVLinearPCMIsFloatKey: @NO,
        AVLinearPCMIsNonInterleaved: @NO
    };
    AVAssetWriterInput *audio = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                                    outputSettings:audioSettings];
    audio.expectsMediaDataInRealTime = NO;
    Require([writer canAddInput:video] && [writer canAddInput:audio], @"Unsupported writer inputs");
    [writer addInput:video];
    [writer addInput:audio];
    AudioStreamBasicDescription asbd = {};
    asbd.mSampleRate = kRate;
    asbd.mFormatID = kAudioFormatLinearPCM;
    asbd.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    asbd.mBytesPerPacket = asbd.mBytesPerFrame = 4;
    asbd.mFramesPerPacket = 1;
    asbd.mChannelsPerFrame = kChannels;
    asbd.mBitsPerChannel = 16;
    CMAudioFormatDescriptionRef audioFormat = nullptr;
    Require(CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &asbd, 0, nullptr,
        0, nullptr, nullptr, &audioFormat) == noErr, @"Could not describe PCM audio");
    Require([writer startWriting], [NSString stringWithFormat:@"startWriting: %@", writer.error]);
    [writer startSessionAtSourceTime:kCMTimeZero];
    int nextVideo = 0, nextAudio = 0;
    bool videoFinished = false, audioFinished = false;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:180];
    // Only append a ready input. When one backs up, service the other instead of
    // waiting on it; blocking for a whole track can deadlock AVAssetWriter.
    while (nextVideo < kFrames || nextAudio < kAudioFrames) {
        @autoreleasepool {
            Require(writer.status == AVAssetWriterStatusWriting,
                [NSString stringWithFormat:@"Writing failed: %@", writer.error]);
            bool videoReady = nextVideo < kFrames && video.readyForMoreMediaData;
            bool audioReady = nextAudio < kAudioFrames && audio.readyForMoreMediaData;
            bool chooseVideo = videoReady && (!audioReady || nextVideo * kSamplesPerFrame <= nextAudio);
            if (chooseVideo) {
                CVPixelBufferRef pixel = MakeFrame(nextVideo);
                bool appended = [adaptor appendPixelBuffer:pixel withPresentationTime:CMTimeMake(nextVideo, kFPS)];
                CVPixelBufferRelease(pixel);
                Require(appended, [NSString stringWithFormat:@"Append video: %@", writer.error]);
                ++nextVideo;
            } else if (audioReady) {
                CMSampleBufferRef buffer = MakeAudio(nextAudio, audioFormat);
                bool appended = [audio appendSampleBuffer:buffer];
                CFRelease(buffer);
                Require(appended, [NSString stringWithFormat:@"Append audio: %@", writer.error]);
                nextAudio += kSamplesPerFrame;
            } else {
                Require([deadline timeIntervalSinceNow] > 0, @"Writer backpressure timeout");
                usleep(1000);
            }
            if (nextVideo == kFrames && !videoFinished) { [video markAsFinished]; videoFinished = true; }
            if (nextAudio == kAudioFrames && !audioFinished) { [audio markAsFinished]; audioFinished = true; }
        }
    }
    [writer endSessionAtSourceTime:CMTimeMake(10, 1)];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
    Require(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 60LL * NSEC_PER_SEC)) == 0,
        @"Writer finalization timed out");
    Require(writer.status == AVAssetWriterStatusCompleted,
        [NSString stringWithFormat:@"finishWriting: %@", writer.error]);
    CFRelease(audioFormat);
}

static NSString *FourCCString(FourCharCode code) {
    char bytes[5] = {(char)(code >> 24), (char)(code >> 16), (char)(code >> 8), (char)code, 0};
    return [NSString stringWithUTF8String:bytes];
}

static NSDictionary *Validate(NSURL *url) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    Require(videoTracks.count == 1 && audioTracks.count == 1, @"Expected exactly one video and one audio track");
    AVAssetTrack *video = videoTracks.firstObject, *audio = audioTracks.firstObject;
    Require(CMTimeCompare(asset.duration, CMTimeMake(10, 1)) == 0, @"Movie duration is not exactly ten seconds");
    Require(CMTimeCompare(video.timeRange.start, kCMTimeZero) == 0 &&
            CMTimeCompare(audio.timeRange.start, kCMTimeZero) == 0, @"Tracks do not both start at zero");
    Require(CMTimeCompare(video.timeRange.duration, CMTimeMake(10, 1)) == 0 &&
            CMTimeCompare(audio.timeRange.duration, CMTimeMake(10, 1)) == 0, @"Track duration mismatch");
    CMFormatDescriptionRef vFormat = (__bridge CMFormatDescriptionRef)video.formatDescriptions.firstObject;
    CMFormatDescriptionRef aFormat = (__bridge CMFormatDescriptionRef)audio.formatDescriptions.firstObject;
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(vFormat);
    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(aFormat);
    Require(dimensions.width == kWidth && dimensions.height == kHeight && video.nominalFrameRate == kFPS,
        @"Unexpected encoded video dimensions/frame rate");
    Require(asbd && asbd->mSampleRate == kRate && asbd->mChannelsPerFrame == kChannels &&
            asbd->mBitsPerChannel == 16 && asbd->mFormatID == kAudioFormatLinearPCM,
        @"Unexpected encoded audio format");
    NSDictionary *colorMetadata = @{
        @"primaries": (__bridge id)CMFormatDescriptionGetExtension(vFormat, kCMFormatDescriptionExtension_ColorPrimaries) ?: @"missing",
        @"transferFunction": (__bridge id)CMFormatDescriptionGetExtension(vFormat, kCMFormatDescriptionExtension_TransferFunction) ?: @"missing",
        @"YCbCrMatrix": (__bridge id)CMFormatDescriptionGetExtension(vFormat, kCMFormatDescriptionExtension_YCbCrMatrix) ?: @"missing"
    };
    for (NSString *key in colorMetadata) Require([colorMetadata[key] isEqual:@"ITU_R_709_2"],
        [NSString stringWithFormat:@"Unexpected encoded color metadata: %@", colorMetadata]);
    NSError *error = nil;
    AVAssetReader *vReader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
    AVAssetReaderTrackOutput *vOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:video
        outputSettings:@{(NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)}];
    [vReader addOutput:vOutput];
    Require([vReader startReading], [NSString stringWithFormat:@"Video reader: %@", vReader.error]);
    int frameCount = 0, flashCount = 0;
    std::vector<int> flashStarts;
    bool previousFlash = false;
    while (CMSampleBufferRef sample = [vOutput copyNextSampleBuffer]) {
        Require(CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample), CMTimeMake(frameCount, kFPS)) == 0,
            @"Decoded video PTS is not the expected frame boundary");
        // AVAssetReader can omit duration on decoded H.264 samples. The exact
        // consecutive PTS values plus ten-second track range still establish
        // the display interval of every frame, including the final one.
        CMTime duration = CMSampleBufferGetDuration(sample);
        Require(!CMTIME_IS_NUMERIC(duration) || CMTimeCompare(duration, CMTimeMake(1, kFPS)) == 0,
            [NSString stringWithFormat:@"Decoded video duration: %@", CFBridgingRelease(CMTimeCopyDescription(kCFAllocatorDefault, duration))]);
        CVPixelBufferRef pixel = CMSampleBufferGetImageBuffer(sample);
        CVPixelBufferLockBaseAddress(pixel, kCVPixelBufferLock_ReadOnly);
        const uint8_t *base = (const uint8_t *)CVPixelBufferGetBaseAddress(pixel);
        size_t offset = 100 * CVPixelBufferGetBytesPerRow(pixel) + 100 * 4;
        bool flash = base[offset] > 200;
        Require(flash == IsFlash(frameCount), @"Decoded flash does not align to the intended video frame");
        if (flash) { ++flashCount; if (!previousFlash) flashStarts.push_back(frameCount); }
        previousFlash = flash;
        CVPixelBufferUnlockBaseAddress(pixel, kCVPixelBufferLock_ReadOnly);
        ++frameCount;
        CFRelease(sample);
    }
    Require(vReader.status == AVAssetReaderStatusCompleted && frameCount == kFrames && flashCount == 25,
        @"Video frame count/flash count validation failed");
    AVAssetReader *aReader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
    AVAssetReaderTrackOutput *aOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:audio
        outputSettings:@{AVFormatIDKey: @(kAudioFormatLinearPCM), AVLinearPCMBitDepthKey: @16,
            AVLinearPCMIsBigEndianKey: @NO, AVLinearPCMIsFloatKey: @NO, AVLinearPCMIsNonInterleaved: @NO}];
    [aReader addOutput:aOutput];
    Require([aReader startReading], [NSString stringWithFormat:@"Audio reader: %@", aReader.error]);
    int audioFrames = 0, nonzeroSamples = 0, peak = 0;
    while (CMSampleBufferRef sample = [aOutput copyNextSampleBuffer]) {
        Require(CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sample), CMTimeMake(audioFrames, kRate)) == 0,
            @"Decoded audio PTS is not contiguous");
        CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
        size_t length = CMBlockBufferGetDataLength(block);
        std::vector<int16_t> samples(length / 2);
        Require(CMBlockBufferCopyDataBytes(block, 0, length, samples.data()) == noErr, @"Could not inspect audio");
        Require(length == (size_t)CMSampleBufferGetNumSamples(sample) * 4, @"Unexpected decoded PCM layout");
        for (size_t i = 0; i < samples.size() / 2; ++i) {
            int value = samples[i * 2];
            Require(value == samples[i * 2 + 1], @"Stereo channels differ");
            int position = audioFrames + (int)i;
            if (!IsBeep(position)) Require(value == 0, @"Non-silent sample outside a beep");
            if (value != 0) ++nonzeroSamples;
            peak = std::max(peak, std::abs(value));
            constexpr double pi = 3.14159265358979323846;
            int expected = IsBeep(position) ? (int)std::lround(32767.0 * 0.251188643150958 *
                std::sin(2 * pi * 1000 * ((position - kRate) % (2 * kRate)) / kRate)) : 0;
            Require(value == expected, @"Decoded PCM differs from the exact intended waveform");
        }
        audioFrames += (int)(samples.size() / 2);
        CFRelease(sample);
    }
    Require(aReader.status == AVAssetReaderStatusCompleted && audioFrames == kAudioFrames && peak > 8000,
        @"Audio frame count/peak validation failed");
    NSMutableArray *pulses = [NSMutableArray array];
    for (int frame : flashStarts) {
        [pulses addObject:@{@"startSeconds": @((double)frame / kFPS), @"durationSeconds": @0.2,
            @"startVideoFrameZeroBased": @(frame), @"videoFrames": @5,
            @"startAudioSampleZeroBased": @(frame * kSamplesPerFrame), @"audioFrames": @9600}];
    }
    unsigned long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil]
        [NSFileSize] unsignedLongLongValue];
    return @{
        @"file": url.path, @"bytes": @(fileSize), @"durationSeconds": @10,
        @"validation": @"PASS: decoded every video frame and every PCM sample; exact PTS and waveform checks",
        @"video": @{@"codecFourCC": FourCCString(CMFormatDescriptionGetMediaSubType(vFormat)),
            @"width": @(dimensions.width), @"height": @(dimensions.height), @"framesPerSecond": @(video.nominalFrameRate), @"frameCount": @(frameCount),
            @"startSeconds": @0, @"durationSeconds": @10, @"flashFrames": @(flashCount),
            @"colorMetadata": colorMetadata, @"SDR": @YES},
        @"audio": @{@"codecFourCC": FourCCString(CMFormatDescriptionGetMediaSubType(aFormat)),
            @"sampleRate": @(asbd->mSampleRate), @"channels": @(asbd->mChannelsPerFrame), @"bitsPerSample": @(asbd->mBitsPerChannel),
            @"sampleFrames": @(audioFrames), @"startSeconds": @0, @"durationSeconds": @10,
            @"toneHz": @1000, @"peakDBFS": @(-12.0), @"peakPCM": @(peak),
            @"nonzeroSampleFrames": @(nonzeroSamples), @"stereoChannelsIdentical": @YES},
        @"pulses": pulses,
        @"limits": @"Validates encoded source timestamps and decoded media. Hardware/display/audio output latency must be judged separately. The sine wave starts at a zero crossing, with its first nonzero sample 1/48000 second after each pulse boundary.",
        @"build": @"xcrun clang++ -std=c++17 -O2 -fobjc-arc -Wno-deprecated-declarations tools/GenerateSyncMovie.mm -o fixtures/generate-sync-movie -framework Foundation -framework AVFoundation -framework AudioToolbox -framework CoreMedia -framework CoreVideo -framework CoreGraphics -framework CoreText"
    };
}

int main(int argc,const char**argv){@autoreleasepool{if(argc<2||argc>3)return 64;colourBars=argc==3;WriteMovie([NSURL fileURLWithPath:@(argv[1])]);return 0;}}
