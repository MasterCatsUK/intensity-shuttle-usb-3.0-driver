// GPL-2.0-or-later. Keep offline tests away from the user's active USB sender.
// Include before SharedOutput.hpp, then undefine htons after that include.
#pragma once
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <cassert>
static uint16_t loopbackTestPort;
static uint16_t LoopbackTestHTons(uint16_t value){return htons(value==47539?loopbackTestPort:value);}
static void ChooseLoopbackTestPort(){
    int fd=socket(AF_INET,SOCK_STREAM,0);assert(fd>=0);
    sockaddr_in address{};address.sin_family=AF_INET;address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    assert(bind(fd,reinterpret_cast<sockaddr*>(&address),sizeof(address))==0);
    socklen_t bytes=sizeof(address);assert(getsockname(fd,reinterpret_cast<sockaddr*>(&address),&bytes)==0);
    loopbackTestPort=ntohs(address.sin_port);close(fd);
}
#undef htons
#define htons LoopbackTestHTons
