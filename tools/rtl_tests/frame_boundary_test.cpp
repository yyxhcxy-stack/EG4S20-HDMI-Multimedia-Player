#include "frame_boundary.cc"
#include <iostream>
#include <algorithm>
using namespace cxxrtl_design;
int main(){
 p_frame__boundary d;unsigned requests=0,verified=0,next_check=0,cw=0,ch=0,cm=0;bool prev=false;
 auto set_requested=[&](unsigned n){unsigned w=n/4==0?333:n/4==1?240:1,h=n/4==0?221:n/4==1?320:1;d.p_requested__width.set(w);d.p_requested__height.set(h);d.p_requested__mode.set(n%4);d.p_requested__base.set(n%2?307200:0);};
 auto tick=[&](bool edge){d.p_mem__clk.set(false);d.p_video__clk.set(false);d.step();d.p_mem__clk.set(true);d.p_video__clk.set(edge);d.step();d.step();};
 d.p_rst.set(true);for(int i=0;i<10;++i)tick(i%5==4);d.p_rst.set(false);set_requested(0);
 for(unsigned vc=0;vc<13*800*525;++vc){
  for(int i=0;i<5;++i){tick(i==4);bool req=d.p_read__req.get<bool>();
   if(req&&!prev){if(requests>=12)return 3;cw=requests/4==0?333:requests/4==1?240:1;ch=requests/4==0?221:requests/4==1?320:1;cm=requests%4;
    unsigned len=cw*(cm==1&&ch>240?(ch-240)/2+240:ch);
    if(d.p_read__len.get<unsigned>()!=len||d.p_read__base.get<unsigned>()!=(requests%2?307200:0)){std::cerr<<"Frame descriptor mismatch request="<<requests<<" length="<<d.p_read__len.get<unsigned>()<<" expected="<<len<<"\n";return 1;}
    next_check=vc+100;++requests;if(requests<12)set_requested(requests);
   }prev=req;
  }
  if(next_check&&vc==next_check){unsigned ow=cw,oh=ch;
   if(cm==1){ow=std::min(640u,cw*2);oh=std::min(480u,ch*2);}if(cm==2){ow=(cw+1)/2;oh=(ch+1)/2;}
   if(cm==3){if(cw*480>=ch*640){ow=640;oh=std::max(1u,ch*640/cw);}else{oh=480;ow=std::max(1u,cw*480/ch);}}
   if(d.p_display__w.get<unsigned>()!=ow||d.p_display__h.get<unsigned>()!=oh){std::cerr<<"Frame window mismatch\n";return 2;}
   next_check=0;if(++verified==12){std::cout<<"PASS frame boundary: 12 real 640x480 timing requests, mixed sizes/modes, current-frame descriptor and window alignment\n";return 0;}
  }
 }
 std::cerr<<"Frame timing timeout\n";return 4;
}
