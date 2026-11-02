#include "frame_reader.cc"
#include <iostream>
using namespace cxxrtl_design;
int main(){
 unsigned checks=0,requests=0;
 for(bool stride:{false,true}) {
   p_frame__fifo__read d;auto tick=[&](){d.p_mem__clk.set(false);d.step();d.p_mem__clk.set(true);d.step();};
   d.p_rst.set(true);tick();d.p_rst.set(false);d.p_Sdr__init__done.set(true);
   for(unsigned h:{1u,3u,480u}) for(unsigned w:{1u,2u,127u,128u,129u,160u,333u,640u}){
   const unsigned length=w*(stride?(h+1)/2:h),expected_count=length;
   d.p_read__line__width.set(w);d.p_read__stride__2x.set(stride);d.p_read__len.set(length);
   d.p_read__addr__0.set(1000);d.p_wrusedw.set(0);d.p_read__req.set(true);
   for(int i=0;i<15;++i)tick();if(!d.p_read__req__ack.get<bool>())return 1;
   d.p_read__req.set(false);unsigned n=0;bool finished=false;
   for(int i=0;i<1200000;++i){
     d.p_mem__clk.set(false);d.step();
     if(d.p_App__rd__en.get<bool>()){
       unsigned address=d.p_App__rd__addr.get<unsigned>();
       unsigned expected=1000+(n/w)*w*(stride?2:1)+n%w;
       if(address!=expected){std::cerr<<"Stride address mismatch width="<<w<<" n="<<n<<" got="<<address<<" expected="<<expected<<"\n";return 1;}
       ++n;++checks;
     }
     d.p_mem__clk.set(true);d.step();if(d.p_read__finish.get<bool>()){finished=true;break;}
   }
   if(!finished||n!=expected_count){std::cerr<<"Frame read completion/count mismatch w="<<w<<" h="<<h<<" n="<<n<<" expected="<<expected_count<<"\n";return 1;}
   ++requests;for(int i=0;i<5;++i)tick();
   }
 }
 std::cout<<"PASS frame reader: "<<checks<<" SDRAM addresses, "<<requests<<" consecutive requests, full-height sequential/strided frames and exact burst counts\n";
}
