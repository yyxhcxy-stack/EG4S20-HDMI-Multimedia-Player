#ifdef WRITER256
#include "frame_writer256.cc"
#else
#include "frame_writer.cc"
#endif
#include <iostream>
using namespace cxxrtl_design;
int main(){
 unsigned checks=0,requests=0;
 // Reuse the controller to catch stale short-burst limits on a new frame.
 p_frame__fifo__write d;auto tick=[&](){d.p_mem__clk.set(false);d.step();d.p_mem__clk.set(true);d.step();};
 d.p_rst.set(true);tick();d.p_rst.set(false);d.p_Sdr__init__done.set(true);
 for(unsigned h:{1u,3u,5u,480u}) for(unsigned w:{1u,2u,127u,128u,129u,160u,333u,640u}) {
   d.p_img__width.set(w);d.p_img__height.set(h);d.p_write__len.set(w*h);
   d.p_write__addr__0.set(1000);d.p_rdusedw.set(0);d.p_write__req.set(true);d.p_App__rd__busy.set(false);
   for(int i=0;i<15&&!d.p_write__req__ack.get<bool>();++i)tick();if(!d.p_write__req__ack.get<bool>())return 1;
   d.p_write__req.set(false);unsigned n=0,produced=0;bool finished=false;
   for(unsigned i=0;i<1200000;++i){
     d.p_mem__clk.set(false);d.step();
     if(d.p_fifo__aclr.get<bool>())produced=0;
     else if(i%3==0 && produced<w*h && produced-n<512)++produced;
     d.p_rdusedw.set(produced-n);
     // Reader may stall admission but honors the writer's reservation.
     d.p_App__rd__busy.set(!d.p_O__wr__busy.get<bool>() && i%97<11);d.step();
     if(d.p_App__wr__en.get<bool>()) {
       unsigned address=d.p_App__wr__addr.get<unsigned>();
       unsigned expected=1000+(h-1-n/w)*w+n%w;
       if(n>=w*h||n>=produced||address!=expected){std::cerr<<"V-flip write mismatch/underflow width="<<w<<" n="<<n<<" produced="<<produced<<" address="<<address<<" expected="<<expected<<"\n";return 1;}
       ++n;++checks;
     }
     d.p_mem__clk.set(true);d.step();
     if(d.p_write__finish.get<bool>()){finished=true;break;}
   }
   if(!finished||n!=w*h){std::cerr<<"Write did not finish width="<<w<<" count="<<n<<" expected="<<w*h<<"\n";return 1;}
   ++requests;for(int i=0;i<5;++i)tick();
 }
 std::cout<<"PASS frame writer: "<<checks<<" addresses, "<<requests<<" consecutive requests, FIFO supply stalls, contention, partial bursts and no underflow\n";
}
