#include "../src/output/SharedOutput.hpp"
#include <cstdio>
int main(){printf("Header/ring size %zu; page %d\n",sizeof(shuttle_sink::Ring),getpagesize());}
