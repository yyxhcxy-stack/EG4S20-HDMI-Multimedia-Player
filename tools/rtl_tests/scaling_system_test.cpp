#include "scaling_system.cc"
#include <deque>
#include <iostream>
#include <algorithm>
using namespace cxxrtl_design;
static unsigned source(unsigned x,unsigned y){return ((x*17+y*3)&255)<<16|((x*5+y*31)&255)<<8|((x*13+y*11)&255);}
static unsigned blend(unsigned a,unsigned b,unsigned f){return (a*(4096-f)+b*f+2048)>>12;}
static unsigned ref(unsigned w,unsigned h,unsigned m,unsigned ow,unsigned oh,unsigned x,unsigned y){
 unsigned qx=m==3?(ow>1?uint64_t(x)*(w-1)*4096/(ow-1):0):m==1?((w>320?(w-320)/2:0)*4096+x*2048):x*(m==2?8192:4096);
 unsigned qy=m==3?(oh>1?uint64_t(y)*(h-1)*4096/(oh-1):0):m==1?((h>240?(h-240)/2:0)*4096+y*2048):y*(m==2?8192:4096);
 unsigned sx=qx>>12,sy=qy>>12,nx=std::min(sx+1,m==1&&w>320?(w-320)/2+319:w-1),ny=std::min(sy+1,m==1&&h>240?(h-240)/2+239:h-1);
 unsigned a=source(sx,sy),b=source(nx,sy),c=source(sx,ny),d=source(nx,ny),p=0;
 for(unsigned k=0;k<24;k+=8){unsigned av=(a>>k)&255,bv=(b>>k)&255,cv=(c>>k)&255,dv=(d>>k)&255;
 p|=(m==2?(av+bv+cv+dv+2)/4:blend(blend(av,bv,qx&4095),blend(cv,dv,qx&4095),qy&4095))<<k;}return p;
}
struct Expected{bool hs,vs,de;unsigned rgb;};
int main(){
 p_scaling__system d;unsigned checks=0,frames=0;uint64_t mt=0;
 unsigned source_w=640,issued=0;bool clear_prev=false;
 struct Read{bool valid;unsigned address;};std::deque<Read> returns(10,{false,0});
 auto memory_tick=[&](bool video_edge){
  d.p_mem__clk.set(false);d.p_video__clk.set(false);d.step();
  bool clear=d.p_fifo__clear.get<bool>();
  if(clear&&!clear_prev){issued=0;returns.assign(10,{false,0});}
  clear_prev=clear;
  auto returning=returns.front();returns.pop_front();
  unsigned offset=returning.address-d.p_read__base.get<unsigned>();
  d.p_data__valid.set(returning.valid&&!clear);d.p_memory__data.set(source(offset%source_w,offset/source_w));
  d.p_wr__busy.set(mt%503<75);d.step();
  bool request=d.p_app__read.get<bool>();unsigned addr=d.p_app__address.get<unsigned>();
  if(request){if(addr!=d.p_read__base.get<unsigned>()+issued){std::cerr<<"SDRAM address mismatch\n";exit(1);}++issued;}
  returns.push_back({request,addr});
  d.p_mem__clk.set(true);d.p_video__clk.set(video_edge);d.step();d.step();++mt;
 };
 d.p_rst.set(true);for(int i=0;i<10;++i)memory_tick(i%5==4);d.p_rst.set(false);
 for(auto size:{std::pair<unsigned,unsigned>{640,480},{320,240},{333,221},{160,120},{640,360},{240,320},{1,1},{1,479},{639,1}})for(unsigned m=0;m<4;++m){
  unsigned w=size.first,h=size.second,ow=w,oh=h;source_w=w;
  if(m==1){ow=std::min(2*w,640u);oh=std::min(2*h,480u);}if(m==2){ow=(w+1)/2;oh=(h+1)/2;}
  if(m==3){if(w*480>=h*640){ow=640;oh=std::max(1u,h*640/w);}else{oh=480;ow=std::max(1u,w*480/h);}}
  unsigned left=(640-ow)/2,top=(480-oh)/2;
  d.p_width.set(w);d.p_height.set(h);d.p_mode.set(m);d.p_frame__base.set(frames%2?307200:0);d.p_display__valid.set(true);
  std::deque<Expected> q(2,{false,false,false,0});
  const unsigned blank=35*800;
  for(unsigned vc=0;vc<blank+480*800+10;++vc){
   bool vs=vc<10;int x=int(vc-blank)%800,y=int(vc-blank)/800;bool active=vc>=blank&&vc<blank+480*800;bool de=active&&x<640,hs=active&&x>=656&&x<752;
   d.p_vs.set(vs);d.p_hs.set(hs);d.p_de.set(de);
   if(vc==100000){d.p_width.set(1);d.p_height.set(1);d.p_mode.set((m+1)%4);d.p_frame__base.set(999);}
   if(vc==10)d.p_frame__req.set(true);else if(d.p_frame__ack.get<bool>())d.p_frame__req.set(false);
   unsigned expected=0x141c28;
   if(de&&unsigned(x)>=left&&unsigned(x)<left+ow&&unsigned(y)>=top&&unsigned(y)<top+oh)expected=ref(w,h,m,ow,oh,x-left,y-top);
   q.push_back({hs,vs,de,expected});auto e=q.front();q.pop_front();
   for(int j=0;j<5;++j)memory_tick(j==4);
   if(vc>3&&(d.p_hs__out.get<bool>()!=e.hs||d.p_vs__out.get<bool>()!=e.vs||d.p_de__out.get<bool>()!=e.de||(e.de&&d.p_rgb__out.get<unsigned>()!=e.rgb))){
    std::cerr<<"Pipeline mismatch "<<w<<"x"<<h<<" mode="<<m<<" video="<<vc<<" got="<<std::hex<<d.p_rgb__out.get<unsigned>()<<" expected="<<e.rgb<<std::dec<<" hs="<<d.p_hs__out.get<bool>()<<"/"<<e.hs<<" vs="<<d.p_vs__out.get<bool>()<<"/"<<e.vs<<" de="<<d.p_de__out.get<bool>()<<"/"<<e.de<<" underflow="<<d.p_underflow.get<bool>()<<"\n";return 1;}
   if(e.de)++checks;
  }
  if(d.p_underflow.get<bool>()||d.p_source__underflow.get<bool>()||issued!=d.p_read__len.get<unsigned>()){std::cerr<<"Pipeline underrun/source count "<<issued<<" expected="<<w*h<<"\n";return 1;}
  ++frames;
 }
 std::cout<<"PASS scaling system: "<<checks<<" HDMI pixels, "<<frames<<" consecutive frames, 125/25 MHz CDC/FIFO, alignment, real frame reader, 256-word bursts, SDRAM latency, write contention and exact addresses\n";
}
