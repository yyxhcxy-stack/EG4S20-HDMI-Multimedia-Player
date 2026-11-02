#include "lcd_snapshot.cc"
#include <iostream>
int main(){cxxrtl_design::p_lcd__snapshot d;auto tick=[&](){d.p_dstclk.set(false);d.step();d.p_dstclk.set(true);d.step();};
for(unsigned height=0;height<32;height++){d.p_map__height.set(height);d.step();unsigned expected=height<=26?(height*17+13)/26:17;if(d.p_mapped__height.get<unsigned>()!=expected){std::cerr<<"LCD height mapping mismatch "<<height<<"\n";return 1;}}
d.p_rst.set(true);tick();d.p_rst.set(false);unsigned samples=0,bytes=0,bits=0,shift=0;bool prevs=false;unsigned resets=0;bool lastreset=true;unsigned lowcount=0;
uint64_t frame_h=0,frame_p=0;bool frame_started=false;unsigned frame_checks=0;
for(unsigned n=0;n<36000000;n++){
 d.p_srcclk.set((n&1)!=0);d.p_send.set(n%32==1);d.p_data=cxxrtl::value<80>{n,n^0xabcdef01u,n&65535u};d.step();tick();
 if(d.p_received.get<bool>()){if((d.p_received__data.data[0]^d.p_received__data.data[1])!=0xabcdef01u||d.p_received__data.data[2]!=(d.p_received__data.data[0]&65535u)){std::cerr<<"CDC mixed bundle\n";return 1;}samples++;}
 if(d.p_lcd_2e_state.get<unsigned>()>=5 && d.p_lcd_2e_state.get<unsigned>()<=7){
 if(!frame_started){frame_h=d.p_lcd_2e_frame__spec.get<uint64_t>();frame_p=d.p_lcd_2e_frame__peak.get<uint64_t>();frame_started=true;}
 if(frame_h!=d.p_lcd_2e_frame__spec.get<uint64_t>()||frame_p!=d.p_lcd_2e_frame__peak.get<uint64_t>()){std::cerr<<"LCD mid-refresh snapshot mutation\n";return 1;}frame_checks++;
 }else frame_started=false;
 bool rs=d.p_lrst.get<bool>();if(!rs)lowcount++;if(rs&&!lastreset)resets++;lastreset=rs;
 bool s=d.p_scl.get<bool>();if(s&&!prevs&&!d.p_cs.get<bool>()){shift=(shift<<1)|unsigned(d.p_mosi.get<bool>());if(++bits==8){bytes++;bits=0;shift=0;}}prevs=s;
}
if(frame_checks<10000||samples<100||bytes<32822||lowcount<1000000||resets!=1||!d.p_blk.get<bool>()){std::cerr<<"LCD init/refresh missing bytes="<<bytes<<"\n";return 1;}
std::cout<<"PASS lcd_snapshot: "<<samples<<" coherent CDC snapshots, exhaustive 0..26 normalized heights/invalid clamping, LCD reset/init and "<<bytes<<" SPI bytes, full refresh with held height/peak snapshot\n";
}
