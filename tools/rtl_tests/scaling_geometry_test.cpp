#include "scaling_geometry.cc"
#include <iostream>
#include <algorithm>
using namespace cxxrtl_design;
int main(){p_scaling__geometry d;unsigned cases=0;
 auto tick=[&](){d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();};
 d.p_rst.set(true);tick();d.p_rst.set(false);
 for(unsigned h=1;h<=480;++h)for(unsigned w=1;w<=640;++w)for(unsigned m=0;m<4;++m){
  unsigned ow=w,oh=h,cx=0,cy=0,sx=4096,sy=4096,rx=0,ry=0,dx=1,dy=1;
  if(m==1){ow=std::min(640u,w*2);oh=std::min(480u,h*2);cx=w>320?(w-320)/2:0;cy=h>240?(h-240)/2:0;sx=sy=2048;}
  if(m==2){ow=(w+1)/2;oh=(h+1)/2;sx=sy=8192;}
  if(m==3){if(w*480>=h*640){ow=640;oh=std::max(1u,h*640/w);}else{oh=480;ow=std::max(1u,w*480/h);}
   dx=ow>1?ow-1:1;dy=oh>1?oh-1:1;sx=ow>1?(w-1)*4096/dx:0;sy=oh>1?(h-1)*4096/dy:0;rx=ow>1?(w-1)*4096%dx:0;ry=oh>1?(h-1)*4096%dy:0;}
  d.p_width.set(w);d.p_height.set(h);d.p_mode.set(m);d.p_start.set(true);tick();d.p_start.set(false);
  unsigned clocks=0;while(!d.p_ready.get<bool>()&&clocks++<150)tick();
  if(!d.p_ready.get<bool>()||d.p_out__w.get<unsigned>()!=ow||d.p_out__h.get<unsigned>()!=oh||d.p_crop__x.get<unsigned>()!=cx||d.p_crop__y.get<unsigned>()!=cy||
   d.p_step__x.get<unsigned>()!=sx||d.p_step__y.get<unsigned>()!=sy||d.p_rem__x.get<unsigned>()!=rx||d.p_rem__y.get<unsigned>()!=ry||d.p_den__x.get<unsigned>()!=dx||d.p_den__y.get<unsigned>()!=dy){std::cerr<<"Geometry mismatch "<<w<<"x"<<h<<" mode="<<m<<"\n";return 1;}
  ++cases;
 }
 std::cout<<"PASS geometry: "<<cases<<" configurations, every width 1..640 / height 1..480 in all four modes\n";
}
