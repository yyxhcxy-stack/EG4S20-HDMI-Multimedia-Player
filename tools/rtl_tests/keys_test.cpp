#include "keys.cc"
#include "key3_reference.cc"
#include <iostream>
using namespace cxxrtl_design;
int main(){
 p_key3__current d;p_key3__reference old;unsigned long long clocks=0;
 auto tick=[&](){
  old.p_rst__all.set(d.p_rst__all.get<bool>());old.p_key3__gated.set(d.p_key3__gated.get<bool>());
  old.p_cmd__scale__vld.set(d.p_cmd__scale__vld.get<bool>());old.p_cmd__vol__vld.set(d.p_cmd__vol__vld.get<bool>());old.p_cmd__alpha__vld.set(d.p_cmd__alpha__vld.get<bool>());
  old.p_cmd__scale__val.set(d.p_cmd__scale__val.get<unsigned>());old.p_cmd__vol__val.set(d.p_cmd__vol__val.get<unsigned>());old.p_cmd__alpha__val.set(d.p_cmd__alpha__val.get<unsigned>());
  d.p_clk.set(false);old.p_clk.set(false);d.step();old.step();d.p_clk.set(true);old.p_clk.set(true);d.step();old.step();d.step();old.step();++clocks;
  if(d.p_key3__state.get<unsigned>()!=old.p_key3__state.get<unsigned>()||d.p_key3__timer.get<unsigned>()!=old.p_key3__timer.get<unsigned>()||d.p_scale__mode.get<unsigned>()!=old.p_scale__mode.get<unsigned>()||d.p_vol__mode.get<unsigned>()!=old.p_vol__mode.get<unsigned>()||d.p_alpha__mode.get<unsigned>()!=old.p_alpha__mode.get<unsigned>()||d.p_hud__en.get<bool>()!=old.p_hud__en.get<bool>()){std::cerr<<"KEY3 golden mismatch clock="<<clocks<<"\n";exit(1);}
 };
 d.p_key3__gated.set(true);d.p_rst__all.set(true);tick();d.p_rst__all.set(false);if(d.p_hud__en.get<bool>())return 6;
 auto run=[&](bool released,unsigned n){d.p_key3__gated.set(released);while(n--)tick();};
 for(unsigned m=0;m<4;++m){run(false,1000010);run(true,18500030);if(d.p_scale__mode.get<unsigned>()!=m)return 2;}
 run(false,1000010);run(true,1000010);run(false,1000010);run(true,18500030);if(d.p_vol__mode.get<unsigned>()!=1)return 3;
 for(unsigned i=0;i<3;++i){run(false,1000010);run(true,1000010);}run(true,1500020);if(d.p_alpha__mode.get<unsigned>()!=2)return 4;
 run(false,50000010);run(true,1500010);if(!d.p_hud__en.get<bool>())return 5;
 for(unsigned i=0;i<20;++i){run(false,500);run(true,500);}
 unsigned seed=1;for(unsigned i=0;i<50000;++i){seed=seed*1664525u+1013904223u;d.p_key3__gated.set(seed&1);d.p_cmd__scale__vld.set(i%1009==0);d.p_cmd__vol__vld.set(i%1013==0);d.p_cmd__alpha__vld.set(i%1019==0);d.p_cmd__scale__val.set((seed>>2)&3);d.p_cmd__vol__val.set((seed>>5)%5);d.p_cmd__alpha__val.set((seed>>8)%3);tick();}
 std::cout<<"PASS KEY3: "<<clocks<<" clocks, exact single/double/triple/long timing, mode cycling, bounce and UART overrides match previous RTL\n";
}
