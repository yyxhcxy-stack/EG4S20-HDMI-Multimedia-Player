#include "enable_equivalence.cc"
#include <iostream>
#include <stdexcept>
using namespace cxxrtl_design;
int main(){p_enable__equivalence d;unsigned cycles=0,results=0,seed=2612;
auto tick=[&](){d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();d.step();if(d.p_mismatch.get<bool>())throw std::runtime_error("DFT enable changed output/cycle");if(d.p_done.get<bool>())++results;++cycles;};
d.p_rst.set(true);d.p_valid.set(false);tick();d.p_rst.set(false);
for(unsigned n=0;n<65536;++n){seed=seed*1664525u+1013904223u;d.p_sample.set(n<256?0:n<512?32767:n<768?32768:seed>>16);d.p_valid.set(true);tick();d.p_valid.set(false);for(unsigned c=0;c<1040;++c)tick();if(d.p_overrun.get<bool>())throw std::runtime_error("Normal-rate overrun");}
if(results!=256)throw std::runtime_error("DFT window count changed");
// Pause, mid-window reset and deliberately overlapping samples.
for(unsigned n=0;n<37;++n){d.p_valid.set(true);tick();d.p_valid.set(false);for(int c=0;c<1040;++c)tick();}for(int c=0;c<5000;++c)tick();
for(unsigned n=0;n<1200;++n){d.p_rst.set(n%211==0);d.p_valid.set(n%17==0);d.p_sample.set(n*97);tick();}
std::cout<<"PASS enable equivalence: "<<cycles<<" clocks, 65536 samples, 256 windows, exact amplitudes/complex outputs/valid/overrun vs baseline, zero/full-scale/random, pause/reset/overrun recovery\n";
}
