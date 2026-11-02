#include "audio_baseline.cc"
#include <iostream>
int main(){cxxrtl_design::p_audio__baseline d;auto tick=[&](){d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();};
d.p_rst.set(true);tick();d.p_rst.set(false);int last=-1;bool previous=false;
for(int n=0;n<1000;n++){tick();bool b=d.p_bclk.get<bool>();if(b&&!previous){if(last>=0&&n-last!=4){std::cout<<"FAIL baseline 64fs: BCLK period="<<n-last<<" MCLK ticks; expected 4\n";return 1;}last=n;}previous=b;}
std::cout<<"PASS 64fs BCLK\n";}
