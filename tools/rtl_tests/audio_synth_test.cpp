#include "audio_synth.cc"
#include <fstream>
#include <iostream>
#include <vector>
#include <algorithm>
int main(){cxxrtl_design::p_audio__synth d;auto tick=[&](){d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();};auto sample=[&](){for(int i=0;i<255;i++)tick();d.p_sample__tick.set(true);tick();d.p_sample__tick.set(false);};
d.p_rst.set(true);tick();d.p_rst.set(false);d.p_enable.set(true);unsigned inc[]={46819724,52553362,58989156,70150310,78741068};unsigned checks=0;uint32_t phase_model=0;unsigned env[3]={0,0,0},previous=0,model_count=0;bool enabled=false;unsigned last_note=0;
for(unsigned note=0;note<5;note++){d.p_note__idx.set(note);for(unsigned n=0;n<2000;n++){
 auto phase=phase_model;auto e0=env[0],e1=env[1],e2=env[2];
 if(d.p_env0.get<unsigned>()!=e0||d.p_env1.get<unsigned>()!=e1||d.p_env2.get<unsigned>()!=e2){std::cerr<<"Envelope state mismatch\n";return 1;}
 auto tri=[](unsigned p){unsigned x=(p>>15)&65535;if(p>>31)x=(~x)&65535;return int(x)-32768;};
 int64_t sum=((int64_t(tri(d.p_phase0.get<unsigned>()))*(e0>>9))>>7)+((int64_t(tri(d.p_phase1.get<unsigned>()))*(e1>>9))>>7)+((int64_t(tri(d.p_phase2.get<unsigned>()))*(e2>>9))>>7);
 int expected=std::max<int64_t>(-8000000,std::min<int64_t>(8000000,sum)),prev=int32_t(d.p_previous__bell.get<unsigned>()<<8)>>8;
 if(!enabled||note!=last_note||model_count==191999){enabled=true;last_note=note;model_count=0;env[0]=8000000;env[1]=4200000;env[2]=2600000;}else{model_count++;if(env[0]>800000)env[0]-=std::max(1u,env[0]>>16);if(env[1]>200000)env[1]-=std::max(1u,env[1]>>15);if(env[2])env[2]-=std::max(1u,env[2]>>13);}
 phase_model+=inc[note];
 sample();int l=int32_t(d.p_left.get<unsigned>()<<8)>>8,r=int32_t(d.p_right.get<unsigned>()<<8)>>8;
 if(l!=expected||r!=(expected>>1)+(prev>>1)||d.p_phase0.get<unsigned>()!=phase+inc[note]){std::cerr<<"Synth bell mismatch\n";return 1;}checks++;
}}
std::ifstream f("src/rtl/voice_emergency_64kb.hex");std::vector<int> rom;unsigned x;while(f>>std::hex>>x)rom.push_back((int(x)-128)*65536);if(rom.size()!=65536)return 1;
d.p_emergency.set(true);sample();
for(unsigned n=0;n<498816;n++){
 unsigned c=d.p_emerg__count.get<unsigned>();int expected;
 if(c<96000)expected=d.p_alarm__phase.get<unsigned>()>>31?-8200000:8200000;
 else if(c<105600)expected=0;
 else {unsigned idx=(c-105600)/6,step=(c-105600)%6;int64_t a=rom[idx],b=rom[std::min(65535u,idx+1)],v=a;int64_t num=step*(b-a)+3;int64_t delta=num>=0?num/6:-((-num+5)/6);v+=delta;int64_t boosted=v+(v>>1)+(v>>2);expected=std::max<int64_t>(-8200000,std::min<int64_t>(8200000,boosted));}
 sample();int l=int32_t(d.p_left.get<unsigned>()<<8)>>8;if(l!=expected||d.p_left.get<unsigned>()!=d.p_right.get<unsigned>()){std::cerr<<"Emergency mismatch count="<<c<<" got="<<l<<" expected="<<expected<<" step="<<d.p_voice__step.get<unsigned>()<<" idx="<<d.p_voice__index.get<unsigned>()<<"\n";return 1;}checks++;
}
std::cout<<"PASS audio_synth: "<<checks<<" sample checks, five notes, stereo, full emergency cycle, exact signed PCM and six-phase interpolation including final ROM sample\n";
}
