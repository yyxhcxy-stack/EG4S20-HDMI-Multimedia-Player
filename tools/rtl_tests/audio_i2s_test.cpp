#include "audio_i2s.cc"
#include <deque>
#include <iostream>
#include <random>
int main(){unsigned checked=0;std::mt19937 gen(1067);
for(unsigned phase=0;phase<7;phase++){
 cxxrtl_design::p_audio__i2s d;std::deque<std::pair<unsigned,unsigned>> expected;
 bool tb=false,rb=false,prevb=false,prevws=true;unsigned tedge=0,lastedge=0,edges=0,slot=0,word=0,currentl=0,currentr=0,decoded=0;
 d.p_rst.set(true);d.p_left.set(0);d.p_right.set(0);d.step();
 for(unsigned t=0;t<2500000;t++){
  bool txevent=t%625==0,rxevent=(t+phase*11)%307==0; // asynchronous phase sweep, >2 receiver clocks per half-bit
  if(t==20000){d.p_rst.set(false);d.step();}
  if(txevent){tb=!tb;d.p_txclk.set(tb);if(tb){if(d.p_tick.get<bool>()){currentl=gen()&0xffffff;currentr=gen()&0xffffff;d.p_left.set(currentl);d.p_right.set(currentr);if(!d.p_rst.get<bool>())expected.push_back({currentl,currentr});}tedge++;}d.step();}
  if(rxevent){rb=!rb;d.p_rxclk.set(rb);d.step();if(rb&&d.p_valid.get<bool>()){
   auto got=std::make_pair(d.p_rxleft.get<unsigned>(),d.p_rxright.get<unsigned>());
   if(decoded==0 && !expected.empty() && expected.front()!=got)expected.pop_front();
   decoded++;
   if(expected.empty() || expected.front()!=got){std::cerr<<"I2S PCM mismatch phase="<<phase<<"\n";return 1;}expected.pop_front();checked++;
  }}
  bool b=d.p_bclk.get<bool>();if(b&&!prevb&&!d.p_rst.get<bool>()){
   if(edges++&&tedge-lastedge!=4){std::cerr<<"BCLK period\n";return 1;}lastedge=tedge;
   bool ws=d.p_lrck.get<bool>();if(ws!=prevws){slot=0;word=0;prevws=ws;}else{if(slot<24)word=(word<<1)|unsigned(d.p_dout.get<bool>());slot++;}
  }prevb=b;
 }
}
// Independent bit-level sender: explicit one-bit WS delay, malformed slots and mid-frame reset.
{
 cxxrtl_design::p_audio__i2s d;d.p_manual.set(true);std::deque<std::pair<unsigned,unsigned>> q;unsigned pairs=0;
 auto clocks=[&](unsigned n){while(n--){d.p_rxclk.set(false);d.step();d.p_rxclk.set(true);d.step();if(d.p_valid.get<bool>()){auto v=std::make_pair(d.p_rxleft.get<unsigned>(),d.p_rxright.get<unsigned>());if(q.empty()||q.front()!=v){std::cerr<<"I2S malformed/reset pair\n";exit(1);}q.pop_front();pairs++;}}};
 auto bit=[&](bool w,bool data){d.p_mb.set(false);d.p_mw.set(w);d.p_md.set(data);clocks(7);d.p_mb.set(true);clocks(7);};
 auto slot=[&](bool w,unsigned pcm,unsigned length){bit(w,false);for(unsigned i=1;i<length;i++)bit(w,i<=24?((pcm>>(24-i))&1):false);};
 d.p_rst.set(true);clocks(5);d.p_rst.set(false);slot(true,0,32);slot(false,0x800001,32);slot(true,0x7fffff,32);q.push_back({0x800001,0x7fffff});
 slot(false,0,32);slot(true,0,32);q.push_back({0,0});
 slot(false,0xffffff,27);slot(true,0x112233,32); // malformed left, discard right pair
 slot(false,0x123456,32);slot(true,0x654321,19); // malformed right
 slot(false,0xabcdef,10);d.p_rxreset.set(true);clocks(5);if(d.p_valid.get<bool>()||d.p_rxleft.get<unsigned>()||d.p_rxright.get<unsigned>())return 1;d.p_rxreset.set(false);
 for(unsigned i=0;i<22;i++)bit(false,false);slot(true,0x777777,32); // incomplete after reset cannot pair
 slot(false,0xa5a5a5,32);slot(true,0x5a5a5a,32);q.push_back({0xa5a5a5,0x5a5a5a});slot(false,0,1);
 if(!q.empty()||pairs!=3){std::cerr<<"I2S exact valid count "<<pairs<<"\n";return 1;}
}
if(checked<30){std::cerr<<"Only "<<checked<<" pairs\n";return 1;}std::cout<<"PASS audio_i2s: "<<checked<<" random stereo pairs, 7 asynchronous phases, 64fs clocks, independent framing/zero/full-scale, malformed slots and half-frame reset\n";
}
