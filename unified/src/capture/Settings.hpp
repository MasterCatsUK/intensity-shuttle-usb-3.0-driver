// GPL-2.0-or-later. Validated controls shared by the native app and extension.
#pragma once
#import <Foundation/Foundation.h>
#include "VideoProfile.hpp"
static NSString * const SettingsProperty=@"4cc_conf_glob_0";
static NSDictionary *defaultSettings() { return @{ @"standard":@"PAL",@"video_input":@"S-Video",@"audio_input":@"Analog RCA",@"dropout":@"Hold last frame",@"output_size":@"Native",@"input_aspect":@"4:3",@"field_order":@"Top first",@"brightness":@0,@"contrast":@100,@"colour":@100,@"sharpness":@0 }; }
static bool parseSettings(NSDictionary *d,shuttle::CaptureSettings &s) {
    if(![d isKindOfClass:NSDictionary.class]) return false;
    for(NSString *key in @[@"standard",@"video_input",@"audio_input",@"dropout"])
        if(![d[key] isKindOfClass:NSString.class]) return false;
    NSDictionary *videos=@{@"S-Video":@0x06000000,@"Composite":@0x04000000,@"Component":@0x02000000,@"HDMI":@0};
    NSString *standard=d[@"standard"],*video=d[@"video_input"],*audio=d[@"audio_input"],*drop=d[@"dropout"];
    if(![@[@"PAL",@"NTSC"] containsObject:standard] || !videos[video] ||
       ![@[@"Analog RCA",@"Embedded digital"] containsObject:audio] || ![@[@"Hold last frame",@"Black"] containsObject:drop]) return false;
    NSString *output=d[@"output_size"]?:@"Native";
    NSArray *sizes=@[@"Native",@"Square pixels",@"1280x960",@"1440x1080",@"1280x720",@"1920x1080",@"Native interlaced",@"1920x1080 interlaced"];
    if(![output isKindOfClass:NSString.class] || ![sizes containsObject:output]) return false;
    for(NSString *key in @[@"brightness",@"contrast",@"colour",@"sharpness"]) {
        id value=d[key];if(!value)continue;
        double v=[value isKindOfClass:NSNumber.class]?[value doubleValue]:NAN;
        int low=[key isEqual:@"brightness"]?-100:0,high=[key isEqual:@"brightness"]||[key isEqual:@"sharpness"]?100:200;
        if(!std::isfinite(v)||v<low||v>high||v!=std::round(v))return false;
    }
    s.picture.brightness=d[@"brightness"]?[d[@"brightness"] intValue]:0;
    s.picture.contrast=d[@"contrast"]?[d[@"contrast"] intValue]:100;
    s.picture.colour=d[@"colour"]?[d[@"colour"] intValue]:100;
    s.picture.sharpness=d[@"sharpness"]?[d[@"sharpness"] intValue]:0;
    NSString *aspect=d[@"input_aspect"]?:@"4:3";
    if(![aspect isKindOfClass:NSString.class]||![@[@"4:3",@"16:9"] containsObject:aspect])return false;
    NSString *order=d[@"field_order"]?:@"Top first";
    if(![order isKindOfClass:NSString.class]||![@[@"Top first",@"Bottom first"] containsObject:order])return false;
    s.bottomFirst=[order isEqual:@"Bottom first"];
    s.widescreen=[aspect isEqual:@"16:9"];
    s.outputSize=static_cast<shuttle::OutputSize>([sizes indexOfObject:output]);
    s.profile.ntsc=[standard isEqual:@"NTSC"];s.videoInput=[videos[video] unsignedIntValue];
    s.audioInput=[audio isEqual:@"Analog RCA"]?0x10000000:0;s.blackOnDropout=[drop isEqual:@"Black"];return true;
}
static NSString *settingsJSON(NSDictionary *d) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:nil];
    return data?[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]:nil;
}
static NSDictionary *settingsDictionary(NSString *json) {
    if(![json isKindOfClass:NSString.class]) return nil;
    id value=[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    return [value isKindOfClass:NSDictionary.class]?value:nil;
}
