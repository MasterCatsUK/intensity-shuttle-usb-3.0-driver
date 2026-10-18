// GPL-2.0-or-later. Shared saved timeline-output audio adjustment.
#pragma once
#include <CoreFoundation/CoreFoundation.h>
#include "AudioSync.hpp"
#include "Timecode.hpp"
#include "AudioMeters.hpp"
#include "SafeZones.hpp"
namespace shuttle_output_audio {
static std::atomic<bool> timecodeOverlayEnabled{false};
static std::atomic<unsigned> timecodeOverlayPosition{5};
static std::atomic<bool> audioMetersEnabled{false};
static std::atomic<unsigned> audioMetersPosition{2};
static std::atomic<bool> titleSafeEnabled{false},actionSafeEnabled{false};
inline int readAudioOffsetPreference(CFStringRef domain=CFSTR("local.shuttle.camera")){
    CFPreferencesAppSynchronize(domain);
    CFPropertyListRef raw=CFPreferencesCopyAppValue(CFSTR("HDMIAudioOffsetMS"),domain);
    int value=0;
    if(raw){if(CFGetTypeID(raw)==CFNumberGetTypeID())CFNumberGetValue(static_cast<CFNumberRef>(raw),kCFNumberIntType,&value);CFRelease(raw);}
    return clampAudioOffset(value);
}
inline int readOutputPreferences(CFStringRef domain){
    int offset=readAudioOffsetPreference(domain);
    Boolean exists=false;bool enabled=CFPreferencesGetAppBooleanValue(CFSTR("ShowHDMITimecode"),domain,&exists);
    timecodeOverlayEnabled.store(exists&&enabled);
    long position=CFPreferencesGetAppIntegerValue(CFSTR("HDMITimecodePosition"),domain,&exists);
    timecodeOverlayPosition.store(shuttle_sink::savedTimecodePosition(exists?position:0));
    enabled=CFPreferencesGetAppBooleanValue(CFSTR("ShowHDMIAudioMeters"),domain,&exists);
    audioMetersEnabled.store(exists&&enabled);
    position=CFPreferencesGetAppIntegerValue(CFSTR("HDMIAudioMeterPosition"),domain,&exists);
    audioMetersPosition.store(savedMeterPosition(exists?position:0));
    enabled=CFPreferencesGetAppBooleanValue(CFSTR("ShowHDMITitleSafe"),domain,&exists);titleSafeEnabled.store(exists&&enabled);
    enabled=CFPreferencesGetAppBooleanValue(CFSTR("ShowHDMIActionSafe"),domain,&exists);actionSafeEnabled.store(exists&&enabled);
    return offset;
}
inline int readLiveAudioOffsetPreference(){return readOutputPreferences(CFSTR("local.shuttle.camera"));}
}
