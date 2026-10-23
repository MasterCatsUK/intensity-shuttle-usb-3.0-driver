// GPL-2.0-or-later. User-visible full-cadence contract under USB transfer bursts.
#include "../src/PreviewClock.hpp"
#include <cassert>
#include <cmath>
#include <cstdio>
int main(){
    for(unsigned nom:{25u,30000u}){
        unsigned den=nom==25?1:1001;double rate=double(nom)/den;
        player::PreviewClock clock;uint64_t last=0;unsigned changes=0;
        for(unsigned tick=0;tick<600;++tick){
            uint64_t ns=uint64_t(tick)*1000000000/60;
            // Four 32-ms USB slots produce frames ahead of physical playout.
            uint64_t newest=uint64_t(std::ceil((double(ns/32000000)*.032+.128)*rate));
            uint64_t frame=clock.choose(newest,nom,den,ns);
            assert(frame==1+uint64_t(static_cast<unsigned __int128>(ns)*nom/(1000000000ULL*den)));
            assert(frame>=last&&frame<=last+1);if(frame!=last)++changes;last=frame;
        }
        unsigned expected=1+unsigned((599ULL*1000000000/60)*static_cast<unsigned __int128>(nom)/(1000000000ULL*den));
        assert(changes==expected);printf("PASS: %.5f fps preview displays all %u due frames across 600 UI refreshes despite 32-ms USB bursts.\n",rate,changes);
        assert(clock.choose(1000,nom,den,11000000000)==1000-player::PreviewFrames+1); // bounded recovery after UI stall
        clock.reset();assert(clock.choose(0,nom,den,0)==0);assert(clock.choose(1,0,den,0)==0);
    }
}
