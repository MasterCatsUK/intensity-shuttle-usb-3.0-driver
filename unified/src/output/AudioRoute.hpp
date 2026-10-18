// GPL-2.0-or-later. Explicit media-audio routing; no input or alert changes.
#pragma once
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

namespace shuttle_audio_route {
static NSString* const HDMIUID = @"local.shuttle.audio.hdmi";
static NSString* const PreviousUIDPreference = @"OutputPreviousMediaAudioUID";

inline AudioObjectPropertyAddress mediaOutputAddress() {
    return {kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
}
inline AudioDeviceID mediaOutput(OSStatus& status) {
    auto address=mediaOutputAddress();AudioDeviceID device=kAudioObjectUnknown;UInt32 bytes=sizeof(device);
    status=AudioObjectGetPropertyData(kAudioObjectSystemObject,&address,0,nullptr,&bytes,&device);
    return status? kAudioObjectUnknown:device;
}
inline NSString* stringProperty(AudioDeviceID device,AudioObjectPropertySelector selector,OSStatus& status) {
    AudioObjectPropertyAddress address{selector,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    CFStringRef value=nullptr;UInt32 bytes=sizeof(value);
    status=AudioObjectGetPropertyData(device,&address,0,nullptr,&bytes,&value);
    if(status){if(value)CFRelease(value);return nil;}
    return CFBridgingRelease(value);
}
inline NSString* uid(AudioDeviceID device,OSStatus& status) {
    return stringProperty(device,kAudioDevicePropertyDeviceUID,status);
}
inline NSString* name(AudioDeviceID device) {
    OSStatus status=0;NSString* value=stringProperty(device,kAudioObjectPropertyName,status);
    return value.length?value:@"Unknown audio output";
}
inline AudioDeviceID outputForUID(NSString* value,OSStatus& status) {
    AudioObjectPropertyAddress address{kAudioHardwarePropertyTranslateUIDToDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    CFStringRef qualifier=(__bridge CFStringRef)value;AudioDeviceID device=kAudioObjectUnknown;UInt32 bytes=sizeof(device);
    status=AudioObjectGetPropertyData(kAudioObjectSystemObject,&address,sizeof(qualifier),&qualifier,&bytes,&device);
    if(status||device==kAudioObjectUnknown)return kAudioObjectUnknown;
    UInt32 alive=0;bytes=sizeof(alive);address={kAudioDevicePropertyDeviceIsAlive,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    status=AudioObjectGetPropertyData(device,&address,0,nullptr,&bytes,&alive);
    if(status||!alive)return kAudioObjectUnknown;
    address={kAudioDevicePropertyStreams,kAudioDevicePropertyScopeOutput,kAudioObjectPropertyElementMain};bytes=0;
    status=AudioObjectGetPropertyDataSize(device,&address,0,nullptr,&bytes);
    return !status&&bytes>=sizeof(AudioStreamID)?device:kAudioObjectUnknown;
}
inline OSStatus setMediaOutput(AudioDeviceID device) {
    // This is the sole write to Core Audio. In particular, neither the input
    // device nor the separate system/alert-output property is changed.
    auto address=mediaOutputAddress();Boolean writable=false;
    OSStatus status=AudioObjectIsPropertySettable(kAudioObjectSystemObject,&address,&writable);
    if(status)return status;
    if(!writable)return kAudioHardwareIllegalOperationError;
    return AudioObjectSetPropertyData(kAudioObjectSystemObject,&address,0,nullptr,sizeof(device),&device);
}
inline NSString* errorText(OSStatus status) {
    return status?[NSString stringWithFormat:@"Core Audio error %d",(int)status]:@"device unavailable";
}
}
