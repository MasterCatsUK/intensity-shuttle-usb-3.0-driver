// GPL-2.0-or-later. Explicit temporary diagnostic route with guarded restoration.
#import <Foundation/Foundation.h>
#include "../src/output/AudioRoute.hpp"
int main(int argc,char**argv){@autoreleasepool{
    using namespace shuttle_audio_route;
    if(argc!=3)return 64;NSString* command=@(argv[1]);NSString* path=@(argv[2]);OSStatus status=0;
    AudioDeviceID current=mediaOutput(status);NSString* currentUID=status?nil:uid(current,status);
    if(status||!currentUID.length){fprintf(stderr,"Cannot read media output: %s\n",errorText(status).UTF8String);return 1;}
    if([command isEqual:@"select"]){
        if([currentUID isEqual:HDMIUID]){fprintf(stderr,"HDMI is already selected; prior route not replaced\n");return 2;}
        AudioDeviceID hdmi=outputForUID(HDMIUID,status);if(!hdmi||status)return 3;
        NSDictionary* saved=@{@"previous_uid":currentUID,@"previous_name":name(current),@"target_uid":HDMIUID};
        NSData* data=[NSJSONSerialization dataWithJSONObject:saved options:NSJSONWritingPrettyPrinted error:nil];
        if(![data writeToFile:path options:NSDataWritingAtomic error:nil])return 4;
        status=setMediaOutput(hdmi);if(status){fprintf(stderr,"Route failed: %d\n",int(status));return 5;}
        current=mediaOutput(status);currentUID=status?nil:uid(current,status);
        if(status||![currentUID isEqual:HDMIUID])return 6;
        printf("HDMI media audio selected; previous output saved: %s\n",[saved[@"previous_name"] UTF8String]);return 0;
    }
    if([command isEqual:@"restore"]){
        NSDictionary* saved=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:nil];
        NSString* prior=saved[@"previous_uid"];if(!prior.length||[prior isEqual:HDMIUID])return 7;
        if(![currentUID isEqual:HDMIUID]){puts("Kept the user's later audio-output selection");return 0;}
        AudioDeviceID previous=outputForUID(prior,status);if(!previous||status)return 8;
        status=setMediaOutput(previous);if(status)return 9;printf("Restored media audio: %s\n",name(previous).UTF8String);return 0;
    }
    return 64;
}}
