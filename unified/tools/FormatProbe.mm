// GPL-2.0-or-later. Read-only CMIO format/rate/clock verification; never starts I/O.
#import <Foundation/Foundation.h>
#import <CoreMediaIO/CoreMediaIO.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreAudio/CoreAudio.h>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

static bool readBytes(CMIOObjectID object, CMIOObjectPropertySelector selector,
                      CMIOObjectPropertyScope scope, std::vector<uint8_t>& bytes,
                      CMFormatDescriptionRef qualifier = nullptr) {
    CMIOObjectPropertyAddress address{selector, scope, kCMIOObjectPropertyElementMain};
    const UInt32 qualifierBytes = qualifier ? sizeof(qualifier) : 0;
    const void* qualifierData = qualifier ? &qualifier : nullptr;
    UInt32 size = 0;
    OSStatus rc = CMIOObjectGetPropertyDataSize(object, &address, qualifierBytes,
                                              qualifierData, &size);
    if (rc || size > 1024 * 1024) {
        fprintf(stderr, "Property %08x size: status %d; bytes %u\n",
                unsigned(selector), int(rc), unsigned(size));
        return false;
    }
    bytes.resize(size);
    UInt32 used = size;
    rc = CMIOObjectGetPropertyData(object, &address, qualifierBytes, qualifierData,
                                   size, &used, bytes.data());
    if (rc || used > size) {
        fprintf(stderr, "Property %08x read: status %d; bytes %u/%u\n",
                unsigned(selector), int(rc), unsigned(used), unsigned(size));
        return false;
    }
    bytes.resize(used);
    return true;
}

template<class T>
static bool readValue(CMIOObjectID object, CMIOObjectPropertySelector selector,
                      CMIOObjectPropertyScope scope, T& value) {
    std::vector<uint8_t> bytes;
    if (!readBytes(object, selector, scope, bytes) || bytes.size() != sizeof(T)) return false;
    std::memcpy(&value, bytes.data(), sizeof(T));
    return true;
}

static bool check(bool condition, const char* message) {
    if (!condition) fprintf(stderr, "FAIL: %s\n", message);
    return condition;
}

// CMIO clients can round frame-duration CMTime values. This remains much tighter
// than the 0.001-fps tolerance accepted by the extension's format setter.
static bool equalRate(double actual, double expected) {
    return std::isfinite(actual) && std::fabs(actual - expected) < 0.0001;
}

static bool checkAudioLatencies() {
    AudioObjectPropertyAddress address{kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    OSStatus rc = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, nullptr, &size);
    if (rc || size > 1024 * 1024 || size % sizeof(AudioDeviceID))
        return check(false, "Core Audio device enumeration must be available");
    std::vector<AudioDeviceID> devices(size / sizeof(AudioDeviceID));
    rc = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, nullptr, &size, devices.data());
    if (rc) return check(false, "Core Audio device enumeration must succeed");
    bool foundOutput = false, foundInput = false, ok = true;
    for (auto device : devices) {
        CFStringRef uid = nullptr;
        UInt32 used = sizeof(uid);
        address = {kAudioDevicePropertyDeviceUID, kAudioObjectPropertyScopeGlobal,
                   kAudioObjectPropertyElementMain};
        if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &used, &uid) || !uid) continue;
        const bool output = CFEqual(uid, CFSTR("local.shuttle.audio.hdmi"));
        const bool input = CFEqual(uid, CFSTR("local.shuttle.audio.stereo"));
        CFRelease(uid);
        if (!output && !input) continue;
        if (output) foundOutput = true;
        if (input) foundInput = true;
        // HAL3 adds output buffering. Capture retains AudioDriver's original
        // DelayFrames=3840 and its existing input device UID.
        const UInt32 expected = output ? 12288 : 3840;
        UInt32 latency = 0;
        used = sizeof(latency);
        address = {kAudioDevicePropertyLatency,
                   output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput,
                   kAudioObjectPropertyElementMain};
        rc = AudioObjectGetPropertyData(device, &address, 0, nullptr, &used, &latency);
        printf("%s audio device %u: latency %u frames; expected %u; status %d\n",
               output ? "HDMI output" : "Capture input", unsigned(device), unsigned(latency),
               unsigned(expected), int(rc));
        ok = check(!rc && used == sizeof(latency) && latency == expected,
                   output ? "HAL3 HDMI latency must be 12288 frames" :
                            "Capture latency must remain 3840 frames") && ok;
    }
    ok = check(foundOutput, "HDMI audio device must be enumerated") && ok;
    ok = check(foundInput, "Existing capture audio device must be enumerated") && ok;
    return ok;
}

static const char* names[] = {"576i50", "1080i50", "1080p25", "480i59.94", "1080i59.94", "1080p29.97"};
static const double nominal[] = {25, 25, 25, 30000.0 / 1001, 30000.0 / 1001, 30000.0 / 1001};
static const int widths[] = {720, 1920, 1920, 720, 1920, 1920};
static const int heights[] = {576, 1080, 1080, 486, 1080, 1080};
static int modeArgument(const char* argument) {
    const char* helperNames[] = {"576i50", "1080i50", "1080p25", "480i5994", "1080i5994", "1080p2997"};
    for (int mode=0;mode<6;++mode)
        if (!strcmp(argument,names[mode]) || !strcmp(argument,helperNames[mode])) return mode;
    return -1;
}

int main(int argc, char** argv) {
    int expectedMode=-1;
    const bool expectAbsent=argc==2&&!strcmp(argv[1],"--absent");
    if (argc==3&&!strcmp(argv[1],"--expect-mode")) expectedMode=modeArgument(argv[2]);
    if (argc!=1&&!expectAbsent&&expectedMode<0) {
        fputs("Usage: format-probe [--absent | --expect-mode 576i50|1080i50|1080p25|480i5994|1080i5994|1080p2997]\n",stderr);
        return 64;
    }
    @autoreleasepool {
        std::vector<uint8_t> bytes;
        if (!readBytes(kCMIOObjectSystemObject, kCMIOHardwarePropertyDevices,
                       kCMIOObjectPropertyScopeGlobal, bytes) || bytes.size() % sizeof(CMIODeviceID)) return 2;
        CMIODeviceID device = kCMIOObjectUnknown;
        for (size_t offset = 0; offset < bytes.size(); offset += sizeof(CMIODeviceID)) {
            CMIODeviceID candidate;
            std::memcpy(&candidate, bytes.data() + offset, sizeof(candidate));
            CFStringRef uid = nullptr;
            if (readValue(candidate, kCMIODevicePropertyDeviceUID,
                          kCMIOObjectPropertyScopeGlobal, uid) && uid) {
                if (CFEqual(uid, CFSTR("local.shuttle.output.cmio"))) device = candidate;
                CFRelease(uid);
            }
        }
        if (expectAbsent) {
            const bool absent=device==kCMIOObjectUnknown;
            puts(absent?"PASS: HDMI output device absent while sender idle":"FAIL: HDMI output device still advertised without a sender");
            return absent?0:1;
        }
        if (device == kCMIOObjectUnknown) {
            fputs("Shuttle HDMI output device not found\n", stderr);
            return 2;
        }
        if (!readBytes(device, kCMIODevicePropertyStreams, kCMIODevicePropertyScopeOutput, bytes) ||
            !check(bytes.size() == sizeof(CMIOStreamID), "Expected exactly one HDMI output stream")) return 2;
        CMIOStreamID stream;
        std::memcpy(&stream, bytes.data(), sizeof(stream));
        printf("Read-only HDMI format probe: device %u; stream %u\n", unsigned(device), unsigned(stream));

        bool ok = checkAudioLatencies();
        Float64 currentRate = 0, minimumRate = 0;
        bool currentOK = readValue(stream, kCMIOStreamPropertyFrameRate,
                                    kCMIOObjectPropertyScopeGlobal, currentRate);
        bool minimumOK = readValue(stream, kCMIOStreamPropertyMinimumFrameRate,
                                    kCMIOObjectPropertyScopeGlobal, minimumRate);
        printf("Current frame rate %.9f; minimum %.9f\n", currentRate, minimumRate);
        ok = check(currentOK && minimumOK && std::isfinite(currentRate) && currentRate > 0 &&
                   std::isfinite(minimumRate) && minimumRate > 0 && minimumRate <= currentRate,
                   "Current/minimum frame rates must be available and valid") && ok;
        if (expectedMode>=0)
            ok = check(equalRate(currentRate,nominal[expectedMode]) && equalRate(minimumRate,nominal[expectedMode]),
                       "Singleton current/minimum rates must match the expected mode") && ok;

        CFTypeRef clock = nullptr;
        if (readValue(stream, kCMIOStreamPropertyClock, kCMIOObjectPropertyScopeGlobal, clock) && clock) {
            const uint64_t hostNow=CVGetCurrentHostTime();
            CMTime deviceTime = CMIOStreamClockConvertHostTimeToDeviceTime(hostNow, clock);
            printf("Stream clock %.9f s; flags %u; type %lu\n", CMTimeGetSeconds(deviceTime),
                    unsigned(deviceTime.flags), static_cast<unsigned long>(CFGetTypeID(clock)));
            ok = check(CMTIME_IS_NUMERIC(deviceTime), "Stream clock must return a numeric time") && ok;
            CMTime later=CMIOStreamClockConvertHostTimeToDeviceTime(hostNow+uint64_t(CVGetHostClockFrequency()/8),clock);
            const double delta=CMTimeGetSeconds(CMTimeSubtract(later,deviceTime));
            printf("Clock conversion for 125ms host interval: %.9f s\n",delta);
            ok = check(CMTIME_IS_NUMERIC(later)&&std::isfinite(delta)&&std::fabs(delta-0.125)<0.0001,
                       "Stream clock conversion must progress at host rate") && ok;
            if (CFGetTypeID(clock) == CMClockGetTypeID()) {
                auto cmClock = static_cast<CMClockRef>(const_cast<void*>(clock));
                const double relativeRate=CMSyncGetRelativeRate(cmClock, CMClockGetHostTimeClock());
                printf("Stream/host relative rate %.9f\n", relativeRate);
                ok = check(equalRate(relativeRate,1), "Stream clock must run at host rate") && ok;
            }
            CFRelease(clock);
        } else {
            ok = check(false, "Stream clock must be available") && ok;
        }

        CFArrayRef formats = nullptr;
        if (!readValue(stream, kCMIOStreamPropertyFormatDescriptions,
                       kCMIOObjectPropertyScopeGlobal, formats) || !formats) return 2;
        const CFIndex count = CFArrayGetCount(formats);
        ok = check(count == (expectedMode>=0?1:6), expectedMode>=0?
                   "Ready output must advertise exactly one matching mode":"Expected six distinct legacy HDMI mode descriptions") && ok;
        CMFormatDescriptionRef active=nullptr;
        const bool activeOK=readValue(stream,kCMIOStreamPropertyFormatDescription,kCMIOObjectPropertyScopeGlobal,active)&&active;
        ok = check(activeOK,"Active format must be available") && ok;
        const CFIndex checked = count < (expectedMode>=0?1:6) ? count : (expectedMode>=0?1:6);
        for (CFIndex index = 0; index < checked; ++index) {
            const int mode=expectedMode>=0?expectedMode:int(index);
            auto format = static_cast<CMFormatDescriptionRef>(CFArrayGetValueAtIndex(formats, index));
            auto dimensions = CMVideoFormatDescriptionGetDimensions(format);
            auto name = static_cast<CFStringRef>(CMFormatDescriptionGetExtension(format, kCMFormatDescriptionExtension_FormatName));
            printf("Format %ld (%s): %dx%d; name %s; expected %.9f fps\n", long(index), names[mode],
                    dimensions.width, dimensions.height, name ? [(__bridge NSString*)name UTF8String] : "(absent)", nominal[mode]);
            ok = check(dimensions.width == widths[mode] && dimensions.height == heights[mode],
                       "Format dimensions must match the expected mode") && ok;
            const bool nameOK=name&&CFGetTypeID(name)==CFStringGetTypeID()&&
                [(__bridge NSString*)name isEqualToString:[NSString stringWithUTF8String:names[mode]]];
            ok = check(nameOK,"Format name must match the expected mode") && ok;
            ok = check(CMFormatDescriptionGetMediaSubType(format)==kCVPixelFormatType_422YpCbCr8,
                       "Output format must use UYVY") && ok;
            CFTypeRef fieldCount=CMFormatDescriptionGetExtension(format,kCMFormatDescriptionExtension_FieldCount);
            int fields=0;const int expectedFields=(mode==2||mode==5)?1:2;
            const bool fieldOK=fieldCount&&CFGetTypeID(fieldCount)==CFNumberGetTypeID()&&
                CFNumberGetValue(static_cast<CFNumberRef>(fieldCount),kCFNumberIntType,&fields)&&fields==expectedFields;
            ok = check(fieldOK,"Field count must match the expected mode") && ok;
            if (expectedMode>=0)
                ok = check(activeOK&&CMFormatDescriptionEqual(active,format),"Active format must equal the singleton description") && ok;
            for (CFIndex previous = 0; previous < index; ++previous) {
                auto other = static_cast<CMFormatDescriptionRef>(CFArrayGetValueAtIndex(formats, previous));
                if (CMFormatDescriptionEqual(format, other)) {
                    fprintf(stderr, "FAIL: Format %ld equals format %ld\n", long(index), long(previous));
                    ok = false;
                }
            }
            if (readBytes(stream, kCMIOStreamPropertyFrameRates, kCMIOObjectPropertyScopeGlobal, bytes, format)) {
                const size_t rates = bytes.size() / sizeof(Float64);
                printf("  Discrete rates:");
                for (size_t n = 0; n < rates; ++n) {
                    Float64 rate;
                    std::memcpy(&rate, bytes.data() + n * sizeof(rate), sizeof(rate));
                    printf(" %.9f", rate);
                    ok = check(equalRate(rate, nominal[mode]), "Discrete rate must match the nominal mode rate") && ok;
                }
                puts("");
                ok = check(bytes.size() == sizeof(Float64), "Expected exactly one discrete rate per mode") && ok;
            } else {
                ok = check(false, "Qualified discrete frame rates must be exposed") && ok;
            }
            if (readBytes(stream, kCMIOStreamPropertyFrameRateRanges, kCMIOObjectPropertyScopeGlobal, bytes, format)) {
                AudioValueRange range{};
                if (bytes.size() == sizeof(range)) {
                    std::memcpy(&range, bytes.data(), sizeof(range));
                    printf("  Qualified range: %.9f .. %.9f\n", range.mMinimum, range.mMaximum);
                }
                ok = check(bytes.size() == sizeof(range) && equalRate(range.mMinimum, nominal[mode]) &&
                           equalRate(range.mMaximum, nominal[mode]), "Qualified range must equal the nominal mode rate") && ok;
            } else {
                ok = check(false, "Qualified frame-rate ranges must be exposed") && ok;
            }
        }
        if(active)CFRelease(active);
        CFRelease(formats);
        puts(ok ? (expectedMode>=0?"PASS: expected singleton mode, discrete rates, qualified ranges, stream clock and HAL3/capture latencies":
                    "PASS: six distinct legacy modes, discrete rates, qualified ranges, stream clock and HAL3/capture latencies"):
                   "FAIL: HDMI format/latency verification");
        return ok ? 0 : 1;
    }
}
