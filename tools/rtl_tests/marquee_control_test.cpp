#ifdef UART_BRAM_MODEL
#include "marquee_control_vendor.cc"
#else
#include "marquee_control.cc"
#endif
#include <iostream>
#include <string>
#include <vector>
#include <cstdlib>
using namespace cxxrtl_design;
int main(){
 p_uart__scada__controller d;std::string received;uint64_t clocks=0;bool frames=true;unsigned frame_phase=1;
 int phase=0,wait=0,bit=0;unsigned byte=0;bool previous=true;
 auto fail=[&](const std::string&s){std::cerr<<s<<"\n";exit(1);};
 auto tick=[&](){
  bool video=(clocks%2)==frame_phase;
  d.p_marq__frame__pulse.set(frames&&clocks%10000>=9996);
  d.p_clk.set(false);d.p_video__clk.set(video);d.step();d.step();
  d.p_clk.set(true);d.step();d.step();clocks++;
  bool tx=d.p_uart__tx.get<bool>();
  if(!phase){if(previous&&!tx){phase=1;wait=651;bit=0;byte=0;}}
  else if(--wait==0){if(phase==1){byte|=unsigned(tx)<<bit;if(++bit==8){phase=2;wait=434;}else wait=434;}
   else{if(!tx)fail("TX stop bit");received.push_back(char(byte));phase=0;}}
  previous=tx;
 };
 auto hold=[&](bool v,unsigned n){d.p_uart__rx.set(v);while(n--)tick();};
 auto send=[&](std::string s){for(unsigned char c:s){hold(false,434);for(int i=0;i<8;i++)hold((c>>i)&1,434);hold(true,434);}hold(true,100);};
 auto drain=[&](){hold(true,220000);};
 auto expect=[&](std::string s){drain();if(received!=s)fail("ACK mismatch got="+received+" expected="+s);received.clear();};
 auto content=[&](std::string s){for(unsigned i=0;i<128;i++){d.p_marq__read__addr.set(i);hold(true,6);unsigned c=d.p_marq__read__data.get<unsigned>();unsigned want=i<s.size()?unsigned(s[i]):32;if(c!=want)fail("Text byte mismatch "+std::to_string(i));}};
 d.p_rst.set(true);hold(true,20);d.p_rst.set(false);hold(true,50);
 if(d.p_marq__custom__valid.get<bool>()||d.p_marq__hidden.get<bool>())fail("Reset defaults");
 std::vector<std::string> old={"CMD:EMERG=0","CMD:EMERG=1","CMD:NEXT","CMD:AUTO=0","CMD:AUTO=1"};
 for(int i=0;i<4;i++){old.push_back("CMD:SCALE="+std::to_string(i));old.push_back("CMD:TRANS="+std::to_string(i));}
 for(int i=0;i<5;i++)old.push_back("CMD:VOL="+std::to_string(i));for(int i=0;i<3;i++)old.push_back("CMD:ALPHA="+std::to_string(i));
 for(auto s:old){send(s+"\r\n");expect("[ACK] OK: "+s+"\r\n");}
 send("cmd:text=a\r");expect("[ACK] OK: CMD:TEXT\r\n");content("A");
 std::string longtext;for(unsigned i=0;i<128;i++)longtext+=char(32+i%64);
 send("CMD:TEXT="+longtext+"\n");expect("[ACK] OK: CMD:TEXT\r\n");content(longtext);
 send("CMD:TEXT=  hello!  \r\n");expect("[ACK] OK: CMD:TEXT\r\n");content("  HELLO!  ");
 for(std::string bad: {std::string(),std::string(129,'B'),std::string("`{|}~"),std::string("\xE4\xB8\xAD"),std::string("A\tB"),std::string("A\x7F"),std::string("A\0B",3)}){
  send("CMD:TEXT="+bad+"\n");expect("[ACK] ERR: CMD:TEXT\r\n");content("  HELLO!  ");
 }
 send("CMD:MARQ=0\n");expect("[ACK] OK: CMD:MARQ=0\r\n");if(!d.p_marq__hidden.get<bool>())fail("Hide");
 send("CMD:TEXT=OFF UPDATE\n");expect("[ACK] OK: CMD:TEXT\r\n");content("OFF UPDATE");if(!d.p_marq__hidden.get<bool>())fail("Text auto-enabled");
 send("CMD:MARQ=1\r\n");expect("[ACK] OK: CMD:MARQ=1\r\n");if(d.p_marq__hidden.get<bool>())fail("Show");
 frames=false;send("CMD:TEXT=FIRST\n");hold(true,300);if(!received.empty())fail("ACK before frame");content("OFF UPDATE");
 send("CMD:TEXT=SECOND\n");expect("[ACK] ERR: CMD:TEXT\r\n");content("OFF UPDATE");
 send("CMD:MARQ=0\n");expect("[ACK] ERR: CMD:MARQ=0\r\n");frames=true;expect("[ACK] OK: CMD:TEXT\r\n");content("FIRST");
 d.p_emergency__mode.set(true);send("CMD:TEXT=EMERGENCY UPDATE\n");expect("[ACK] OK: CMD:TEXT\r\n");content("EMERGENCY UPDATE");d.p_emergency__mode.set(false);
 // Abort partial receive and pending frame transaction independently.
 frames=false;send("CMD:TEXT=INCOMPLETE");d.p_rst.set(true);hold(true,20);d.p_rst.set(false);hold(true,50);
 if(d.p_marq__custom__valid.get<bool>()||d.p_marq__hidden.get<bool>())fail("Partial reset");
 frames=true;send("CMD:TEXT=AFTER RESET\n");expect("[ACK] OK: CMD:TEXT\r\n");content("AFTER RESET");
 frames=false;send("CMD:TEXT=RESET PENDING\n");hold(true,300);if(!received.empty())fail("Pending reset early ACK");
 d.p_rst.set(true);hold(true,20);d.p_rst.set(false);hold(true,50);frames=true;hold(true,220000);
 if(d.p_marq__custom__valid.get<bool>()||d.p_marq__hidden.get<bool>()||!received.empty())fail("Pending reset leaked transaction");
 send("CMD:TEXT=RECOVERED\n");expect("[ACK] OK: CMD:TEXT\r\n");content("RECOVERED");
 for(unsigned ph=0;ph<2;ph++){frame_phase=ph;send("CMD:TEXT=PHASE\n");expect("[ACK] OK: CMD:TEXT\r\n");content("PHASE");}
 std::string echo31="CMD:"+std::string(27,'~');send(echo31+"\n");expect("[ACK] ERR: "+echo31+"\r\n");
 send(echo31+"X\n");expect("[ACK] ERR: "+echo31+"\r\n");
 // Exercise actual clocks through two 1Hz boundaries in normal/emergency.
 for(bool emergency:{false,true}){
  d.p_emergency__mode.set(emergency);hold(true,55000000);
  if(!received.empty()||!d.p_uart__tx.get<bool>())fail("Unsolicited UART telemetry");
  send("CMD:MARQ=0\n");expect("[ACK] OK: CMD:MARQ=0\r\n");
  send("CMD:TEXT=QUIET UART\n");expect("[ACK] OK: CMD:TEXT\r\n");content("QUIET UART");
 }
 std::cout<<"PASS marquee_control: real UART RX/TX, all 21 legacy values, 1/128/129 bytes, ASCII/invalid/whitespace, CR/LF/CRLF, frame ACK, busy protection, both CDC phases, partial/pending reset, 2.2 seconds normal/emergency silence and ACK/text recovery\n";
}
