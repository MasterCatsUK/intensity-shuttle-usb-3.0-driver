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
    d=[defaultSettings() mutableCopy];[d removeObjectForKey:@"input_aspect"];
    assert(parseSettings(d,parsed)&&!parsed.widescreen&&parsed.aspectH()==16&&parsed.aspectV()==15);
    for(NSString *standard in @[@"PAL",@"NTSC"])for(NSString *aspect in @[@"4:3",@"16:9"]){
        d[@"standard"]=standard;d[@"input_aspect"]=aspect;d[@"output_size"]=@"Native";
        assert(parseSettings(settingsDictionary(settingsJSON(d)),parsed));bool wide=[aspect isEqual:@"16:9"],ntsc=[standard isEqual:@"NTSC"];
        assert(parsed.widescreen==wide&&parsed.outputHeight()==(ntsc?480:576));
        assert(parsed.aspectH()==(wide?(ntsc?32:64):(ntsc?8:16))&&parsed.aspectV()==(wide?(ntsc?27:45):(ntsc?9:15)));
        d[@"output_size"]=@"Square pixels";assert(parseSettings(d,parsed)&&parsed.outputWidth()==(wide?(ntsc?854:1024):(ntsc?640:768))&&parsed.aspectH()==1&&parsed.aspectV()==1);
        for(NSString *size in @[@"1280x720",@"1920x1080"]){d[@"output_size"]=size;assert(parseSettings(d,parsed)&&parsed.imageHeight()==parsed.outputHeight()&&parsed.imageWidth()==(wide?parsed.outputWidth():parsed.outputHeight()*4/3));}
    }
    for(id bad in @[@"Auto",@16,NSNull.null]){d[@"input_aspect"]=bad;assert(!parseSettings(d,parsed));}
    d=[defaultSettings() mutableCopy];[d removeObjectForKey:@"field_order"];assert(parseSettings(d,parsed)&&!parsed.bottomFirst&&!parsed.interlaced());
    for(NSString *standard in @[@"PAL",@"NTSC"])for(NSString *size in @[@"Native interlaced",@"1920x1080 interlaced"])for(NSString *order in @[@"Top first",@"Bottom first"]){
        d[@"standard"]=standard;d[@"output_size"]=size;d[@"field_order"]=order;
        assert(parseSettings(settingsDictionary(settingsJSON(d)),parsed)&&parsed.interlaced()&&parsed.bottomFirst==[order isEqual:@"Bottom first"]);
        assert(parsed.sampleRateNom()==([standard isEqual:@"NTSC"]?30000:25));
        assert(parsed.sampleNS(3)==parsed.profile.frameNS(3));
    }
    for(id bad in @[@"Auto",@1,NSNull.null]){d[@"field_order"]=bad;assert(!parseSettings(d,parsed));}
    puts("PASS: legacy settings, PAL/NTSC square pixels, 4:3 upscales, JSON roundtrip, invalid-size rejection");
} }
