// GPL-2.0-or-later. Backward compatible settings and invalid-size rejection.
#include "Settings.hpp"
#include <cassert>
int main() { @autoreleasepool {
    shuttle::CaptureSettings parsed;
    NSMutableDictionary *d=[defaultSettings() mutableCopy];[d removeObjectForKey:@"output_size"];
    assert(parseSettings(d,parsed) && parsed.outputWidth()==720 && parsed.outputHeight()==576);
    d[@"output_size"]=@"Square pixels";assert(parseSettings(d,parsed) && parsed.outputWidth()==768 && parsed.outputHeight()==576 && parsed.aspectH()==parsed.aspectV());
    d[@"standard"]=@"NTSC";assert(parseSettings(d,parsed) && parsed.outputWidth()==640 && parsed.outputHeight()==480);
    d[@"output_size"]=@"1280x960";assert(parseSettings(d,parsed) && parsed.outputWidth()==1280 && parsed.outputHeight()==960);
    d[@"output_size"]=@"1440x1080";assert(parseSettings(settingsDictionary(settingsJSON(d)),parsed) && parsed.outputWidth()==1440 && parsed.outputHeight()==1080);
    for(id invalid in @[@"99999x99999",@123,NSNull.null,@[]]) { d[@"output_size"]=invalid;assert(!parseSettings(d,parsed)); }
    d=[defaultSettings() mutableCopy];d[@"brightness"]=@(-25);d[@"sharpness"]=@60;
    assert(parseSettings(settingsDictionary(settingsJSON(d)),parsed)&&parsed.picture.brightness==-25&&parsed.picture.sharpness==60);
    for(id invalid in @[@(-101),@101,@"50",@1.5,NSNull.null]){d[@"brightness"]=invalid;assert(!parseSettings(d,parsed));}
    d=[defaultSettings() mutableCopy];[d removeObjectForKey:@"brightness"];[d removeObjectForKey:@"contrast"];[d removeObjectForKey:@"colour"];[d removeObjectForKey:@"sharpness"];
    assert(parseSettings(d,parsed)&&parsed.picture.brightness==0&&parsed.picture.contrast==100&&parsed.picture.colour==100&&parsed.picture.sharpness==0);
    puts("PASS: legacy settings, PAL/NTSC square pixels, 4:3 upscales, JSON roundtrip, invalid-size rejection");
} }
