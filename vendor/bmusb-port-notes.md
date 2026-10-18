# bmusb 0.7.8 changes for this macOS prototype

The original GPL-2.0-or-later archive is included alongside the modified source.
The camera service links bmusb and the bundled libusb statically.

- Use macOS pthread naming and QoS; avoid GCC function multiversioning in Clang.
- Use the portable pixel decoder on Apple silicon.
- Keep video USB transfers within the macOS transfer limit, with packet counts
  aligned to eight microframes, and allocate their full possible capacity.
- Do not reset an already-active USB configuration; bound synchronous vendor
  control requests to 1500 ms.
- Keep source-frame byte offsets correct when USB packets fail.
- Permit capture to bypass no-signal A/V matching, bound pending queues and drop
  stale frames, avoiding unbounded latency during loss of lock.
- Track disconnection, pending transfers and shutdown atomically.
- Add shutdown_capture(): cancel transfers, wait for completion, join event and
  dequeue threads, return queued frames, free transfers, release USB interface,
  close device and release the libusb context. Retain buffers if cancellation
  is not confirmed within the timeout, and report failure to the caller.
- Balance the libusb context used by num_cards(), and free an unused diagnostic
  control transfer allocation.
- Replace fatal setup exits with C++ exceptions, allowing the camera service to
  report initialization errors through CMIO.

The extension selects S-Video and analogue audio, accepts complete PAL frames
only and publishes video. Audio buffers are returned to their allocator but no
Core Audio device is implemented. The standalone recorder is a separate port
and does not share this service's runtime state.

For dropout handling, set_audio_observer() borrows each complete raw audio block
on the USB thread before video matching and no-signal dropping. It never takes
allocator ownership. The camera performs a bounded nonblocking stereo send
there; video conversion and timed output run separately. This permits usable
RCA audio to survive missing video frames.
