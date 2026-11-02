#include "seg_digits.cc"
#include <iostream>
using namespace cxxrtl_design;
int main(){p_seg__digits d;for(unsigned amp=0;amp<128;++amp){d.p_vu__amp.set(amp);d.step();unsigned t=amp>=90?9:amp/10,o=(amp-t*10)&15;if(d.p_vu__tens.get<unsigned>()!=t||d.p_vu__ones.get<unsigned>()!=o){std::cerr<<"Segment digits mismatch amplitude="<<amp<<"\n";return 1;}}std::cout<<"PASS segment digits: all 128 VU amplitude codes match original saturated tens and wrapped ones\n";}
