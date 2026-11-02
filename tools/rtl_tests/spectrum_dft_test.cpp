#include "spectrum_dft.cc"
#include <cmath>
#include <iostream>
#include <random>
#include <algorithm>
#include <fstream>
template<size_t N> uint64_t slice(const cxxrtl::value<N>& p,unsigned off,unsigned bits){uint64_t x=0;for(unsigned i=0;i<bits;i++)x|=uint64_t((p.data[(off+i)/32]>>((off+i)%32))&1)<<i;return x;}
template<size_t N> uint64_t slice(const cxxrtl::wire<N>& p,unsigned off,unsigned bits){return slice(p.curr,off,bits);}
int main(){cxxrtl_design::p_audio__spectrum__dft d;auto tick=[&](){d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();};
d.p_rst.set(true);tick();d.p_rst.set(false);unsigned ks[]={1,2,3,4,5,6,7,8,10,12,16,20,24,32,40,53};int coeff[256];for(int n=0;n<256;n++)coeff[n]=int(std::floor(32767*std::cos(2*std::acos(-1)*n/256)+.5));std::mt19937 gen(1076);unsigned blocks=4100;std::ofstream vectors("output/verification/dft_reference_vectors.txt");
for(unsigned block=0;block<blocks;block++){
 int64_t re[16]={},im[16]={};double fre[16]={},fim[16]={};unsigned latency=0;
 for(unsigned n=0;n<256;n++){
  int x=block<16?int(std::round(30000*std::sin(2*std::acos(-1)*ks[block]*n/256))):block==16?32767:block==17?0:block==18?(n==0?-32768:0):block==19?int(std::round(12000*(std::sin(2*std::acos(-1)*3*n/256)+std::sin(2*std::acos(-1)*20*n/256)))):block==20?int(std::round(30000*std::sin(2*std::acos(-1)*7.5*n/256))):block==21?int(std::round(30000*std::sin(2*std::acos(-1)*(n*1.0/256+n*n*.08/512)))):int(int16_t(gen()));
  if(block<22)vectors<<x<<" ";
  for(unsigned k=0;k<16;k++){re[k]+=int64_t(x)*coeff[(n*ks[k])&255];im[k]-=int64_t(x)*coeff[(n*ks[k]+192)&255];double a=2*std::acos(-1)*n*ks[k]/256;fre[k]+=x*std::cos(a)*2/256;fim[k]-=x*std::sin(a)*2/256;}
  d.p_sample.set(uint16_t(x));d.p_sample__valid.set(true);tick();d.p_sample__valid.set(false);unsigned wait=0;
  do{tick();wait++;if(d.p_result__valid.get<bool>())latency=wait;}while(d.p_state.get<unsigned>()!=0&&wait<513);
  if(wait>512||d.p_overrun.get<bool>()){std::cerr<<"DFT timing/overrun\n";return 1;}
 }
 if(!latency){std::cerr<<"No result\n";return 1;}
 if(block<22)vectors<<"\n";
 unsigned peak=0,maxamp=0;
 for(unsigned k=0;k<16;k++){
  uint64_t r=slice(d.p_debug__re,k*40,40),i=slice(d.p_debug__im,k*40,40);int64_t rr=int64_t(r<<24)>>24,ii=int64_t(i<<24)>>24;
  uint64_t a=std::abs(re[k]),b=std::abs(im[k]);if(a<b)std::swap(a,b);unsigned amp=std::min<uint64_t>(65535,(a+(b>>1)+(1<<21))>>22),got=slice(d.p_amplitudes,k*16,16);
  if(block<22)vectors<<rr<<" "<<ii<<" "<<got<<"\n";
  if(rr!=re[k]||ii!=im[k]||got!=amp||std::abs(rr/double(1<<22)-fre[k])>8||std::abs(ii/double(1<<22)-fim[k])>8){std::cerr<<"DFT mismatch block="<<block<<" bin="<<k<<"\n";return 1;}
  if(got>maxamp){maxamp=got;peak=k;}
 }
 if(block<16&&peak!=block){std::cerr<<"DFT peak\n";return 1;}
}
// Pause discards a partial window; restart must produce exact silence.
for(unsigned i=0;i<37;i++){d.p_sample.set(12345);d.p_sample__valid.set(true);tick();d.p_sample__valid.set(false);for(unsigned c=0;c<321;c++)tick();}
for(unsigned c=0;c<5000;c++)tick();if(d.p_n.get<unsigned>()!=0)return 1;
for(unsigned i=0;i<256;i++){d.p_sample.set(0);d.p_sample__valid.set(true);tick();d.p_sample__valid.set(false);for(unsigned c=0;c<321;c++)tick();}
for(unsigned k=0;k<16;k++)if(slice(d.p_amplitudes,k*16,16))return 1;
d.p_sample__valid.set(true);tick();tick();if(!d.p_overrun.get<bool>())return 1;d.p_rst.set(true);tick();if(d.p_overrun.get<bool>())return 1;
std::cout<<"PASS spectrum_dft: "<<blocks*256<<" samples, integer complex/magnitude exact, float error <=8 LSB, 16 peaks, 320 clocks at 50 MHz (160 video clocks), DC/silence/dual/off-bin/sweep/random, overrun/reset\n";
}
