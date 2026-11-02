#include "uart.cc"
#include <iostream>
#include <string>
using namespace cxxrtl_design;
int main(){
 p_uart__scada__controller d;std::string received;
 int phase=0,wait=0,bit=0;unsigned byte=0,next_count=0,scale_count=0,volume_count=0;bool previous=true;
 auto tick=[&](){
   d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();d.step();
   bool tx=d.p_uart__tx.get<bool>();
   if(!phase){if(previous&&!tx){phase=1;wait=651;bit=0;byte=0;}}
   else if(--wait==0){
     if(phase==1){byte|=unsigned(tx)<<bit;if(++bit==8){phase=2;wait=434;}else wait=434;}
     else {if(!tx){std::cerr<<"UART stop bit error\n";exit(1);}received.push_back(char(byte));phase=0;}
   }
   previous=tx;
   if(d.p_cmd__next__pulse.get<bool>())++next_count;
   if(d.p_cmd__scale__vld.get<bool>())++scale_count;
   if(d.p_cmd__vol__vld.get<bool>())++volume_count;
 };
 auto hold=[&](bool level,int cycles){d.p_uart__rx.set(level);for(int n=0;n<cycles;++n)tick();};
 auto send=[&](const std::string&s){for(unsigned char c:s){hold(false,434);for(int i=0;i<8;++i)hold((c>>i)&1,434);hold(true,434);}hold(true,180000);};
 d.p_rst.set(true);hold(true,10);d.p_rst.set(false);hold(true,1000);
 std::string expected;
 // More than 256 total bytes exercises the FIFO pointers across wraparound.
 for(int n=0;n<16;++n){send("CMD:NEXT\n");expected+="[ACK] OK: CMD:NEXT\r\n";}
 send("CMD:SCALE=2\n");expected+="[ACK] OK: CMD:SCALE=2\r\n";
 send("CMD:VOL=4\n");expected+="[ACK] OK: CMD:VOL=4\r\n";
 send("CMD:BAD\n");expected+="[ACK] ERR: CMD:BAD\r\n";
 if(received!=expected){std::cerr<<"UART ACK mismatch\nReceived: "<<received<<"Expected: "<<expected;return 1;}
 if(next_count!=16||scale_count!=1||volume_count!=1){std::cerr<<"Command pulse mismatch\n";return 1;}
 std::cout<<"PASS UART: "<<received.size()<<" decoded ACK bytes, FIFO wraparound, valid controls and invalid command response\n";
}
