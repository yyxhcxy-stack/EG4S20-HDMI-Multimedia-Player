#include "audio_output.cc"
#include <iostream>
#include <random>
#include <algorithm>
static int32_t clamp(int64_t x){return std::max<int64_t>(-8388608,std::min<int64_t>(8388607,x));}
static int32_t scale(int32_t x,int g){return clamp((int64_t(x)*g+128)>>8);}
int main(){cxxrtl_design::p_audio__output__stage d;auto tick=[&](){d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();};d.p_rst.set(true);tick();d.p_rst.set(false);
int gain=0,fade=256,key=0,oldl=0,oldr=0,prevl=0,prevr=0;std::mt19937 gen(1086);unsigned latency=0;
for(unsigned n=0;n<12000;n++){
 bool emerg=n>=3000&&n<6000,en=n>=20&&n<11500;unsigned note=n/31%5,vol=n/263%5;int l=int32_t(gen()<<8)>>8,r=int32_t(gen()<<8)>>8;
 int target=emerg?256:!en?0:vol==0?256:vol==1?192:vol==2?128:vol==3?64:0;gain=emerg?256:gain<target?gain+1:gain>target?gain-1:gain;
 int newkey=(emerg<<4)|(en<<3)|note;if(newkey!=key){fade=4;oldl=prevl;oldr=prevr;}else fade=std::min(256,fade+4);key=newkey;
 int el=clamp(int64_t(scale(scale(l,gain),fade))+scale(oldl,256-fade)),er=clamp(int64_t(scale(scale(r,gain),fade))+scale(oldr,256-fade));
 d.p_enable.set(en);d.p_emergency.set(emerg);d.p_note__idx.set(note);d.p_volume.set(vol);d.p_left__in.set(l&0xffffff);d.p_right__in.set(r&0xffffff);d.p_valid__in.set(true);tick();d.p_valid__in.set(false);
 unsigned w=0;do{tick();w++;}while(!d.p_valid__out.get<bool>()&&w<65);
 int gl=int32_t(d.p_left__out.get<unsigned>()<<8)>>8,gr=int32_t(d.p_right__out.get<unsigned>()<<8)>>8;
 if(w>64|| (latency&&w!=latency)||gl!=el||gr!=er||d.p_overrun.get<bool>()){std::cerr<<"Output mismatch n="<<n<<" got="<<gl<<","<<gr<<" expected="<<el<<","<<er<<" latency="<<w<<"\n";return 1;}latency=w;prevl=el;prevr=er;tick();
}
d.p_valid__in.set(true);tick();tick();if(!d.p_overrun.get<bool>())return 1;
std::cout<<"PASS audio_output: 12000 stereo pairs, exact gain/fade/round/saturation, fixed latency="<<latency<<", all volumes, emergency bypass, retrigger and overrun\n";
}
