#include "transition.cc"
#include <iostream>
#include <cmath>
#include <stdexcept>
using namespace cxxrtl_design;
int main() {
    p_video__transition d;
    auto tick = [&]() { d.p_clk.set(false); d.step(); d.p_clk.set(true); d.step(); };
    d.p_rst.set(true); tick(); d.p_rst.set(false);
    unsigned checks = 0;
    for (unsigned mode=0; mode<3; ++mode)
      for (unsigned opening=0; opening<2; ++opening)
        for (unsigned step=0; step<16; ++step) {
            d.p_de.set(false); tick();
            d.p_active.set(true); d.p_mode.set(mode);
            d.p_opening.set(opening); d.p_step.set(step);
            for (unsigned x=0; x<640; ++x) {
                unsigned rgb = ((x%256)<<16) | ((255-x%256)<<8) | 127;
                d.p_rgb__in.set(rgb); d.p_de.set(true); d.p_clk.set(false); d.step();
                double t=double(step)/15.0;
                unsigned progress=std::lround(256*(3*t*t-2*t*t*t));
                unsigned gain = opening ? progress : 256-progress;
                unsigned expected=0;
                if (mode==0) {
                    for (unsigned shift: {0u,8u,16u})
                        expected |= (((((rgb>>shift)&255)*gain+128)>>8)&255)<<shift;
                } else if (mode==1) {
                    unsigned slit = std::lround(32.0*gain/256.0);
                    expected = x%32 < slit ? rgb : 0;
                } else {
                    unsigned edge=std::lround(640.0*progress/256.0);
                    if (step==0) expected=opening ? 0 : rgb;
                    else if (step==15) expected=opening ? rgb : 0;
                    else if (x==edge-1 || x==edge-2) expected=0xFFFFFF;
                    else if (x==edge-3 || x==edge) expected=0x00FFFF;
                    else expected=(opening ? x<edge : x>=edge) ? rgb : 0;
                }
                unsigned got=d.p_rgb__out.get<unsigned>();
                if (got!=expected) {
                    std::cerr<<"Transition mismatch mode="<<mode<<" opening="<<opening<<" step="<<step<<" x="<<x<<" got="<<got<<" expected="<<expected<<"\n";
                    return 1;
                }
                ++checks; d.p_clk.set(true); d.step();
            }
        }
    d.p_active.set(false); d.p_rgb__in.set(0xFEDCBA); d.step();
    if (d.p_rgb__out.get<unsigned>()!=0xFEDCBA) return 1;
    std::cout<<"PASS transition: "<<checks<<" output pixels, all modes/steps/endpoints and bypass, independent floating smoothstep reference\n";
}
