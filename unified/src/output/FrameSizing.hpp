// GPL-2.0-or-later. Source aspect and output pixel aspect are explicit.
#pragma once
#include <algorithm>
#include <cmath>
namespace shuttle_output {
enum class Sizing { Fit,Fill,Stretch };
inline Sizing sizingValue(long value){return value==1?Sizing::Fill:value==2?Sizing::Stretch:Sizing::Fit;}
struct Rectangle {double x,y,width,height;};
inline Rectangle destination(double sw,double sh,double dw,double dh,double pixelAspect,Sizing sizing){
    if(sw<=0||sh<=0||dw<=0||dh<=0||pixelAspect<=0||!std::isfinite(sw+sh+dw+dh+pixelAspect))return {0,0,0,0};
    if(sizing==Sizing::Stretch)return {0,0,dw,dh};
    double scale=sizing==Sizing::Fill?std::max(dw*pixelAspect/sw,dh/sh):std::min(dw*pixelAspect/sw,dh/sh);
    double w=sw*scale/pixelAspect,h=sh*scale;return {(dw-w)/2,(dh-h)/2,w,h};
}
inline Rectangle crop(double sw,double sh,double dw,double dh,double pixelAspect,Sizing sizing){
    if(sizing!=Sizing::Fill)return {0,0,sw,sh};
    double aspect=dw*pixelAspect/dh,w=sw,h=sh;
    if(sw/sh>aspect)w=sh*aspect;else h=sw/aspect;
    return {(sw-w)/2,(sh-h)/2,w,h};
}
enum class Connector { HDMI,SVideo,Composite,Component };
inline bool connectorSupports(Connector connector,unsigned mode){return mode<6&&((connector!=Connector::SVideo&&connector!=Connector::Composite)||mode==0||mode==3);}
inline unsigned compatibleMode(Connector connector,unsigned mode){return connectorSupports(connector,mode)?mode:(mode>=3?3:0);}
}
