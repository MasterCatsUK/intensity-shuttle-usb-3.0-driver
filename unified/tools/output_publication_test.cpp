// Pure lifecycle test: no CMIO service, network socket, USB or audio changes.
#include "../src/output/SharedOutput.hpp"
#include <cassert>
#include <cstdio>

int main(){
    using shuttle_sink::PublicationGuard;
    using namespace std::chrono;
    auto now=PublicationGuard::Clock::time_point{}+seconds(10);
    PublicationGuard guard;
    // An unexpected sender EOF is withdrawn immediately, including after a
    // normal earlier connection. Merely being published grants no grace.
    assert(guard.keepPublished(true,2,2,now));
    assert(!guard.keepPublished(false,2,2,now));
    guard.normalStreamStopped(false,now);
    assert(!guard.keepPublished(false,2,2,now));
    // Reproduce the observed FCP lifecycle: stop, reconnect 18 ms later,
    // immediate new start. There must be no intervening device withdrawal.
    guard.normalStreamStopped(true,now);
    for(int ms=0;ms<18;++ms)assert(guard.keepPublished(false,2,2,now+milliseconds(ms)));
    assert(guard.keepPublished(true,2,2,now+milliseconds(18)));
    assert(guard.keepPublished(true,2,2,now+milliseconds(115)));
    assert(!guard.keepPublished(false,2,2,now+milliseconds(116)));
    // A physical format change is always a real replacement, even during an
    // expected reconnect. Its immutable stream formats must not be mutated.
    guard.normalStreamStopped(true,now);
    assert(!guard.keepPublished(true,5,2,now+milliseconds(1)));
    assert(!guard.keepPublished(false,2,2,now+milliseconds(2)));
    // A missing helper can never keep a cached device published indefinitely.
    guard.normalStreamStopped(true,now);
    assert(guard.keepPublished(false,2,2,now+milliseconds(PublicationGuard::ReconnectMilliseconds-1)));
    assert(!guard.keepPublished(false,2,2,now+milliseconds(PublicationGuard::ReconnectMilliseconds)));
    guard.clear();assert(!guard.keepPublished(false,2,2,now));
    puts("PASS: normal CMIO stop/reconnect preserves device, unexpected EOF/mode changes withdraw, missing reconnect expires");
}
