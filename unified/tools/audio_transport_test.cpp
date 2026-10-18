#include "../src/output/OutputAudio.hpp"
#include <cassert>
#include <limits>
int main(){using namespace shuttle_output_audio;Reader reader;int fd=socket(AF_INET,SOCK_DGRAM,0);assert(fd>=0);sockaddr_in a{};a.sin_len=sizeof(a);a.sin_family=AF_INET;a.sin_port=htons(Port);a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);assert(connect(fd,(sockaddr*)&a,sizeof(a))==0);
    Packet packet;packet.firstSample=1000000;packet.frames=480;for(unsigned n=0;n<960;++n)packet.samples[n]=n%2?-0.25f:0.5f;
    assert(valid(packet,sizeof(packet)));assert(!valid(packet,sizeof(packet)-1));assert(send(fd,&packet,sizeof(packet),0)==sizeof(packet));
    packet.firstSample+=480;packet.samples[0]=std::numeric_limits<float>::quiet_NaN();assert(!valid(packet,sizeof(packet)));assert(send(fd,&packet,sizeof(packet),0)==sizeof(packet));
    usleep(10000);std::vector<int32_t> pcm;reader.read(999990,980,pcm);assert(pcm.size()==980*8);for(unsigned n=0;n<980;++n){bool present=n>=10&&n<490;if(pcm[n*8]!=(present?4194304:0)){fprintf(stderr,"Mismatch at %u: %d expected %d\n",n,pcm[n*8],present?4194304:0);abort();}assert(pcm[n*8+1]==(present?-2097152:0));for(unsigned c=2;c<8;++c)assert(pcm[n*8+c]==0);}close(fd);puts("PASS: timestamped stereo alignment, exact PCM24 levels, silent holes, isolated stereo channels, invalid and truncated packet rejection");}
