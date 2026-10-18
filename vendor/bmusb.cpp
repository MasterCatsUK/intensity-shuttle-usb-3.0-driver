// Intensity Shuttle USB3 capture driver, v0.7.8
// Can download 8-bit and 10-bit UYVY/v210-ish frames from HDMI, quite stable
// (can do captures for hours at a time with no drops), except during startup
// 576p60/720p60/1080i60 works, 1080p60 does not work (firmware limitation)
// Audio comes out as 8-channel 24-bit raw audio.

#if (defined(__i386__) || defined(__x86_64__)) && defined(__GNUC__) && !defined(__clang__)
#define HAS_MULTIVERSIONING 1
#endif

#include <assert.h>
#include <errno.h>
#include <libusb.h>
#include <unistd.h>
#include <netinet/in.h>
#include <pthread.h>
#include <sched.h>
#ifdef __APPLE__
#include <pthread/qos.h>
#endif
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if HAS_MULTIVERSIONING
#include <immintrin.h>
#endif
#include "bmusb/bmusb.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <stack>
#include <string>
#include <thread>
#include <stdexcept>

using namespace std;
using namespace std::chrono;
using namespace std::placeholders;

#define USB_VENDOR_BLACKMAGIC 0x1edb
#define MIN_WIDTH 640
#define HEADER_SIZE 44
//#define HEADER_SIZE 0
#define AUDIO_HEADER_SIZE 4

#define FRAME_SIZE (8 << 20)  // 8 MB.
#ifdef __APPLE__
// More queued time for Darwin's USB callbacks; each request spans whole USB frames.
#define USB_VIDEO_TRANSFER_SIZE (1 << 20)
#else
#define USB_VIDEO_TRANSFER_SIZE (128 << 10)  // 128 kB.
#endif

namespace bmusb {

card_connected_callback_t BMUSBCapture::card_connected_callback = nullptr;
bool BMUSBCapture::hotplug_existing_devices = false;

namespace {

FILE *audiofp;

thread usb_thread;
atomic<bool> should_quit;

int v210_stride(int width)
{
	return (width + 5) / 6 * 4 * sizeof(uint32_t);
}

int find_xfer_size_for_width(PixelFormat pixel_format, int width)
{
	// Video seems to require isochronous packets scaled with the width;
	// seemingly six lines is about right, rounded up to the required 1kB
	// multiple.
	// Note that for 10-bit input, you'll need to increase size accordingly.
	int stride;
	if (pixel_format == PixelFormat_10BitYCbCr) {
		stride = v210_stride(width);
	} else {
		stride = width * sizeof(uint16_t);
	}
	int size = stride * 6;
	if (size % 1024 != 0) {
		size &= ~1023;
		size += 1024;
	}
	return size;
}

void change_xfer_size_for_width(PixelFormat pixel_format, int width, libusb_transfer *xfr)
{
	assert(width >= MIN_WIDTH);
	size_t size = find_xfer_size_for_width(pixel_format, width);
	int num_iso_pack = xfr->length / size;
#ifdef __APPLE__
	// Darwin schedules in 1 ms bus frames. A partial group of eight 125 us
	// microframes causes the next request's start to overlap the previous one.
	num_iso_pack -= num_iso_pack % 8;
	assert(num_iso_pack >= 8);
#endif
	if (num_iso_pack != xfr->num_iso_packets ||
	    size != xfr->iso_packet_desc[0].length) {
		xfr->num_iso_packets = num_iso_pack;
		libusb_set_iso_packet_lengths(xfr, size);
	}
}

struct VideoFormatEntry {
	uint16_t normalized_video_format;
	unsigned width, height, second_field_start;
	unsigned extra_lines_top, extra_lines_bottom;
	unsigned frame_rate_nom, frame_rate_den;
	bool interlaced;
};

// Get details for the given video format; returns false if detection was incomplete.
bool decode_video_format(uint16_t video_format, VideoFormat *decoded_video_format)
{
	decoded_video_format->id = video_format;
	decoded_video_format->interlaced = false;

	// TODO: Add these for all formats as we find them.
	decoded_video_format->extra_lines_top = decoded_video_format->extra_lines_bottom = decoded_video_format->second_field_start = 0;

	if (video_format == 0x0800) {
		// No video signal. These green pseudo-frames seem to come at about 30.13 Hz.
		// It's a strange thing, but what can you do.
		decoded_video_format->width = 720;
		decoded_video_format->height = 525;
		decoded_video_format->stride = 720 * 2;
		decoded_video_format->extra_lines_top = 0;
		decoded_video_format->extra_lines_bottom = 0;
		decoded_video_format->frame_rate_nom = 3013;
		decoded_video_format->frame_rate_den = 100;
		decoded_video_format->has_signal = false;
		return true;
	}
	if ((video_format & 0xe000) != 0xe000) {
		printf("Video format 0x%04x does not appear to be a video format. Assuming 60 Hz.\n",
			video_format);
		decoded_video_format->width = 0;
		decoded_video_format->height = 0;
		decoded_video_format->stride = 0;
		decoded_video_format->extra_lines_top = 0;
		decoded_video_format->extra_lines_bottom = 0;
		decoded_video_format->frame_rate_nom = 60;
		decoded_video_format->frame_rate_den = 1;
		decoded_video_format->has_signal = false;
		return false;
	}

	decoded_video_format->has_signal = true;

	// NTSC (480i59.94, I suppose). A special case, see below.
	if ((video_format & ~0x0800) == 0xe101 ||
	    (video_format & ~0x0800) == 0xe1c1 ||
	    (video_format & ~0x0800) == 0xe001) {
		decoded_video_format->width = 720;
		decoded_video_format->height = 480;
		if (video_format & 0x0800) {
			decoded_video_format->stride = 720 * 2;
		} else {
			decoded_video_format->stride = v210_stride(720);
		}
		decoded_video_format->extra_lines_top = 17;
		decoded_video_format->extra_lines_bottom = 28;
		decoded_video_format->frame_rate_nom = 30000;
		decoded_video_format->frame_rate_den = 1001;
		decoded_video_format->second_field_start = 280;
		decoded_video_format->interlaced = true;
		return true;
	}

	// PAL (576i50, I suppose). A special case, see below.
	if ((video_format & ~0x0800) == 0xe109 ||
	    (video_format & ~0x0800) == 0xe1c9 ||
	    (video_format & ~0x0800) == 0xe009 ||
	    (video_format & ~0x0800) == 0xe3e9 ||
	    (video_format & ~0x0800) == 0xe3e1) {
		decoded_video_format->width = 720;
		decoded_video_format->height = 576;
		if (video_format & 0x0800) {
			decoded_video_format->stride = 720 * 2;
		} else {
			decoded_video_format->stride = v210_stride(720);
		}
		decoded_video_format->extra_lines_top = 22;
		decoded_video_format->extra_lines_bottom = 27;
		decoded_video_format->frame_rate_nom = 25;
		decoded_video_format->frame_rate_den = 1;
		decoded_video_format->second_field_start = 335;
		decoded_video_format->interlaced = true;
		return true;
	}

	// 0x8 seems to be a flag about availability of deep color on the input,
	// except when it's not (e.g. it's the only difference between NTSC
	// and PAL). Rather confusing. But we clear it here nevertheless, because
	// usually it doesn't mean anything. 0x0800 appears to be 8-bit input
	// (as opposed to 10-bit).
	//
	// 0x4 is a flag I've only seen from the D4. I don't know what it is.
	uint16_t normalized_video_format = video_format & ~0xe80c;
	constexpr VideoFormatEntry entries[] = {
		{ 0x01f1,  720,  480,   0, 40,  5, 60000, 1001, false },  // 480p59.94 (believed).
		{ 0x0131,  720,  576,   0, 44,  5,    50,    1, false },  // 576p50.
		{ 0x0151,  720,  576,   0, 44,  5,    50,    1, false },  // 576p50.
		{ 0x0011,  720,  576,   0, 44,  5,    50,    1, false },  // 576p50 (5:4).
		{ 0x0143, 1280,  720,   0, 25,  5,    50,    1, false },  // 720p50.
		{ 0x0161, 1280,  720,   0, 25,  5,    50,    1, false },  // 720p50.
		{ 0x0103, 1280,  720,   0, 25,  5,    60,    1, false },  // 720p60.
		{ 0x0125, 1280,  720,   0, 25,  5,    60,    1, false },  // 720p60.
		{ 0x0121, 1280,  720,   0, 25,  5, 60000, 1001, false },  // 720p59.94.
		{ 0x01c3, 1920, 1080,   0, 41,  4,    30,    1, false },  // 1080p30.
		{ 0x0003, 1920, 1080, 583, 20, 25,    30,    1,  true },  // 1080i60.
		{ 0x01e1, 1920, 1080,   0, 41,  4, 30000, 1001, false },  // 1080p29.97.
		{ 0x0021, 1920, 1080, 583, 20, 25, 30000, 1001,  true },  // 1080i59.94.
		{ 0x0063, 1920, 1080,   0, 41,  4,    25,    1, false },  // 1080p25.
		{ 0x0043, 1920, 1080, 583, 20, 25,    25,    1,  true },  // 1080i50.
		{ 0x0083, 1920, 1080,   0, 41,  4,    24,    1, false },  // 1080p24.
		{ 0x00a1, 1920, 1080,   0, 41,  4, 24000, 1001, false },  // 1080p23.98.
	};
	for (const VideoFormatEntry &entry : entries) {
		if (normalized_video_format == entry.normalized_video_format) {
			decoded_video_format->width = entry.width;
			decoded_video_format->height = entry.height;
			if (video_format & 0x0800) {
				decoded_video_format->stride = entry.width * 2;
			} else {
				decoded_video_format->stride = v210_stride(entry.width);
			}
			decoded_video_format->second_field_start = entry.second_field_start;
			decoded_video_format->extra_lines_top = entry.extra_lines_top;
			decoded_video_format->extra_lines_bottom = entry.extra_lines_bottom;
			decoded_video_format->frame_rate_nom = entry.frame_rate_nom;
			decoded_video_format->frame_rate_den = entry.frame_rate_den;
			decoded_video_format->interlaced = entry.interlaced;
			return true;
		}
	}

	printf("Unknown video format 0x%04x (normalized 0x%04x). Assuming 720p60.\n", video_format, normalized_video_format);
	decoded_video_format->width = 1280;
	decoded_video_format->height = 720;
	decoded_video_format->stride = 1280 * 2;
	decoded_video_format->frame_rate_nom = 60;
	decoded_video_format->frame_rate_den = 1;
	return false;
}

// There are seemingly no direct indicators of sample rate; you just get
// one frame's worth and have to guess from that.
int guess_sample_rate(const VideoFormat &video_format, size_t len, int default_rate)
{
	size_t num_samples = len / 3 / 8;
	size_t num_samples_per_second = num_samples * video_format.frame_rate_nom / video_format.frame_rate_den;

	// See if we match or are very close to any of the mandatory HDMI sample rates.
	const int candidate_sample_rates[] = { 32000, 44100, 48000 };
	for (int rate : candidate_sample_rates) {
		if (abs(int(num_samples_per_second) - rate) <= 100) {
			return rate;
		}
	}

	fprintf(stderr, "%ld samples at %d/%d fps (%ld Hz) matches no known sample rate, keeping capture at %d Hz\n",
		num_samples, video_format.frame_rate_nom, video_format.frame_rate_den, num_samples_per_second, default_rate);
	return default_rate;
}

}  // namespace

FrameAllocator::~FrameAllocator() {}

MallocFrameAllocator::MallocFrameAllocator(size_t frame_size, size_t num_queued_frames)
	: frame_size(frame_size)
{
	for (size_t i = 0; i < num_queued_frames; ++i) {
		freelist.push(unique_ptr<uint8_t[]>(new uint8_t[frame_size]));
	}
}

FrameAllocator::Frame MallocFrameAllocator::alloc_frame()
{
	Frame vf;
	vf.owner = this;

	unique_lock<mutex> lock(freelist_mutex);  // Meh.
	if (freelist.empty()) {
		printf("Frame overrun (no more spare frames of size %ld), dropping frame!\n",
			frame_size);
	} else {
		vf.data = freelist.top().release();
		vf.size = frame_size;
		freelist.pop();  // Meh.
	}
	return vf;
}

void MallocFrameAllocator::release_frame(Frame frame)
{
	if (frame.overflow > 0) {
		printf("%d bytes overflow after last (malloc) frame\n", int(frame.overflow));
	}
	unique_lock<mutex> lock(freelist_mutex);
	freelist.push(unique_ptr<uint8_t[]>(frame.data));
}

bool uint16_less_than_with_wraparound(uint16_t a, uint16_t b)
{
	if (a == b) {
		return false;
	} else if (a < b) {
		return (b - a < 0x8000);
	} else {
		int wrap_b = 0x10000 + int(b);
		return (wrap_b - a < 0x8000);
	}
}

void BMUSBCapture::queue_frame(uint16_t format, uint16_t timecode, FrameAllocator::Frame frame, deque<QueuedFrame> *q)
{
	unique_lock<mutex> lock(queue_lock);
	// Keep room in the allocators during loss of signal or writer stalls.
	size_t limit = q == &pending_audio_frames ? 32 : 8;
	while (q->size() >= limit) {
		QueuedFrame old = q->front();
		q->pop_front();
		if (old.frame.data) old.frame.owner->release_frame(old.frame);
	}
	if (!q->empty() && !uint16_less_than_with_wraparound(q->back().timecode, timecode)) {
		printf("Blocks going backwards: prev=0x%04x, cur=0x%04x (dropped)\n",
			q->back().timecode, timecode);
		frame.owner->release_frame(frame);
		return;
	}

	QueuedFrame qf;
	qf.format = format;
	qf.timecode = timecode;
	qf.frame = frame;
	q->push_back(std::move(qf));
	queues_not_empty.notify_one();  // might be spurious
}

void dump_frame(const char *filename, uint8_t *frame_start, size_t frame_len)
{
	FILE *fp = fopen(filename, "wb");
	if (fwrite(frame_start + HEADER_SIZE, frame_len - HEADER_SIZE, 1, fp) != 1) {
		printf("short write!\n");
	}
	fclose(fp);
}

void dump_audio_block(uint8_t *audio_start, size_t audio_len)
{
	if (audiofp != nullptr) {
		fwrite(audio_start + AUDIO_HEADER_SIZE, 1, audio_len - AUDIO_HEADER_SIZE, audiofp);
	}
}

void BMUSBCapture::dequeue_thread_func()
{
	char thread_name[16];
	snprintf(thread_name, sizeof(thread_name), "bmusb_dequeue_%d", card_index);
#ifdef __APPLE__
	pthread_setname_np(thread_name);
#else
	pthread_setname_np(pthread_self(), thread_name);
#endif

	if (has_dequeue_callbacks) {
		dequeue_init_callback();
	}
	size_t last_sample_rate = 48000;
	while (!dequeue_thread_should_quit) {
		unique_lock<mutex> lock(queue_lock);
		queues_not_empty.wait(lock, [this]{ return dequeue_thread_should_quit || (!pending_video_frames.empty() && !pending_audio_frames.empty()); });

		if (dequeue_thread_should_quit) break;

		uint16_t video_timecode = pending_video_frames.front().timecode;
		uint16_t audio_timecode = pending_audio_frames.front().timecode;
		AudioFormat audio_format;
		audio_format.bits_per_sample = 24;
		audio_format.num_channels = 8;
		audio_format.sample_rate = last_sample_rate;
		if (uint16_less_than_with_wraparound(video_timecode, audio_timecode)) {
			printf("Video block 0x%04x without corresponding audio block, dropping.\n",
				video_timecode);
			QueuedFrame video_frame = pending_video_frames.front();
			pending_video_frames.pop_front();
			lock.unlock();
			video_frame_allocator->release_frame(video_frame.frame);
		} else if (uint16_less_than_with_wraparound(audio_timecode, video_timecode)) {
			printf("Audio block 0x%04x without corresponding video block, sending blank frame.\n",
				audio_timecode);
			QueuedFrame audio_frame = pending_audio_frames.front();
			pending_audio_frames.pop_front();
			// Snapshot under the lock: no-signal handling can clear this queue.
			QueuedFrame video_frame = pending_video_frames.front();
			lock.unlock();
			audio_format.id = audio_frame.format;

			// Use the snapshotted video format.
			VideoFormat video_format;
			decode_video_format(video_frame.format, &video_format);

			frame_callback(audio_timecode,
			               FrameAllocator::Frame(), 0, video_format,
			               audio_frame.frame, AUDIO_HEADER_SIZE, audio_format);
		} else {
			QueuedFrame video_frame = pending_video_frames.front();
			QueuedFrame audio_frame = pending_audio_frames.front();
			pending_audio_frames.pop_front();
			pending_video_frames.pop_front();
			lock.unlock();

#if 0
			char filename[255];
			snprintf(filename, sizeof(filename), "%04x%04x.uyvy", video_frame.format, video_timecode);
			dump_frame(filename, video_frame.frame.data, video_frame.data_len);
			dump_audio_block(audio_frame.frame.data, audio_frame.data_len); 
#endif

			VideoFormat video_format;
			audio_format.id = audio_frame.format;
			if (decode_video_format(video_frame.format, &video_format)) {
				if (audio_frame.frame.len != 0) {
					audio_format.sample_rate = guess_sample_rate(video_format, audio_frame.frame.len, last_sample_rate);
					last_sample_rate = audio_format.sample_rate;
				}
				frame_callback(video_timecode,
					       video_frame.frame, HEADER_SIZE, video_format,
					       audio_frame.frame, AUDIO_HEADER_SIZE, audio_format);
			} else {
				video_frame_allocator->release_frame(video_frame.frame);
				audio_format.sample_rate = last_sample_rate;
				frame_callback(video_timecode,
				               FrameAllocator::Frame(), 0, video_format,
					       audio_frame.frame, AUDIO_HEADER_SIZE, audio_format);
			}
		}
	}
	if (has_dequeue_callbacks) {
		dequeue_cleanup_callback();
	}
}

void BMUSBCapture::start_new_frame(const uint8_t *start)
{
	uint16_t format = (start[3] << 8) | start[2];
	uint16_t timecode = (start[1] << 8) | start[0];
	VideoFormat incoming_format;
	have_video_signal = decode_video_format(format, &incoming_format) && incoming_format.has_signal;

	if (current_video_frame.len > 0) {
		current_video_frame.received_timestamp = steady_clock::now();
		if (video_diagnostic || (no_signal_bypass && !have_video_signal)) {
			if (no_signal_bypass && !have_video_signal) {
				unique_lock<mutex> lock(queue_lock);
				for (auto *queue : { &pending_audio_frames, &pending_video_frames }) {
					for (const auto &old : *queue) {
						if (old.frame.data) old.frame.owner->release_frame(old.frame);
					}
					queue->clear();
				}
			}
			VideoFormat vf;
			if (decode_video_format(format, &vf)) {
				assumed_frame_width = vf.width;
				frame_callback(timecode, current_video_frame, HEADER_SIZE, vf,
				               FrameAllocator::Frame(), 0, AudioFormat());
			} else {
				current_video_frame.owner->release_frame(current_video_frame);
			}
			current_video_frame = video_frame_allocator->alloc_frame();
			return;
		}

		// If format is 0x0800 (no signal), add a fake (empty) audio
		// frame to get it out of the queue.
		// TODO: Figure out if there are other formats that come with
		// no audio, and treat them the same.
		if (format == 0x0800) {
			FrameAllocator::Frame fake_audio_frame = audio_frame_allocator->alloc_frame();
			if (fake_audio_frame.data == nullptr) {
				// Oh well, it's just a no-signal frame anyway.
				printf("Couldn't allocate fake audio frame, also dropping no-signal video frame.\n");
				current_video_frame.owner->release_frame(current_video_frame);
				current_video_frame = video_frame_allocator->alloc_frame();
				return;
			}
			queue_frame(format, timecode, fake_audio_frame, &pending_audio_frames);
		}
		//dump_frame();
		queue_frame(format, timecode, current_video_frame, &pending_video_frames);

		// Update the assumed frame width. We might be one frame too late on format changes,
		// but it's much better than asking the user to choose manually.
		VideoFormat video_format;
		if (decode_video_format(format, &video_format)) {
			assumed_frame_width = video_format.width;
		}
	}
	//printf("Found frame start, format 0x%04x timecode 0x%04x, previous frame length was %d/%d\n",
	//	format, timecode,
	//	//start[7], start[6], start[5], start[4],
	//	read_current_frame, FRAME_SIZE);

	current_video_frame = video_frame_allocator->alloc_frame();
	//if (current_video_frame.data == nullptr) {
	//	read_current_frame = -1;
	//} else {
	//	read_current_frame = 0;
	//}
}

void BMUSBCapture::start_new_audio_block(const uint8_t *start)
{
	uint16_t format = (start[3] << 8) | start[2];
	uint16_t timecode = (start[1] << 8) | start[0];
	if (current_audio_frame.len > 0) {
		current_audio_frame.received_timestamp = steady_clock::now();
		if (audio_observer) audio_observer(timecode, current_audio_frame, AUDIO_HEADER_SIZE);
		if (video_diagnostic || (no_signal_bypass && !have_video_signal)) {
			current_audio_frame.owner->release_frame(current_audio_frame);
			current_audio_frame = audio_frame_allocator->alloc_frame();
			return;
		}
		//dump_audio_block();
		queue_frame(format, timecode, current_audio_frame, &pending_audio_frames);
	}
	//printf("Found audio block start, format 0x%04x timecode 0x%04x\n",
	//	format, timecode);
	current_audio_frame = audio_frame_allocator->alloc_frame();
}

#if 0
static void dump_pack(const libusb_transfer *xfr, int offset, const libusb_iso_packet_descriptor *pack)
{
	//	printf("ISO pack%u length:%u, actual_length:%u, offset:%u\n", i, pack->length, pack->actual_length, offset);
	for (unsigned j = 0; j < pack->actual_length; j++) {
	//for (int j = 0; j < min(pack->actual_length, 16u); j++) {
		printf("%02x", xfr->buffer[j + offset]);
		if ((j % 16) == 15)
			printf("\n");
		else if ((j % 8) == 7)
			printf("  ");
		else
			printf(" ");
	}
}
#endif

void memcpy_interleaved(uint8_t *dest1, uint8_t *dest2, const uint8_t *src, size_t n)
{
	assert(n % 2 == 0);
	uint8_t *dptr1 = dest1;
	uint8_t *dptr2 = dest2;

	for (size_t i = 0; i < n; i += 2) {
		*dptr1++ = *src++;
		*dptr2++ = *src++;
	}
}

void add_to_frame(FrameAllocator::Frame *current_frame, const char *frame_type_name, const uint8_t *start, const uint8_t *end)
{
	if (current_frame->data == nullptr ||
	    current_frame->len > current_frame->size ||
	    start == end) {
		return;
	}

	int bytes = end - start;
	if (current_frame->len + bytes > current_frame->size) {
		current_frame->overflow = current_frame->len + bytes - current_frame->size;
		current_frame->len = current_frame->size;
		if (current_frame->overflow > 1048576) {
			printf("%d bytes overflow after last %s frame\n",
				int(current_frame->overflow), frame_type_name);
			current_frame->overflow = 0;
		}
		//dump_frame();
	} else {
		if (current_frame->data_copy != nullptr) {
			memcpy(current_frame->data_copy + current_frame->len, start, bytes);
		}
		if (current_frame->interleaved) {
			uint8_t *data = current_frame->data + current_frame->len / 2;
			uint8_t *data2 = current_frame->data2 + current_frame->len / 2;
			if (current_frame->len % 2 == 1) {
				++data;
				swap(data, data2);
			}
			if (bytes % 2 == 1) {
				*data++ = *start++;
				swap(data, data2);
				++current_frame->len;
				--bytes;
			}
			memcpy_interleaved(data, data2, start, bytes);
			current_frame->len += bytes;
		} else {
			memcpy(current_frame->data + current_frame->len, start, bytes);
			current_frame->len += bytes;
		}
	}
}

#if 0
void avx2_dump(const char *name, __m256i n)
{
	printf("%-10s:", name);
	printf(" %02x", _mm256_extract_epi8(n, 0));
	printf(" %02x", _mm256_extract_epi8(n, 1));
	printf(" %02x", _mm256_extract_epi8(n, 2));
	printf(" %02x", _mm256_extract_epi8(n, 3));
	printf(" %02x", _mm256_extract_epi8(n, 4));
	printf(" %02x", _mm256_extract_epi8(n, 5));
	printf(" %02x", _mm256_extract_epi8(n, 6));
	printf(" %02x", _mm256_extract_epi8(n, 7));
	printf(" ");
	printf(" %02x", _mm256_extract_epi8(n, 8));
	printf(" %02x", _mm256_extract_epi8(n, 9));
	printf(" %02x", _mm256_extract_epi8(n, 10));
	printf(" %02x", _mm256_extract_epi8(n, 11));
	printf(" %02x", _mm256_extract_epi8(n, 12));
	printf(" %02x", _mm256_extract_epi8(n, 13));
	printf(" %02x", _mm256_extract_epi8(n, 14));
	printf(" %02x", _mm256_extract_epi8(n, 15));
	printf(" ");
	printf(" %02x", _mm256_extract_epi8(n, 16));
	printf(" %02x", _mm256_extract_epi8(n, 17));
	printf(" %02x", _mm256_extract_epi8(n, 18));
	printf(" %02x", _mm256_extract_epi8(n, 19));
	printf(" %02x", _mm256_extract_epi8(n, 20));
	printf(" %02x", _mm256_extract_epi8(n, 21));
	printf(" %02x", _mm256_extract_epi8(n, 22));
	printf(" %02x", _mm256_extract_epi8(n, 23));
	printf(" ");
	printf(" %02x", _mm256_extract_epi8(n, 24));
	printf(" %02x", _mm256_extract_epi8(n, 25));
	printf(" %02x", _mm256_extract_epi8(n, 26));
	printf(" %02x", _mm256_extract_epi8(n, 27));
	printf(" %02x", _mm256_extract_epi8(n, 28));
	printf(" %02x", _mm256_extract_epi8(n, 29));
	printf(" %02x", _mm256_extract_epi8(n, 30));
	printf(" %02x", _mm256_extract_epi8(n, 31));
	printf("\n");
}
#endif

#ifndef HAS_MULTIVERSIONING

const uint8_t *add_to_frame_fastpath(FrameAllocator::Frame *current_frame, const uint8_t *start, const uint8_t *limit, const char sync_char)
{
	// No fast path possible unless we have multiversioning.
	return start;
}

#else  // defined(HAS_MULTIVERSIONING)

__attribute__((target("sse4.1")))
const uint8_t *add_to_frame_fastpath_core(FrameAllocator::Frame *current_frame, const uint8_t *aligned_start, const uint8_t *limit, const char sync_char);

__attribute__((target("avx2")))
const uint8_t *add_to_frame_fastpath_core(FrameAllocator::Frame *current_frame, const uint8_t *aligned_start, const uint8_t *limit, const char sync_char);

// Does a memcpy and memchr in one to reduce processing time.
// Note that the benefit is somewhat limited if your L3 cache is small,
// as you'll (unfortunately) spend most of the time loading the data
// from main memory.
//
// Complicated cases are left to the slow path; it basically stops copying
// up until the first instance of "sync_char" (usually a bit before, actually).
// This is fine, since 0x00 bytes shouldn't really show up in normal picture
// data, and what we really need this for is the 00 00 ff ff marker in video data.
__attribute__((target("default")))
const uint8_t *add_to_frame_fastpath(FrameAllocator::Frame *current_frame, const uint8_t *start, const uint8_t *limit, const char sync_char)
{
	// No fast path possible unless we have SSE 4.1 or higher.
	return start;
}

__attribute__((target("sse4.1", "avx2")))
const uint8_t *add_to_frame_fastpath(FrameAllocator::Frame *current_frame, const uint8_t *start, const uint8_t *limit, const char sync_char)
{
	if (current_frame->data == nullptr ||
	    current_frame->len > current_frame->size ||
	    start == limit) {
		return start;
	}
	size_t orig_bytes = limit - start;
	if (orig_bytes < 128) {
		// Don't bother.
		return start;
	}

	// Don't read more bytes than we can write.
	limit = min(limit, start + (current_frame->size - current_frame->len));

	// Align end to 32 bytes.
	limit = (const uint8_t *)(intptr_t(limit) & ~31);

	if (start >= limit) {
		return start;
	}

	// Process [0,31] bytes, such that start gets aligned to 32 bytes.
	const uint8_t *aligned_start = (const uint8_t *)(intptr_t(start + 31) & ~31);
	if (aligned_start != start) {
		const uint8_t *sync_start = (const uint8_t *)memchr(start, sync_char, aligned_start - start);
		if (sync_start == nullptr) {
			add_to_frame(current_frame, "", start, aligned_start);
		} else {
			add_to_frame(current_frame, "", start, sync_start);
			return sync_start;
		}
	}

	// Make the length a multiple of 64.
	if (current_frame->interleaved) {
		if (((limit - aligned_start) % 64) != 0) {
			limit -= 32;
		}
		assert(((limit - aligned_start) % 64) == 0);
	}

	return add_to_frame_fastpath_core(current_frame, aligned_start, limit, sync_char);
}

__attribute__((target("avx2")))
const uint8_t *add_to_frame_fastpath_core(FrameAllocator::Frame *current_frame, const uint8_t *aligned_start, const uint8_t *limit, const char sync_char)
{
	const __m256i needle = _mm256_set1_epi8(sync_char);

	size_t bytes_copied;
	const __restrict __m256i *in = (const __m256i *)aligned_start;
	if (current_frame->interleaved) {
		__restrict __m256i *out1 = (__m256i *)(current_frame->data + (current_frame->len + 1) / 2);
		__restrict __m256i *out2 = (__m256i *)(current_frame->data2 + current_frame->len / 2);
		if (current_frame->len % 2 == 1) {
			swap(out1, out2);
		}

		__m256i shuffle_cw = _mm256_set_epi8(
			15, 13, 11, 9, 7, 5, 3, 1, 14, 12, 10, 8, 6, 4, 2, 0,
			15, 13, 11, 9, 7, 5, 3, 1, 14, 12, 10, 8, 6, 4, 2, 0);
		while (in < (const __m256i *)limit) {
			// Note: For brevity, comments show lanes as if they were 2x64-bit (they're actually 2x128).
			__m256i data1 = _mm256_stream_load_si256(in);         // AaBbCcDd EeFfGgHh
			__m256i data2 = _mm256_stream_load_si256(in + 1);     // IiJjKkLl MmNnOoPp

			__m256i found1 = _mm256_cmpeq_epi8(data1, needle);
			__m256i found2 = _mm256_cmpeq_epi8(data2, needle);
			__m256i found = _mm256_or_si256(found1, found2);

			data1 = _mm256_shuffle_epi8(data1, shuffle_cw);       // ABCDabcd EFGHefgh
			data2 = _mm256_shuffle_epi8(data2, shuffle_cw);       // IJKLijkl MNOPmnop
		
			data1 = _mm256_permute4x64_epi64(data1, 0b11011000);  // ABCDEFGH abcdefgh
			data2 = _mm256_permute4x64_epi64(data2, 0b11011000);  // IJKLMNOP ijklmnop

			__m256i lo = _mm256_permute2x128_si256(data1, data2, 0b00100000);
			__m256i hi = _mm256_permute2x128_si256(data1, data2, 0b00110001);

			_mm256_storeu_si256(out1, lo);  // Store as early as possible, even if the data isn't used.
			_mm256_storeu_si256(out2, hi);

			if (!_mm256_testz_si256(found, found)) {
				break;
			}

			in += 2;
			++out1;
			++out2;
		}
		bytes_copied = (uint8_t *)in - aligned_start;
	} else {
		uint8_t *old_end = current_frame->data + current_frame->len;
		__m256i *out = (__m256i *)old_end;
		while (in < (const __m256i *)limit) {
			__m256i data = _mm256_load_si256(in);
			_mm256_storeu_si256(out, data);  // Store as early as possible, even if the data isn't used.
			__m256i found = _mm256_cmpeq_epi8(data, needle);
			if (!_mm256_testz_si256(found, found)) {
				break;
			}

			++in;
			++out;
		}
		bytes_copied = (uint8_t *)out - old_end;
	}
	if (current_frame->data_copy != nullptr) {
		// TODO: It would be somewhat more cache-efficient to write this in the
		// same loop as above. However, it might not be worth the extra complexity.
		memcpy(current_frame->data_copy + current_frame->len, aligned_start, bytes_copied);
	}
	current_frame->len += bytes_copied;

	//printf("managed to fastpath %ld/%ld bytes\n", (const uint8_t *)in - (const uint8_t *)aligned_start, orig_bytes);
	return (const uint8_t *)in;
}

__attribute__((target("sse4.1")))
const uint8_t *add_to_frame_fastpath_core(FrameAllocator::Frame *current_frame, const uint8_t *aligned_start, const uint8_t *limit, const char sync_char)
{
	const __m128i needle = _mm_set1_epi8(sync_char);

	const __m128i *in = (const __m128i *)aligned_start;
	size_t bytes_copied;
	if (current_frame->interleaved) {
		__m128i *out1 = (__m128i *)(current_frame->data + (current_frame->len + 1) / 2);
		__m128i *out2 = (__m128i *)(current_frame->data2 + current_frame->len / 2);
		if (current_frame->len % 2 == 1) {
			swap(out1, out2);
		}

		__m128i mask_lower_byte = _mm_set1_epi16(0x00ff);
		while (in < (const __m128i *)limit) {
			__m128i data1 = _mm_load_si128(in);
			__m128i data2 = _mm_load_si128(in + 1);
			__m128i data1_lo = _mm_and_si128(data1, mask_lower_byte);
			__m128i data2_lo = _mm_and_si128(data2, mask_lower_byte);
			__m128i data1_hi = _mm_srli_epi16(data1, 8);
			__m128i data2_hi = _mm_srli_epi16(data2, 8);
			__m128i lo = _mm_packus_epi16(data1_lo, data2_lo);
			_mm_storeu_si128(out1, lo);  // Store as early as possible, even if the data isn't used.
			__m128i hi = _mm_packus_epi16(data1_hi, data2_hi);
			_mm_storeu_si128(out2, hi);
			__m128i found1 = _mm_cmpeq_epi8(data1, needle);
			__m128i found2 = _mm_cmpeq_epi8(data2, needle);
			if (!_mm_testz_si128(found1, found1) ||
			    !_mm_testz_si128(found2, found2)) {
				break;
			}

			in += 2;
			++out1;
			++out2;
		}
		bytes_copied = (uint8_t *)in - aligned_start;
	} else {
		uint8_t *old_end = current_frame->data + current_frame->len;
		__m128i *out = (__m128i *)old_end;
		while (in < (const __m128i *)limit) {
			__m128i data = _mm_load_si128(in);
			_mm_storeu_si128(out, data);  // Store as early as possible, even if the data isn't used.
			__m128i found = _mm_cmpeq_epi8(data, needle);
			if (!_mm_testz_si128(found, found)) {
				break;
			}

			++in;
			++out;
		}
		bytes_copied = (uint8_t *)out - old_end;
	}
	if (current_frame->data_copy != nullptr) {
		// TODO: It would be somewhat more cache-efficient to write this in the
		// same loop as above. However, it might not be worth the extra complexity.
		memcpy(current_frame->data_copy + current_frame->len, aligned_start, bytes_copied);
	}
	current_frame->len += bytes_copied;

	//printf("managed to fastpath %ld/%ld bytes\n", (const uint8_t *)in - (const uint8_t *)aligned_start, orig_bytes);
	return (const uint8_t *)in;
}

#endif  // defined(HAS_MULTIVERSIONING)

void decode_packs(const libusb_transfer *xfr,
                  const char *sync_pattern,
                  int sync_length,
                  FrameAllocator::Frame *current_frame,
                  const char *frame_type_name,
                  function<void(const uint8_t *start)> start_callback)
{
	int offset = 0;
	for (int i = 0; i < xfr->num_iso_packets; i++) {
		const libusb_iso_packet_descriptor *pack = &xfr->iso_packet_desc[i];

		if (pack->status != LIBUSB_TRANSFER_COMPLETED) {
			fprintf(stderr, "Error: pack %u/%u status %d\n", i, xfr->num_iso_packets, pack->status);
			offset += pack->length;
			continue;
//exit(5);
		}

		const uint8_t *start = xfr->buffer + offset;
		const uint8_t *limit = start + pack->actual_length;
		while (start < limit) {  // Usually runs only one iteration.
			start = add_to_frame_fastpath(current_frame, start, limit, sync_pattern[0]);
			if (start == limit) break;
			assert(start < limit);

			const unsigned char* start_next_frame = (const unsigned char *)memmem(start, limit - start, sync_pattern, sync_length);
			if (start_next_frame == nullptr) {
				// add the rest of the buffer
				add_to_frame(current_frame, frame_type_name, start, limit);
				break;
			} else {
				add_to_frame(current_frame, frame_type_name, start, start_next_frame);
				start = start_next_frame + sync_length;  // skip sync
				start_callback(start);
			}
		}
#if 0
		dump_pack(xfr, offset, pack);
#endif
		offset += pack->length;
	}
}

void BMUSBCapture::cb_xfr(struct libusb_transfer *xfr)
{
	assert(xfr->user_data != nullptr);
	BMUSBCapture *usb = static_cast<BMUSBCapture *>(xfr->user_data);
	if (usb->stopping || usb->disconnected) { --usb->in_flight; return; }
	if (xfr->status != LIBUSB_TRANSFER_COMPLETED &&
	    xfr->status != LIBUSB_TRANSFER_NO_DEVICE) {
		fprintf(stderr, "error: transfer status %d\n", xfr->status);
		usb->disconnected = true;
		--usb->in_flight;
		return;
	}

	if (xfr->status == LIBUSB_TRANSFER_NO_DEVICE) {
		if (!usb->disconnected) {
			fprintf(stderr, "Device went away, stopping transfers.\n");
			usb->disconnected = true;
			if (usb->card_disconnected_callback) {
				usb->card_disconnected_callback();
			}
		}
		// Don't reschedule the transfer; the loop will stop by itself.
		--usb->in_flight;
		return;
	}

	if (xfr->type == LIBUSB_TRANSFER_TYPE_ISOCHRONOUS) {
		if (xfr->endpoint == 0x84) {
			decode_packs(xfr, "DeckLinkAudioResyncT", 20, &usb->current_audio_frame, "audio", bind(&BMUSBCapture::start_new_audio_block, usb, _1));
		} else {
			decode_packs(xfr, "\x00\x00\xff\xff", 4, &usb->current_video_frame, "video", bind(&BMUSBCapture::start_new_frame, usb, _1));

			// Update the transfer with the new assumed width, if we're in the process of changing formats.
			change_xfer_size_for_width(usb->current_pixel_format, usb->assumed_frame_width, xfr);
		}
	}
	if (xfr->type == LIBUSB_TRANSFER_TYPE_CONTROL) {
		//const libusb_control_setup *setup = libusb_control_transfer_get_setup(xfr);
		uint8_t *buf = libusb_control_transfer_get_data(xfr);
#if 0
		if (setup->wIndex == 44) {
			printf("read timer register: 0x%02x%02x%02x%02x\n", buf[0], buf[1], buf[2], buf[3]);
		} else {
			printf("read register %2d:                      0x%02x%02x%02x%02x\n",
				setup->wIndex, buf[0], buf[1], buf[2], buf[3]);
		}
#else
		memcpy(usb->register_file + usb->current_register, buf, 4);
		usb->current_register = (usb->current_register + 4) % NUM_BMUSB_REGISTERS;
		if (usb->current_register == 0) {
			// read through all of them
			printf("register dump:");
			for (int i = 0; i < NUM_BMUSB_REGISTERS; i += 4) {
				printf(" 0x%02x%02x%02x%02x", usb->register_file[i], usb->register_file[i + 1], usb->register_file[i + 2], usb->register_file[i + 3]);
			}
			printf("\n");
		}
		libusb_fill_control_setup(xfr->buffer,
		    LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_ENDPOINT_IN, /*request=*/214, /*value=*/0,
			/*index=*/usb->current_register, /*length=*/4);
#endif
	}

#if 0
	printf("length:%u, actual_length:%u\n", xfr->length, xfr->actual_length);
	for (i = 0; i < xfr->actual_length; i++) {
		printf("%02x", xfr->buffer[i]);
		if (i % 16)
			printf("\n");
		else if (i % 8)
			printf("  ");
		else
			printf(" ");
	}
#endif

	int rc = libusb_submit_transfer(xfr);
	if (rc < 0) {
		fprintf(stderr, "error re-submitting URB: %s\n", libusb_error_name(rc));
		usb->disconnected = true;
		--usb->in_flight;
	}
}

int BMUSBCapture::cb_hotplug(libusb_context *ctx, libusb_device *dev, libusb_hotplug_event event, void *user_data)
{
	if (card_connected_callback != nullptr) {
		libusb_device_descriptor desc;
                if (libusb_get_device_descriptor(dev, &desc) < 0) {
			fprintf(stderr, "Error getting device descriptor for hotplugged device %p, killing hotplug\n", dev);
			libusb_unref_device(dev);
			return 1;
		}

		if ((desc.idVendor == USB_VENDOR_BLACKMAGIC && desc.idProduct == 0xbd3b) ||
		    (desc.idVendor == USB_VENDOR_BLACKMAGIC && desc.idProduct == 0xbd4f)) {
			card_connected_callback(dev);  // Callback takes ownership.
			return 0;
		}
	}
	libusb_unref_device(dev);
	return 0;
}

void BMUSBCapture::usb_thread_func()
{
#ifdef __APPLE__
	pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0);
	pthread_setname_np("bmusb_usb_drv");
#else
	sched_param param;
	memset(&param, 0, sizeof(param));
	param.sched_priority = 1;
	if (sched_setscheduler(0, SCHED_RR, &param) == -1) {
		printf("couldn't set realtime priority for USB thread: %s\n", strerror(errno));
	}
	pthread_setname_np(pthread_self(), "bmusb_usb_drv");
#endif
	while (!should_quit) {
		timeval sec { 1, 0 };
		int rc = libusb_handle_events_timeout(nullptr, &sec);
		if (rc != LIBUSB_SUCCESS)
			break;
	}
}

namespace {

struct USBCardDevice {
	uint16_t product;
	uint8_t bus, port;
	libusb_device *device;
};

const char *get_product_name(uint16_t product)
{
	if (product == 0xbd3b) {
		return "Intensity Shuttle";
	} else if (product == 0xbd4f) {
		return "UltraStudio SDI";
	} else {
		assert(false);
		return nullptr;
	}
}

string get_card_description(int id, uint8_t bus, uint8_t port, uint16_t product)
{
	const char *product_name = get_product_name(product);

	char buf[256];
	snprintf(buf, sizeof(buf), "USB card %d: Bus %03u Device %03u  %s",
		id, bus, port, product_name);
	return buf;
}

vector<USBCardDevice> find_all_cards()
{
	libusb_device **devices;
	ssize_t num_devices = libusb_get_device_list(nullptr, &devices);
	if (num_devices == -1) {
		fprintf(stderr, "Error finding USB devices\n");
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}
	vector<USBCardDevice> found_cards;
	for (ssize_t i = 0; i < num_devices; ++i) {
		libusb_device_descriptor desc;
                if (libusb_get_device_descriptor(devices[i], &desc) < 0) {
			fprintf(stderr, "Error getting device descriptor for device %d\n", int(i));
			throw std::runtime_error("bmusb USB operation failed; see service log");
		}

		uint8_t bus = libusb_get_bus_number(devices[i]);
		uint8_t port = libusb_get_port_number(devices[i]);

		if (!(desc.idVendor == USB_VENDOR_BLACKMAGIC && desc.idProduct == 0xbd3b) &&
		    !(desc.idVendor == USB_VENDOR_BLACKMAGIC && desc.idProduct == 0xbd4f)) {
			libusb_unref_device(devices[i]);
			continue;
		}

		found_cards.push_back({ desc.idProduct, bus, port, devices[i] });
	}
	libusb_free_device_list(devices, 0);

	// Sort the devices to get a consistent ordering.
	sort(found_cards.begin(), found_cards.end(), [](const USBCardDevice &a, const USBCardDevice &b) {
		if (a.product != b.product)
			return a.product < b.product;
		if (a.bus != b.bus)
			return a.bus < b.bus;
		return a.port < b.port;
	});

	return found_cards;
}

libusb_device_handle *open_card(int card_index, string *description)
{
	vector<USBCardDevice> found_cards = find_all_cards();

	for (size_t i = 0; i < found_cards.size(); ++i) {
		string tmp_description = get_card_description(i, found_cards[i].bus, found_cards[i].port, found_cards[i].product);
		fprintf(stderr, "%s\n", tmp_description.c_str());
		if (i == size_t(card_index)) {
			*description = tmp_description;
		}
	}

	if (size_t(card_index) >= found_cards.size()) {
		fprintf(stderr, "Could not open card %d (only %d found)\n", card_index, int(found_cards.size()));
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}

	libusb_device_handle *devh;
	int rc = libusb_open(found_cards[card_index].device, &devh);
	if (rc < 0) {
		fprintf(stderr, "Error opening card %d: %s\n", card_index, libusb_error_name(rc));
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}

	for (size_t i = 0; i < found_cards.size(); ++i) {
		libusb_unref_device(found_cards[i].device);
	}

	return devh;
}

libusb_device_handle *open_card(unsigned card_index, libusb_device *dev, string *description)
{
	uint8_t bus = libusb_get_bus_number(dev);
	uint8_t port = libusb_get_port_number(dev);

	libusb_device_descriptor desc;
	if (libusb_get_device_descriptor(dev, &desc) < 0) {
		fprintf(stderr, "Error getting device descriptor for device %p\n", dev);
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}

	*description = get_card_description(card_index, bus, port, desc.idProduct);

	libusb_device_handle *devh;
	int rc = libusb_open(dev, &devh);
	if (rc < 0) {
		fprintf(stderr, "Error opening card %p: %s\n", dev, libusb_error_name(rc));
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}

	return devh;
}

}  // namespace

unsigned BMUSBCapture::num_cards()
{
	int rc = libusb_init(nullptr);
	if (rc < 0) {
		fprintf(stderr, "Error initializing libusb: %s\n", libusb_error_name(rc));
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}

	vector<USBCardDevice> found_cards = find_all_cards();
	unsigned ret = found_cards.size();
	for (size_t i = 0; i < found_cards.size(); ++i) {
		libusb_unref_device(found_cards[i].device);
	}
	libusb_exit(nullptr);
	return ret;
}

void BMUSBCapture::set_pixel_format(PixelFormat pixel_format)
{
	current_pixel_format = pixel_format;
	update_capture_mode();
}

void BMUSBCapture::configure_card()
{
	if (video_frame_allocator == nullptr) {
		owned_video_frame_allocator.reset(new MallocFrameAllocator(FRAME_SIZE, NUM_QUEUED_VIDEO_FRAMES));
		set_video_frame_allocator(owned_video_frame_allocator.get());
	}
	if (audio_frame_allocator == nullptr) {
		owned_audio_frame_allocator.reset(new MallocFrameAllocator(65536, NUM_QUEUED_AUDIO_FRAMES));
		set_audio_frame_allocator(owned_audio_frame_allocator.get());
	}
	dequeue_thread_should_quit = false;
	dequeue_thread = thread(&BMUSBCapture::dequeue_thread_func, this);

	int rc;
	struct libusb_transfer *xfr;

	rc = libusb_init(nullptr);
	if (rc < 0) {
		fprintf(stderr, "Error initializing libusb: %s\n", libusb_error_name(rc));
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}

	if (dev == nullptr) {
		devh = open_card(card_index, &description);
	} else {
		devh = open_card(card_index, dev, &description);
		libusb_unref_device(dev);
	}
	if (!devh) {
		fprintf(stderr, "Error finding USB device\n");
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}

	libusb_config_descriptor *config;
	rc = libusb_get_config_descriptor(libusb_get_device(devh), /*config_index=*/0, &config);
	if (rc < 0) {
		fprintf(stderr, "Error getting configuration: %s\n", libusb_error_name(rc));
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}

#if 0
	printf("%d interface\n", config->bNumInterfaces);
	for (int interface_number = 0; interface_number < config->bNumInterfaces; ++interface_number) {
		printf("  interface %d\n", interface_number);
		const libusb_interface *interface = &config->interface[interface_number];
		for (int altsetting = 0; altsetting < interface->num_altsetting; ++altsetting) {
			const libusb_interface_descriptor *interface_desc = &interface->altsetting[altsetting];
			printf("    alternate setting %d\n", interface_desc->bAlternateSetting);
			for (int endpoint_number = 0; endpoint_number < interface_desc->bNumEndpoints; ++endpoint_number) {
				const libusb_endpoint_descriptor *endpoint = &interface_desc->endpoint[endpoint_number];
				printf("        endpoint address 0x%02x\n", endpoint->bEndpointAddress);
			}
		}
	}
#endif

	libusb_free_config_descriptor(config);
	int active_configuration = 0;
	rc = libusb_get_configuration(devh, &active_configuration);
	if (rc == 0 && active_configuration != 1) {
		rc = libusb_set_configuration(devh, /*configuration=*/1);
	}
	if (rc < 0) {
		fprintf(stderr, "Error setting configuration 1: %s\n", libusb_error_name(rc));
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}

	rc = libusb_claim_interface(devh, 0);
	if (rc < 0) {
		fprintf(stderr, "Error claiming interface 0: %s\n", libusb_error_name(rc));
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}

	// Alternate setting 1 is output, alternate setting 2 is input.
	// Card is reset when switching alternates, so the driver uses
	// this “double switch” when it wants to reset.
	//
	// There's also alternate settings 3 and 4, which seem to be
	// like 1 and 2 except they advertise less bandwidth needed.
	rc = libusb_set_interface_alt_setting(devh, /*interface=*/0, /*alternate_setting=*/1);
	if (rc < 0) {
		fprintf(stderr, "Error setting alternate 1: %s\n", libusb_error_name(rc));
		if (rc == LIBUSB_ERROR_NOT_FOUND) {
			fprintf(stderr, "This is usually because the card came up in USB2 mode.\n");
			fprintf(stderr, "In particular, this tends to happen if you boot up with the\n");
			fprintf(stderr, "card plugged in; just unplug and replug it, and it usually works.\n");
		}
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}
	rc = libusb_set_interface_alt_setting(devh, /*interface=*/0, /*alternate_setting=*/2);
	if (rc < 0) {
		fprintf(stderr, "Error setting alternate 2: %s\n", libusb_error_name(rc));
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}
#if 0
	rc = libusb_set_interface_alt_setting(devh, /*interface=*/0, /*alternate_setting=*/1);
	if (rc < 0) {
		fprintf(stderr, "Error setting alternate 1: %s\n", libusb_error_name(rc));
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}
#endif

#if 0
	rc = libusb_claim_interface(devh, 3);
	if (rc < 0) {
		fprintf(stderr, "Error claiming interface 3: %s\n", libusb_error_name(rc));
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}
#endif

	// theories:
	//   44 is some kind of timer register (first 16 bits count upwards)
	//   24 is some sort of watchdog?
	//      you can seemingly set it to 0x73c60001 and that bit will eventually disappear
	//      (or will go to 0x73c60010?), also seen 0x73c60100
	//   12 also changes all the time, unclear why	
	//   16 seems to be autodetected mode somehow
	//      --    this is e00115e0 after reset?
	//                    ed0115e0 after mode change [to output?]
	//                    2d0015e0 after more mode change [to input]
	//                    ed0115e0 after more mode change
	//                    2d0015e0 after more mode change
	//
	//                    390115e0 seems to indicate we have signal
	//         changes to 200115e0 when resolution changes/we lose signal, driver resets after a while
	//
	//                    200015e0 on startup
	//         changes to 250115e0 when we sync to the signal
	//
	//    so only first 16 bits count, and 0x0100 is a mask for ok/stable signal?
	//
	//    Bottom 16 bits of this register seem to be firmware version number (possibly not all all of them).
	//
	//    28 and 32 seems to be analog audio input levels (one byte for each of the eight channels).
	//    however, if setting 32 with HDMI embedded audio, it is immediately overwritten back (to 0xe137002a).
	//
	//    4, 8, 20 are unclear. seem to be some sort of bitmask, but we can set them to 0 with no apparent effect.
	//    perhaps some of them are related to analog output?
	//
	//    36 can be set to 0 with no apparent effect (all of this tested on both video and audio),
	//    but the driver sets it to 0x8036802a at some point.
	//
	//    all of this is on request 214/215. other requests (192, 219,
	//    222, 223, 224) are used for firmware upgrade. Probably best to
	//    stay out of it unless you know what you're doing.
	//
	//
	// register 16:
 	// first byte is 0x39 for a stable 576p60 signal, 0x2d for a stable 720p60 signal, 0x20 for no signal
	//
	// theories:
	//   0x01 - stable signal
	//   0x04 - deep color
	//   0x08 - unknown (audio??)
	//   0x20 - 720p??
	//   0x30 - 576p??

	update_capture_mode();

	struct ctrl {
		int endpoint;
		int request;
		int index;
		uint32_t data;
	};
	static const ctrl ctrls[] = {
		{ LIBUSB_ENDPOINT_IN,  214, 16, 0 },
		{ LIBUSB_ENDPOINT_IN,  214,  0, 0 },

		//{ LIBUSB_ENDPOINT_OUT, 215,  0, 0x80000100 },
		//{ LIBUSB_ENDPOINT_OUT, 215,  0, 0x09000000 },
		{ LIBUSB_ENDPOINT_OUT, 215, 24, 0x73c60001 },  // latch for frame start?
		{ LIBUSB_ENDPOINT_IN,  214, 24, 0 },  // 
	};

	for (unsigned req = 0; req < sizeof(ctrls) / sizeof(ctrls[0]); ++req) {
		uint32_t flipped = htonl(ctrls[req].data);
		static uint8_t value[4];
		memcpy(value, &flipped, sizeof(flipped));
		int size = sizeof(value);
		//if (ctrls[req].request == 215) size = 0;
		rc = libusb_control_transfer(devh, LIBUSB_REQUEST_TYPE_VENDOR | ctrls[req].endpoint,
			/*request=*/ctrls[req].request, /*value=*/0, /*index=*/ctrls[req].index, value, size, /*timeout=*/1500);
		if (rc < 0) {
			fprintf(stderr, "Error on control %d: %s\n", ctrls[req].index, libusb_error_name(rc));
			throw std::runtime_error("bmusb USB operation failed; see service log");
		}

		if (ctrls[req].index == 16 && rc == 4) {
			printf("Card firmware version: 0x%02x%02x\n", value[2], value[3]);
		}

#if 0
		printf("rc=%d: ep=%d@%d %d -> 0x", rc, ctrls[req].endpoint, ctrls[req].request, ctrls[req].index);
		for (int i = 0; i < rc; ++i) {
			printf("%02x", value[i]);
		}
		printf("\n");
#endif
	}

#if 0
	// DEBUG
	for ( ;; ) {
		static int my_index = 0;
		static uint8_t value[4];
		int size = sizeof(value);
		rc = libusb_control_transfer(devh, LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_ENDPOINT_IN,
			/*request=*/214, /*value=*/0, /*index=*/my_index, value, size, /*timeout=*/1500);
		if (rc < 0) {
			fprintf(stderr, "Error on control\n");
			throw std::runtime_error("bmusb USB operation failed; see service log");
		}
		printf("rc=%d index=%d: 0x", rc, my_index);
		for (int i = 0; i < rc; ++i) {
			printf("%02x", value[i]);
		}
		printf("\n");
	}
#endif

#if 0
	// set up an asynchronous transfer of the timer register
	static uint8_t cmdbuf[LIBUSB_CONTROL_SETUP_SIZE + 4];
	static int completed = 0;

	xfr = libusb_alloc_transfer(0);
	libusb_fill_control_setup(cmdbuf,
	    LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_ENDPOINT_IN, /*request=*/214, /*value=*/0,
		/*index=*/44, /*length=*/4);
	libusb_fill_control_transfer(xfr, devh, cmdbuf, cb_xfr, &completed, 0);
	xfr->user_data = this;
	libusb_submit_transfer(xfr);

	// set up an asynchronous transfer of register 24
	static uint8_t cmdbuf2[LIBUSB_CONTROL_SETUP_SIZE + 4];
	static int completed2 = 0;

	xfr = libusb_alloc_transfer(0);
	libusb_fill_control_setup(cmdbuf2,
	    LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_ENDPOINT_IN, /*request=*/214, /*value=*/0,
		/*index=*/24, /*length=*/4);
	libusb_fill_control_transfer(xfr, devh, cmdbuf2, cb_xfr, &completed2, 0);
	xfr->user_data = this;
	libusb_submit_transfer(xfr);
#endif

	// set up an asynchronous transfer of the register dump
	static uint8_t cmdbuf3[LIBUSB_CONTROL_SETUP_SIZE + 4];
	static int completed3 = 0;

	xfr = libusb_alloc_transfer(0);
	libusb_fill_control_setup(cmdbuf3,
	    LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_ENDPOINT_IN, /*request=*/214, /*value=*/0,
		/*index=*/current_register, /*length=*/4);
	libusb_fill_control_transfer(xfr, devh, cmdbuf3, cb_xfr, &completed3, 0);
	xfr->user_data = this;
	//libusb_submit_transfer(xfr);
	libusb_free_transfer(xfr); // Diagnostic control transfer is not submitted.

	//audiofp = fopen("audio.raw", "wb");

	// set up isochronous transfers for audio and video
	for (int e = 3; e <= 4; ++e) {
		int num_transfers = 6;
		for (int i = 0; i < num_transfers; ++i) {
			size_t buf_size;
			int num_iso_pack, size;
			if (e == 3) {
				// Allocate for minimum width (because that will give us the most
				// number of packets, so we don't need to reallocate, but we'll
				// default to 720p for the first frame.
				size = find_xfer_size_for_width(PixelFormat_8BitYCbCr, MIN_WIDTH);
				num_iso_pack = USB_VIDEO_TRANSFER_SIZE / size;
				buf_size = USB_VIDEO_TRANSFER_SIZE;
			} else {
				size = 0xc0;
				num_iso_pack = 80;
				buf_size = num_iso_pack * size;
			}
			int num_bytes = num_iso_pack * size;
			assert(size_t(num_bytes) <= buf_size);
#if LIBUSB_API_VERSION >= 0x01000105
			uint8_t *buf = libusb_dev_mem_alloc(devh, buf_size);
#else
			uint8_t *buf = nullptr;
#endif
			bool dma = buf != nullptr;
			if (buf == nullptr) {
#ifndef __APPLE__
				fprintf(stderr, "Failed to allocate persistent DMA memory ");
#if LIBUSB_API_VERSION >= 0x01000105
				fprintf(stderr, "(probably too old kernel; use 4.6.0 or newer).\n");
#else
				fprintf(stderr, "(compiled against too old libusb-1.0).\n");
#endif
				fprintf(stderr, "Will go slower, and likely fail due to memory fragmentation after a few hours.\n");
#endif
				buf = new uint8_t[buf_size];
			}

			xfr = libusb_alloc_transfer(num_iso_pack);
			if (!xfr) {
				fprintf(stderr, "oom\n");
				throw std::runtime_error("bmusb USB operation failed; see service log");
			}

			int ep = LIBUSB_ENDPOINT_IN | e;
			libusb_fill_iso_transfer(xfr, devh, ep, buf, buf_size,
				num_iso_pack, cb_xfr, nullptr, 0);
			libusb_set_iso_packet_lengths(xfr, size);
			xfr->user_data = this;

			if (e == 3) {
				change_xfer_size_for_width(current_pixel_format, assumed_frame_width, xfr);
			}

			iso_xfrs.push_back(xfr);
			iso_dma.push_back(dma);
		}
	}
}

void BMUSBCapture::start_bm_capture()
{
	int i = 0;
	for (libusb_transfer *xfr : iso_xfrs) {
		++in_flight;
		int rc = libusb_submit_transfer(xfr);
		++i;
		if (rc < 0) {
			--in_flight;
			//printf("num_bytes=%d\n", num_bytes);
			fprintf(stderr, "Error submitting iso to endpoint 0x%02x, number %d: %s\n",
				xfr->endpoint, i, libusb_error_name(rc));
			throw std::runtime_error("bmusb USB operation failed; see service log");
		}
	}


#if 0
	libusb_release_interface(devh, 0);
out:
	if (devh)
		libusb_close(devh);
	libusb_exit(nullptr);
	return rc;
#endif
}

void BMUSBCapture::stop_dequeue_thread()
{
	dequeue_thread_should_quit = true;
	queues_not_empty.notify_all();
	if (dequeue_thread.joinable()) dequeue_thread.join();
}

void BMUSBCapture::start_bm_thread()
{
	// Devices leaving are discovered by seeing the isochronous packets
	// coming back with errors, so only care about devices joining.
	if (card_connected_callback != nullptr) {
		if (libusb_hotplug_register_callback(
			nullptr, LIBUSB_HOTPLUG_EVENT_DEVICE_ARRIVED, hotplug_existing_devices ? LIBUSB_HOTPLUG_ENUMERATE : LIBUSB_HOTPLUG_NO_FLAGS,
			USB_VENDOR_BLACKMAGIC, LIBUSB_HOTPLUG_MATCH_ANY, LIBUSB_HOTPLUG_MATCH_ANY,
			&BMUSBCapture::cb_hotplug, nullptr, nullptr) < 0) {
			fprintf(stderr, "libusb_hotplug_register_callback() failed\n");
			throw std::runtime_error("bmusb USB operation failed; see service log");
		}
	}

	should_quit = false;
	usb_thread = thread(&BMUSBCapture::usb_thread_func);
}

void BMUSBCapture::stop_bm_thread()
{
	should_quit = true;
	libusb_interrupt_event_handler(nullptr);
	if (usb_thread.joinable()) usb_thread.join();
}

bool BMUSBCapture::shutdown_capture()
{
	stopping = true;
	for (auto *xfr : iso_xfrs) libusb_cancel_transfer(xfr);
	auto deadline = steady_clock::now() + seconds(3);
	while (in_flight > 0 && steady_clock::now() < deadline)
		this_thread::sleep_for(milliseconds(1));
	stop_bm_thread();
	stop_dequeue_thread();
	if (in_flight != 0) return false; // Retain buffers if cancellation was not confirmed.
	for (size_t i=0;i<iso_xfrs.size();++i) {
		auto *xfr=iso_xfrs[i];
		if (iso_dma[i]) libusb_dev_mem_free(devh,xfr->buffer,xfr->length);
		else delete[] xfr->buffer;
		libusb_free_transfer(xfr);
	}
	iso_xfrs.clear(); iso_dma.clear();
	for (auto *queue : { &pending_video_frames, &pending_audio_frames }) {
		for (const auto &f : *queue) if(f.frame.data) f.frame.owner->release_frame(f.frame);
		queue->clear();
	}
	if(current_video_frame.data) current_video_frame.owner->release_frame(current_video_frame);
	if(current_audio_frame.data) current_audio_frame.owner->release_frame(current_audio_frame);
	current_video_frame = FrameAllocator::Frame();
	current_audio_frame = FrameAllocator::Frame();
	if(devh) {
		libusb_release_interface(devh,0);
		libusb_close(devh); devh=nullptr;
		libusb_exit(nullptr);
	}
	return true;
}

map<uint32_t, VideoMode> BMUSBCapture::get_available_video_modes() const
{
	// The USB3 cards autodetect, and seem to have no provision for forcing modes.
	VideoMode auto_mode;
	auto_mode.name = "Autodetect";
	auto_mode.autodetect = true;
	return {{ 0, auto_mode }};
}

uint32_t BMUSBCapture::get_current_video_mode() const
{
	return 0;  // Matches get_available_video_modes().
}

void BMUSBCapture::set_video_mode(uint32_t video_mode_id)
{
	assert(video_mode_id == 0);  // Matches get_available_video_modes().
}

std::map<uint32_t, std::string> BMUSBCapture::get_available_video_inputs() const
{
	return {
		{ 0x00000000, "HDMI/SDI" },
		{ 0x02000000, "Component" },
		{ 0x04000000, "Composite" },
		{ 0x06000000, "S-video" }
	};
}

void BMUSBCapture::set_video_input(uint32_t video_input_id)
{
	assert((video_input_id & ~0x06000000) == 0);
	current_video_input = video_input_id;
	update_capture_mode();
}

std::map<uint32_t, std::string> BMUSBCapture::get_available_audio_inputs() const
{
	return {
		{ 0x00000000, "Embedded" },
		{ 0x10000000, "Analog" }
	};
}

void BMUSBCapture::set_audio_input(uint32_t audio_input_id)
{
	assert((audio_input_id & ~0x10000000) == 0);
	current_audio_input = audio_input_id;
	update_capture_mode();
}

void BMUSBCapture::update_capture_mode()
{
	if (devh == nullptr) {
		return;
	}

	// Clearing the 0x08000000 bit seems to change the capture format (other source?).
	uint32_t mode = htonl(0x09000000 | current_video_input | current_audio_input);
	if (current_pixel_format == PixelFormat_8BitYCbCr) {
		mode |= htonl(0x20000000);
	} else {
		assert(current_pixel_format == PixelFormat_10BitYCbCr);
	}

	int rc = libusb_control_transfer(devh, LIBUSB_REQUEST_TYPE_VENDOR | LIBUSB_ENDPOINT_OUT,
		/*request=*/215, /*value=*/0, /*index=*/0, (unsigned char *)&mode, sizeof(mode), /*timeout=*/1500);
	if (rc < 0) {
		fprintf(stderr, "Error on setting mode: %s\n", libusb_error_name(rc));
		throw std::runtime_error("bmusb USB operation failed; see service log");
	}
}

}  // namespace bmusb
