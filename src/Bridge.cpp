// GPL-2.0-or-later. Standalone diagnostic: captures USB and sends bounded video packets.
#include "FrameProtocol.hpp"
#include <CoreMedia/CoreMedia.h>
#include <atomic>
#include <condition_variable>
#include <csignal>
#include <cstdio>
#include <deque>
#include <mutex>
#include <thread>
#include <unistd.h>
#include <cerrno>

using namespace bmusb;
static BMUSBCapture *card;
struct Packet { shuttle::Header header; std::vector<uint8_t> pixels; };
static std::mutex mutex;
static std::condition_variable changed;
static std::deque<Packet> packets;
static std::atomic<bool> done{false};
static volatile sig_atomic_t interrupted = 0;
static uint64_t sequence = 0;
static int output_fd = -1;
static void stop(int) { interrupted = 1; }
static uint64_t nowNS() {
    return CMTimeConvertScale(CMClockGetTime(CMClockGetHostTimeClock()), 1000000000,
                               kCMTimeRoundingMethod_Default).value;
}
static bool writeAll(const void *bytes, size_t count) {
    const uint8_t *p = static_cast<const uint8_t *>(bytes);
    while (count && !interrupted) {
        ssize_t n = write(output_fd, p, count);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return false;
        p += n; count -= size_t(n);
    }
    return count == 0;
}
static void writer() {
    while (!done) {
        Packet p;
        {
            std::unique_lock<std::mutex> lock(mutex);
            changed.wait(lock, []{ return done || !packets.empty(); });
            if (done) break;
            p = std::move(packets.front()); packets.pop_front();
        }
        if (!writeAll(&p.header, sizeof(p.header)) || !writeAll(p.pixels.data(), p.pixels.size())) {
            interrupted = 1;
            break;
        }
    }
}
static void frame(uint16_t tc, FrameAllocator::Frame v, size_t vo, VideoFormat vf,
                  FrameAllocator::Frame a, size_t, AudioFormat) {
    if (shuttle::complete(v, vo, vf)) {
        // Timestamp from the source frame counter, not USB callback arrival:
        // several frames can be delivered in one burst after scheduling delays.
        static bool anchored=false;
        static uint16_t previous=0;
        static uint64_t start=0;
        uint16_t delta=uint16_t(tc-previous);
        if (anchored && delta==0) {
            if(v.data) card->get_video_frame_allocator()->release_frame(v);
            if(a.data) card->get_audio_frame_allocator()->release_frame(a);
            return;
        }
        if (!anchored || delta>250) {
            if(anchored) sequence+=2;
            start=std::max(nowNS()-40000000ULL,anchored ? start+40000000ULL : 0ULL);
            anchored=true;
        } else {
            start+=uint64_t(delta)*40000000ULL;
            sequence+=uint64_t(delta-1)*2;
        }
        previous=tc;
        Packet p[2];
        for (unsigned field = 0; field < 2; ++field) {
            p[field].header.field = field;
            p[field].header.sequence = sequence++;
            p[field].header.host_ns = start + field * 20000000ULL;
            p[field].pixels = shuttle::fieldImage(v.data + vo, vf, field);
        }
        std::lock_guard<std::mutex> lock(mutex);
        // Bound latency when the consumer falls behind.
        while (packets.size() > 2) packets.pop_front();
        packets.push_back(std::move(p[0])); packets.push_back(std::move(p[1]));
        changed.notify_one();
    }
    if (v.data) card->get_video_frame_allocator()->release_frame(v);
    if (a.data) card->get_audio_frame_allocator()->release_frame(a);
}
int shuttle_bridge_main(int argc, char **argv) {
    unsigned seconds = 0;
    bool fixture = false;
    for (int i=1; i<argc; ++i) {
        if (std::strcmp(argv[i], "--fixture") == 0) fixture = true;
        else if (std::strcmp(argv[i], "--seconds") == 0 && i+1<argc) {
            char *end = nullptr; long n = std::strtol(argv[++i], &end, 10);
            if (!*argv[i] || *end || n < 1 || n > 60) return 64;
            seconds = unsigned(n);
        } else return 64;
    }
    output_fd = dup(STDOUT_FILENO);
    if (output_fd < 0 || dup2(STDERR_FILENO, STDOUT_FILENO) < 0) return 1;
    setvbuf(stdout, nullptr, _IOLBF, 0);
    signal(SIGTERM, stop); signal(SIGINT, stop); signal(SIGPIPE, SIG_IGN);
    if (fixture) {
        for (unsigned i=0; i<(seconds ? seconds : 1)*50; ++i) {
            shuttle::Header h; h.field = i % 2; h.sequence = i; h.host_ns = nowNS();
            std::vector<uint8_t> pixels(shuttle::Bytes);
            for (size_t x=0; x<pixels.size(); x+=4) {
                pixels[x] = 128; pixels[x+2] = 128;
                pixels[x+1] = pixels[x+3] = h.field ? 180 : 50;
            }
            if (!writeAll(&h,sizeof(h)) || !writeAll(pixels.data(),pixels.size())) return 1;
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
        }
        return 0;
    }
    if (!BMUSBCapture::num_cards()) { std::fprintf(stderr,"Shuttle is not connected.\n"); return 2; }
    card = new BMUSBCapture(0);
    card->set_no_signal_bypass(true);
    card->set_video_input(0x06000000);
    card->set_audio_input(0x10000000);
    card->set_pixel_format(PixelFormat_8BitYCbCr);
    card->set_frame_callback(frame);
    card->configure_card();
    std::thread output(writer);
    card->start_bm_capture();
    BMUSBCapture::start_bm_thread();
    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
    while (!interrupted && !card->get_disconnected() &&
           (!seconds || std::chrono::steady_clock::now() < deadline))
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    bool disconnected = card->get_disconnected();
    bool clean = card->shutdown_capture();
    done = true; changed.notify_all(); output.join();
    if(clean) { delete card; card=nullptr; }
    return disconnected || !clean ? 3 : 0;
}
#ifndef SHUTTLE_BRIDGE_EMBEDDED
int main(int argc,char **argv) { return shuttle_bridge_main(argc,argv); }
#endif
