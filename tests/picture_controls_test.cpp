// GPL-2.0-or-later. Pixel fixtures: identity, levels, chroma, edge sharpening and stride guards.
// xcrun clang++ -std=c++14 -fsanitize=address,undefined -Isrc tests/picture_controls_test.cpp -o /tmp/shuttle-picture-test
#include "PictureControls.hpp"
#include <cassert>
#include <cstdio>
int main(){
    std::vector<uint8_t> input={40,0,220,255,100,90,150,130,17,18,19,20},copy=input;
    shuttle::PictureControls neutral({});neutral.apply(copy.data(),4,1,12);assert(copy==input);
    shuttle::PictureSettings s;s.colour=0;copy=input;shuttle::PictureControls(s).apply(copy.data(),4,1,12);assert(copy[0]==128&&copy[2]==128&&copy[4]==128&&copy[6]==128);assert(copy[1]==input[1]&&copy[3]==input[3]);
    s={};s.brightness=20;copy=input;shuttle::PictureControls(s).apply(copy.data(),4,1,12);assert(copy[5]>input[5]&&copy[7]>input[7]&&copy[3]==235);assert(copy[0]==input[0]);
    s={};s.contrast=0;copy=input;shuttle::PictureControls(s).apply(copy.data(),4,1,12);assert(copy[1]==126&&copy[3]==126&&copy[5]==126);
    std::vector<uint8_t> edge={128,16,128,16,128,128,128,128,128,235,128,235};s={};s.sharpness=100;copy=edge;shuttle::PictureControls(s).apply(copy.data(),6,1,12);assert(copy[3]==16&&copy[5]>128&&copy[7]<128&&copy[9]==235);
    for(int b:{-100,0,100})for(int c:{0,100,200})for(int col:{0,100,200})for(int sharp:{0,100}){
        s={b,c,col,sharp};copy=input;shuttle::PictureControls(s).apply(copy.data(),4,1,12);for(size_t i=8;i<12;++i)assert(copy[i]==input[i]);
    }
    puts("PASS: neutral byte identity, brightness/contrast/colour, edge enhancement, bounds and row padding");
}
