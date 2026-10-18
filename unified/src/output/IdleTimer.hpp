// GPL-2.0-or-later. Inactivity means no newly received editor frame, not an unchanged image.
#pragma once
#include <chrono>
namespace shuttle_idle {
class Timer {
public:
    using Clock=std::chrono::steady_clock;
private:
    int seconds;
    Clock::time_point lastActive;
public:
    explicit Timer(int delay=120,Clock::time_point now=Clock::now()):seconds(delay>=-1&&delay<=86400?delay:120),lastActive(now){}
    bool idle(bool freshFrame,Clock::time_point now=Clock::now()){
        if(freshFrame){lastActive=now;return false;}
        return seconds>=0&&now-lastActive>=std::chrono::seconds(seconds);
    }
};
}
