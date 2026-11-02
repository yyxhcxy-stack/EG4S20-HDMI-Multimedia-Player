#include "scaling_core.cc"
#include <iostream>
#include <vector>
#include <algorithm>
#include <fstream>

using namespace cxxrtl_design;
static unsigned fw,fh;
static unsigned pixel(unsigned x,unsigned y,unsigned pattern){
 if(pattern==1)return ((x^y)&1)?0xffffff:0;
 if(pattern==2){if(x==0&&y==0)return 0xff0000;if(x==fw-1&&y==0)return 0x00ff00;if(x==0&&y==fh-1)return 0x0000ff;if(x==fw-1&&y==fh-1)return 0xffff00;return x==0||y==0||x==fw-1||y==fh-1?0xffffff:0x123456;}
 return ((x*17+y*3)&255)<<16|((x*5+y*31)&255)<<8|((x*13+y*11)&255);
}
static unsigned blend(unsigned a,unsigned b,unsigned phase){return (a*(4096-phase)+b*phase+2048)>>12;}
static unsigned reference(unsigned w,unsigned h,unsigned mode,unsigned ow,unsigned oh,unsigned x,unsigned y,unsigned pattern){
 unsigned qx,qy;
 if(mode==3){qx=ow>1?uint64_t(x)*(w-1)*4096/(ow-1):0;qy=oh>1?uint64_t(y)*(h-1)*4096/(oh-1):0;}
 else if(mode==1){qx=((w>320?(w-320)/2:0)*4096)+x*2048;qy=((h>240?(h-240)/2:0)*4096)+y*2048;}
 else {qx=x*(mode==2?8192:4096);qy=y*(mode==2?8192:4096);}
 unsigned sx=qx/4096,sy=qy/4096,nx=std::min(sx+1,mode==1&&w>320?(w-320)/2+319:w-1),ny=std::min(sy+1,mode==1&&h>240?(h-240)/2+239:h-1);
 unsigned a=pixel(sx,sy,pattern),b=pixel(nx,sy,pattern),c=pixel(sx,ny,pattern),e=pixel(nx,ny,pattern),out=0;
 for(unsigned ch=0;ch<24;ch+=8){unsigned av=(a>>ch)&255,bv=(b>>ch)&255,cv=(c>>ch)&255,ev=(e>>ch)&255;
  unsigned v=mode==2?(av+bv+cv+ev+2)/4:blend(blend(av,bv,qx%4096),blend(cv,ev,qx%4096),qy%4096);out|=v<<ch;}
 return out;
}
int main(){
 p_scaling__core d;uint64_t checks=0;unsigned frames=0;
 auto tick=[&](){d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();};
 d.p_rst.set(true);tick();d.p_rst.set(false);
 const std::vector<std::pair<unsigned,unsigned>> sizes={{640,480},{320,240},{333,221},{160,120},{640,360},{240,320},{1,1},{1,479},{639,1},{2,3},{3,2},{639,479},{127,129}};
 for(unsigned pattern=0;pattern<3;++pattern)for(auto [w,h]:sizes)for(unsigned mode=0;mode<4;++mode){
  fw=w;fh=h;unsigned ow=w,oh=h;
  if(mode==1){ow=std::min(2*w,640u);oh=std::min(2*h,480u);}
  if(mode==2){ow=(w+1)/2;oh=(h+1)/2;}
  if(mode==3){if(w*480>=h*640){ow=640;oh=std::max(1u,h*640/w);}else{oh=480;ow=std::max(1u,w*480/h);}}
  std::ofstream preview;
  if(pattern==2 && w==333 && h==221){preview.open("output/scaling_preview/mode"+std::to_string(mode)+".ppm",std::ios::binary);preview<<"P6\n"<<ow<<" "<<oh<<"\n255\n";}
  d.p_mode.set(mode);d.p_width.set(w);d.p_height.set(h);d.p_start.set(true);tick();d.p_start.set(false);
  unsigned source=0,n=0;bool pending=false;unsigned pdata=0;bool finished=false;
  for(unsigned cycle=0;cycle<4000000;++cycle){
   bool empty=source==w*h||cycle%19==3||cycle%19==4;
   bool full=cycle%23==5||cycle%23==6;
   d.p_src__empty.set(empty);d.p_src__data.set(pending?pdata:0xdeadbe);d.p_out__full.set(full);
   d.p_clk.set(false);d.step();
   bool rd=d.p_src__read.get<bool>();
   if(rd&&empty){std::cerr<<"Empty read\n";return 1;}
   unsigned next=rd?pixel(source%w,source/w,pattern):0;
   if(d.p_out__write.get<bool>()){
    if(n>=ow*oh){std::cerr<<"Excess output\n";return 1;}
    unsigned expected=reference(w,h,mode,ow,oh,n%ow,n/ow,pattern),got=d.p_out__data.get<unsigned>();
    if(got!=expected){std::cerr<<"Pixel mismatch "<<w<<"x"<<h<<" mode="<<mode<<" pattern="<<pattern<<" x="<<n%ow<<" y="<<n/ow<<" got="<<std::hex<<got<<" expected="<<expected<<std::dec<<"\n";return 1;}
    if(preview.is_open()){char bytes[]={char(got>>16),char(got>>8),char(got)};preview.write(bytes,3);}
    ++n;++checks;
   }
   d.p_clk.set(true);d.step();pending=rd;pdata=next;if(rd)++source;
   if(d.p_config__ready.get<bool>()&&(d.p_out__w.get<unsigned>()!=ow||d.p_out__h.get<unsigned>()!=oh)){std::cerr<<"Geometry mismatch\n";return 1;}
   if(d.p_done.get<bool>()){finished=true;break;}
  }
  if(!finished||n!=ow*oh){std::cerr<<"Frame timeout/count "<<w<<"x"<<h<<" mode="<<mode<<" output="<<n<<" source="<<source<<"\n";return 1;}
  ++frames;
 }
 std::cout<<"PASS scaling core: "<<checks<<" reference pixels, "<<frames<<" consecutive mixed-size/mode frames, source stalls/output backpressure, first row and edges\n";
}
