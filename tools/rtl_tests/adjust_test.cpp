#include "adjust.cc"
#include <iostream>
#include <algorithm>
using namespace cxxrtl_design;
static unsigned ref(unsigned v,unsigned b,unsigned c){
 unsigned gains[]={256,320,192,384};int x=std::min(255u,v*gains[b]/256),y=x;
 switch(c){case 1:y=x+x/4-32;break;case 2:y=x+x/2-64;break;case 3:y=2*x-128;break;case 4:y=x/2+x/4+32;break;}
 return std::clamp(y,0,255);
}
int main(){p_video__adjust__lut d;unsigned n=0;
 for(unsigned b=0;b<4;++b)for(unsigned c=0;c<8;++c)for(unsigned x=0;x<256;++x){
  unsigned g=255-x,z=x^0x55;d.p_brightness.set(b);d.p_contrast.set(c);d.p_rgb__in.set(x<<16|g<<8|z);
  d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();d.step(); // settle ROM registers and the output mux in the same clock edge
  if(d.p_rgb__out.get<unsigned>()!=(ref(x,b,c)<<16|ref(g,b,c)<<8|ref(z,b,c))){std::cerr<<"Colour transfer mismatch b="<<b<<" c="<<c<<" x="<<x<<" got="<<d.p_rgb__out.get<unsigned>()<<" expected="<<(ref(x,b,c)<<16|ref(g,b,c)<<8|ref(z,b,c))<<"\n";return 1;}++n;
 }
 std::cout<<"PASS adjustment: "<<n<<" exhaustive controls/input cases, all RGB channels preserve original curves\n";
}
