// GPL-2.0-or-later. SDR monitoring scopes measured before monitoring overlays.
#pragma once
#include <vector>
#include <cstdint>
#include <array>
#include <memory>
namespace shuttle_scopes {
enum class View:unsigned {Video,FourUp,Luma,Parade,Overlay,Vectorscope,Histogram};
inline View validView(long value){return value>=0&&value<=6?View(value):View::Video;}
struct RGB {double r,g,b,y,cb,cr;};
RGB decode(uint8_t u,uint8_t y,uint8_t v,bool hd);
struct Analysis {
 static constexpr unsigned Width=960,Height=768,VectorSize=256;
 std::array<std::vector<uint32_t>,4> wave; // luma, R, G, B
 std::array<std::array<uint32_t,256>,3> histogram{};
 std::vector<uint32_t> vector;unsigned columns=Width;uint32_t samples=0;bool hd=false;
 Analysis();void update(const std::vector<uint8_t>& image,unsigned width,unsigned height);
};
struct Raster {unsigned width=0,height=0;std::vector<uint8_t> bgra;};
class Renderer {
 struct Impl;std::unique_ptr<Impl> impl;
public:
 Renderer();~Renderer();
 // image is replaced only after measuring the unaltered rendered input.
 void replace(std::vector<uint8_t>& image,unsigned width,unsigned height,View view);
 Raster render(const std::vector<uint8_t>& source,unsigned sourceWidth,unsigned sourceHeight,unsigned canvasWidth,unsigned canvasHeight,View view,bool outputPixels=false);
};
// Async monitoring never waits for a render on the caller's playback thread.
class AsyncRenderer {
 struct Impl;std::unique_ptr<Impl> impl;
public:
 AsyncRenderer();~AsyncRenderer();
 bool replace(std::vector<uint8_t>& image,unsigned width,unsigned height,View view);
 std::shared_ptr<const Raster> native(const std::vector<uint8_t>& source,unsigned sourceWidth,unsigned sourceHeight,unsigned canvasWidth,unsigned canvasHeight,View view);
 uint64_t completed()const;double renderMilliseconds()const;
};
}
