#include "audio_system.cc"
#include <deque>
#include <iostream>
#include <cmath>
#include <array>
int main(int argc,char**){bool actual_pll=argc>1;cxxrtl_design::p_audio__system d;bool mc=false,vc=false,fc=false;uint64_t mi=0,vi=0,fi=0;unsigned sent=0,received=0,outputs=0,blocks=0,acrs=0;std::deque<std::pair<unsigned,unsigned>> q;
int coeff[256],ks[]={1,2,3,4,5,6,7,8,10,12,16,20,24,32,40,53};for(int i=0;i<256;i++)coeff[i]=int(std::floor(32767*std::cos(2*std::acos(-1)*i/256)+.5));int64_t re[16]={},im[16]={};unsigned pos=0;std::deque<std::array<unsigned,16>> gold;
d.p_rst.set(true);d.p_enable.set(true);d.step();
while(true){uint64_t tm=actual_pll ? mi*61 : mi*625,tv=actual_pll ? vi*30 : vi*1536/5,tf=actual_pll ? fi*15 : fi*768/5,t=std::min(tm,std::min(tv,tf));if(t>=(actual_pll?1500000000ull:15360000000ull))break;uint64_t ts=actual_pll?t*256/25:t;
 if(ts>20000)d.p_rst.set(false);
 d.p_note.set(ts/1536000000ull%5);d.p_vol.set(ts/1024000000ull%5);d.p_emergency.set(ts>=7680000000ull&&ts<9216000000ull);
 if(tm==t){mc=!mc;if(mc&&!d.p_rst.get<bool>()&&d.p_tx__tick.get<bool>()){q.push_back({d.p_synth__l.get<unsigned>(),d.p_synth__r.get<unsigned>()});sent++;}d.p_mclk.set(mc);mi++;d.step();}
 if(tf==t){fc=!fc;d.p_clk50.set(fc);fi++;d.step();}
 if(tv==t){vc=!vc;
  if(vc&&!d.p_rst.get<bool>()&&d.p_raw__valid.get<bool>()){
   auto p=std::make_pair(d.p_raw__l.get<unsigned>(),d.p_raw__r.get<unsigned>());if(!received&&!q.empty()&&q.front()!=p)q.pop_front();
   if(q.empty()||q.front()!=p){std::cerr<<"Integrated I2S pair mismatch sample="<<received<<"\n";return 1;}q.pop_front();received++;
  }
  if(vc&&d.p_out__valid.get<bool>()){
   int x=int32_t(d.p_out__l.get<unsigned>()<<8)>>16;
   for(int k=0;k<16;k++){re[k]+=int64_t(x)*coeff[(pos*ks[k])&255];im[k]-=int64_t(x)*coeff[(pos*ks[k]+192)&255];}
   if(++pos==256){std::array<unsigned,16> a;for(int k=0;k<16;k++){uint64_t r=std::abs(re[k]),i=std::abs(im[k]);a[k]=std::min<uint64_t>(65535,(std::max(r,i)+(std::min(r,i)>>1)+(1<<21))>>22);re[k]=im[k]=0;}gold.push_back(a);pos=0;}outputs++;
  }
  d.p_vclk.set(vc);vi++;d.step();
  if(vc&&d.p_dft__valid.get<bool>()){
   if(gold.empty()||!d.p_display__dft__valid.get<bool>())return 1;auto a=gold.front();gold.pop_front();for(unsigned k=0;k<16;k++){unsigned off=k*16;unsigned got=(d.p_amplitudes.data[off/32]>>(off%32))&65535;unsigned hb=k*5,height=0;for(unsigned bit=0;bit<5;bit++)height|=((d.p_display__heights.data[(hb+bit)/32]>>((hb+bit)%32))&1)<<bit;if(height!=std::min(26u,(a[k]*26+4096)>>13)){std::cerr<<"Display DFT height mismatch\n";return 1;}if(got!=a[k]){std::cerr<<"Integrated DFT mismatch\n";return 1;}}blocks++;
  }
  if(vc&&d.p_acr__valid.get<bool>()){if(d.p_n.get<unsigned>()!=6144|| (acrs && (d.p_cts.get<unsigned>()<(actual_pll?24985:24999)||d.p_cts.get<unsigned>()>(actual_pll?24987:25001)))){std::cerr<<"ACR CTS mismatch\n";return 1;}acrs++;}
 }
 if(d.p_output__overrun.get<bool>()||d.p_dft__overrun.get<bool>())return 1;
}
if(sent<47990||received+2<sent||outputs+1<received||blocks<180||acrs<990)return 1;
std::cout<<"PASS audio_system: one second exact 12.288/25/50 MHz, native shared 9-bit RAM and CDC clocks, "<<received<<(actual_pll?" PLL-rate stereo pairs, ":" nominal stereo pairs, ")<<outputs<<" processed samples, "<<blocks<<" DFT blocks, "<<acrs<<" ACR packets, no drop/overrun\n";
}
