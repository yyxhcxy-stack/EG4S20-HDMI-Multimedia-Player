#if defined(PARAMETER_TEST)
#include "parameter_feedback.cc"
#elif defined(MARQUEE_TEST)
#include "marquee_osd.cc"
#elif defined(ANLOGIC_RAM_MODEL)
#include "osd_bram.cc"
#else
#include "osd.cc"
#endif
#include "osd_reference.cc"
#include <iostream>
#include <deque>
#include <cmath>
#include <algorithm>
#include <fstream>
#include <vector>
using namespace cxxrtl_design;
static unsigned bcd(unsigned n){return (n/100)<<8|((n/10)%10)<<4|n%10;}
int main(){
 p_osd__display d;p_osd__reference before;unsigned golden=0;
 unsigned feedback_count=0,feedback_kind=0;bool feedback_initialized=false,prior_emergency=false;
 unsigned previous_parameters[8]={};
 unsigned bars[16]={},peaks[16]={},holds[16]={},amp[16]={},pending_amp[16]={},sample_pos=0,busy=0,latest_delay=0;bool decay=false;
 std::deque<unsigned> source_samples;unsigned delivered=0;
 int64_t re[16]={},im[16]={};int coefficients[256],ks[]={1,2,3,4,5,6,7,8,10,12,16,20,24,32,40,53};
 for(int i=0;i<256;i++)coefficients[i]=int(std::floor(32767*std::cos(2*std::acos(-1)*i/256)+.5));
 #ifdef ANLOGIC_RAM_MODEL
 unsigned history[1024]={};
 #endif
 int normal_offset=0;bool normal_phase=false;std::string custom_text;unsigned memory_character=32;
 const std::string labels[]={"SCALE","VOLUME","BRIGHTNESS","CONTRAST","IMAGE EFFECT","ALPHA","TRANSITION","PLAY MODE"};
 const std::string scale[]={"1.0X","2.0X","0.5X","AUTO"},volume[]={"100%"," 75%"," 50%"," 25%","MUTE"},bright[]={"100%","125%"," 75%","150%"},contrast[]={"1.00X","1.25X","1.50X","2.00X","0.75X"},color[]={"COLOR: VIVID (ORIG)","COLOR: MONO (B&W)","RUBB: INK-RUBBING","SPLIT: COLOR/RUBB"},alpha[]={"25%","50%","75%"},trans[]={"FADE","BLND","WIPE","AUTO"};
 auto tick=[&](){
 int source_x=int(before.p_x__cnt.get<unsigned>())+normal_offset;
 unsigned ci=(unsigned(source_x)&1023)>>3;
 unsigned character=source_x>=0&&ci<custom_text.size()?unsigned(custom_text[ci]):32;
 d.p_marq__read__data.set(memory_character);
 unsigned address=d.p_marq__read__addr.get<unsigned>();
 unsigned next_memory_character=address<custom_text.size()?unsigned(custom_text[address]):32;
 before.p_reference__marq__hidden.set(d.p_marq__hidden.get<bool>());
 before.p_reference__marq__custom.set(d.p_marq__custom__valid.get<bool>());
 before.p_reference__marq__char.set(character);
 before.p_reference__marq__position.set(unsigned(normal_offset)&1023);
 bool fp=d.p_vs__in__d.get<bool>()&&!d.p_vs__in.get<bool>();
 unsigned current_parameters[8]={d.p_scale__mode.get<unsigned>(),d.p_vol__mode.get<unsigned>(),d.p_sw__in.get<unsigned>()&3,d.p_contrast__lvl__in.get<unsigned>(),d.p_color__mode.get<unsigned>(),d.p_alpha__mode.get<unsigned>(),d.p_trans__mode.get<unsigned>(),d.p_auto__play__status.get<unsigned>()};
 if(d.p_rst.get<bool>()){feedback_count=0;feedback_kind=0;feedback_initialized=false;prior_emergency=false;}
 // Drive the oracle with the previously committed snapshot, before this edge.
 bool feedback_active=feedback_count&&!before.p_active__hud__en.get<bool>()&&!before.p_active__emergency.get<bool>()&&before.p_hud__fade__step.get<unsigned>()==0;
 unsigned xx=before.p_x__cnt.get<unsigned>(),yy=before.p_y__cnt.get<unsigned>(),column=xx>=444?(xx-444)/8:999;
 unsigned *pp=previous_parameters;
 const std::string *values[]={&scale[pp[0]%4],&volume[pp[1]%5],&bright[pp[2]%4],&contrast[pp[3]%5],&color[pp[4]%4],&alpha[pp[5]%3],&trans[pp[6]%4],&labels[0]};
 const std::string auto_value="AUTO",manual_value="MANUAL";values[7]=pp[7]?&auto_value:&manual_value;
 bool value_line=yy>=66;const std::string &notice_text=value_line?*values[feedback_kind]:labels[feedback_kind];
 before.p_reference__feedback__active.set(feedback_active);before.p_reference__feedback__value.set(value_line);
 before.p_reference__feedback__char.set(column<notice_text.size()?unsigned(notice_text[column]):32);
 auto dim=[](unsigned n){std::string q=std::to_string(n);return std::string(3-q.size(),'0')+q;};
 std::string geometry=(xx>=444&&xx<620&&yy>=186&&yy<238)?(yy<204?"VIDEO: 640X480":yy<222?"INPUT: "+dim(d.p_bmp__width.get<unsigned>())+"X"+dim(d.p_bmp__height.get<unsigned>()):"WINDOW:"+dim(d.p_scaled__width.get<unsigned>())+"X"+dim(d.p_scaled__height.get<unsigned>())):"";
 before.p_reference__geometry__char.set(column<geometry.size()?unsigned(geometry[column]):32);
 if(fp&&!d.p_rst.get<bool>()){
   bool emergency=d.p_emergency__mode.get<bool>();
   if(!feedback_initialized||d.p_hud__en.get<bool>()||emergency||prior_emergency)feedback_count=0;
   else {unsigned changed=8;for(unsigned i=0;i<8;i++)if(current_parameters[i]!=previous_parameters[i]){changed=i;break;}if(changed<8){feedback_kind=changed;feedback_count=120;}else if(feedback_count)feedback_count--;}
   for(unsigned i=0;i<8;i++)previous_parameters[i]=current_parameters[i];feedback_initialized=true;prior_emergency=emergency;
 }
 for(unsigned j=0;j<3;j++){before.p_reference__bars.data[j]=0;before.p_reference__peaks.data[j]=0;}
 for(unsigned j=0;j<16;j++){unsigned off=j*5;before.p_reference__bars.data[off/32]|=bars[j]<<(off%32);before.p_reference__peaks.data[off/32]|=peaks[j]<<(off%32);if(off%32>27){before.p_reference__bars.data[off/32+1]|=bars[j]>>(32-off%32);before.p_reference__peaks.data[off/32+1]|=peaks[j]>>(32-off%32);}}
 if(d.p_rst.get<bool>()){for(int i=0;i<16;i++)bars[i]=peaks[i]=holds[i]=amp[i]=re[i]=im[i]=0;sample_pos=busy=latest_delay=0;decay=false;}
 else {
  if(d.p_spectrum_2e_genblk1_2e_result__cdc_2e_received.get<bool>()) {for(int i=0;i<16;i++){unsigned off=i*5;unsigned got=0;for(unsigned bit=0;bit<5;bit++)got|=((d.p_spectrum_2e_genblk1_2e_result__cdc_2e_data__out.curr.data[(off+bit)/32]>>((off+bit)%32))&1)<<bit;if(got!=std::min(26u,(pending_amp[i]*26+4096)>>13)){std::cerr<<"Shared DFT height mismatch tick="<<golden<<" bin="<<i<<" got="<<got<<" expected="<<std::min(26u,(pending_amp[i]*26+4096)>>13)<<" delivered="<<delivered<<" n="<<d.p_spectrum_2e_dft_2e_n.get<unsigned>()<<" overrun="<<d.p_spectrum_2e_dft_2e_overrun.get<bool>()<<" amp="<<pending_amp[i]<<" pos="<<sample_pos<<"\n";exit(1);}amp[i]=pending_amp[i];}}
  if(fp){bool playing=(d.p_display__valid.get<bool>() && d.p_audio__active__cnt.get<unsigned>()>0);for(int i=0;i<16;i++){unsigned h=playing?std::min(26u,(amp[i]*26+4096)>>13):0;bars[i]=h>=bars[i]?h:bars[i]-1;if(h>=peaks[i]&&h>0){peaks[i]=h;holds[i]=14;}else if(holds[i])holds[i]--;else if(decay&&peaks[i])peaks[i]--;}decay=!decay;}

  if(d.p_audio__valid.get<bool>()){
    source_samples.push_back((d.p_audio__left.get<unsigned>()>>8)&65535);
    int x=int32_t(d.p_audio__left.get<unsigned>()<<8)>>16;for(int i=0;i<16;i++){re[i]+=int64_t(x)*coefficients[(sample_pos*ks[i])&255];im[i]-=int64_t(x)*coefficients[(sample_pos*ks[i]+192)&255];}
    if(++sample_pos==256){for(int i=0;i<16;i++){uint64_t a=std::abs(re[i]),b=std::abs(im[i]);pending_amp[i]=std::min<uint64_t>(65535,(std::max(a,b)+(std::min(a,b)>>1)+(1<<21))>>22);re[i]=im[i]=0;}sample_pos=0;}
  }
 }

 #ifdef ANLOGIC_RAM_MODEL
 unsigned nx=fp?0:d.p_de__in.get<bool>()?(d.p_x__cnt.get<unsigned>()+1)&255:0;unsigned ba=d.p_rst.get<bool>()?104:(d.p_wave__wr__ptr.get<unsigned>()+unsigned(d.p_audio__valid.get<bool>())+nx-152)&255;unsigned expected_b=history[ba];
 #endif
  before.p_rst.set(d.p_rst.get<unsigned>());
  before.p_vs__in.set(d.p_vs__in.get<unsigned>());
  before.p_hs__in.set(d.p_hs__in.get<unsigned>());
  before.p_de__in.set(d.p_de__in.get<unsigned>());
  before.p_rgb__in.set(d.p_rgb__in.get<unsigned>());
  before.p_sw__in.set(d.p_sw__in.get<unsigned>());
  before.p_contrast__lvl__in.set(d.p_contrast__lvl__in.get<unsigned>());
  before.p_hud__en.set(d.p_hud__en.get<unsigned>());
  before.p_alpha__mode.set(d.p_alpha__mode.get<unsigned>());
  before.p_scale__mode.set(d.p_scale__mode.get<unsigned>());
  before.p_color__mode.set(d.p_color__mode.get<unsigned>());
  before.p_trans__mode.set(d.p_trans__mode.get<unsigned>());
  before.p_bmp__width.set(d.p_bmp__width.get<unsigned>());
  before.p_scaled__width.set(d.p_scaled__width.get<unsigned>());
  before.p_bmp__height.set(d.p_bmp__height.get<unsigned>());
  before.p_auto__play__status.set(d.p_auto__play__status.get<unsigned>());
  before.p_cur__img__idx.set(d.p_cur__img__idx.get<unsigned>());
  before.p_display__valid.set(d.p_display__valid.get<unsigned>());
  before.p_load__fail__hold.set(d.p_load__fail__hold.get<unsigned>());
  before.p_audio__valid.set(d.p_audio__valid.get<unsigned>());
  before.p_audio__left.set(d.p_audio__left.get<unsigned>());
  before.p_sdram__loading.set(d.p_sdram__loading.get<unsigned>());
  before.p_fade__active.set(d.p_fade__active.get<unsigned>());
  before.p_img__total__count.set(d.p_img__total__count.get<unsigned>());
  before.p_vol__mode.set(d.p_vol__mode.get<unsigned>());
  before.p_emergency__mode.set(d.p_emergency__mode.get<unsigned>());
  before.p_scada__active.set(d.p_scada__active.get<unsigned>());
  before.p_scaled__height.set(d.p_scaled__height.get<unsigned>());
  auto fast=[&](){d.p_clk50.set(false);d.step();
 #ifdef ANLOGIC_RAM_MODEL
 bool av50=d.p_spectrum_2e_input__cdc_2e_received.get<bool>();unsigned aa=av50?d.p_spectrum_2e_wave__pointer.get<unsigned>():256+d.p_spectrum_2e_dft_2e_bin.get<unsigned>()*9+std::min(8u,d.p_spectrum_2e_dft_2e_segment.get<unsigned>());unsigned expected_a=history[aa];if(!d.p_rst.get<bool>()&&(av50||d.p_spectrum_2e_dft_2e_state.get<unsigned>()==3))history[aa]=av50?(d.p_spectrum_2e_input__cdc_2e_data__out.get<unsigned>()>>8):d.p_spectrum_2e_dft_2e_read__word.curr.data[0]&511;
 #endif
 if(!d.p_rst.get<bool>() && d.p_spectrum_2e_input__cdc_2e_received.get<bool>()) {unsigned got=d.p_spectrum_2e_input__cdc_2e_data__out.get<unsigned>()&65535;if(source_samples.empty()||got!=source_samples.front()){std::cerr<<"Sample CDC loss/mismatch tick="<<golden<<" delivered="<<delivered<<"\n";exit(1);}source_samples.pop_front();delivered++;}
 d.p_clk50.set(true);d.step();d.step();
 #ifdef ANLOGIC_RAM_MODEL
 if(d.p_spectrum_2e_audio__history__bram_2e_doa.get<unsigned>()!=expected_a){std::cerr<<"RAM A port mismatch\n";exit(1);}
 #endif
 };
  fast();fast();
  d.p_video__clk.set(false);before.p_video__clk.set(false);d.step();before.step();
  if(d.p_rst.get<bool>()){normal_offset=0;normal_phase=false;}
  else if(d.p_marq__normal__reset.get<bool>()){normal_offset=d.p_marq__custom__valid.get<bool>()?-640:0;normal_phase=false;}
  else if(fp&&!d.p_marq__hidden.get<bool>()&&!before.p_active__emergency.get<bool>()){
    if(normal_phase){++normal_offset;if(normal_offset==1024)normal_offset=0;}normal_phase=!normal_phase;
  }
  d.p_video__clk.set(true);before.p_video__clk.set(true);d.step();before.step();d.step();before.step();
  memory_character=next_memory_character;before.p_reference__marq__position.set(unsigned(normal_offset)&1023);d.step();before.step();
  if(d.p_normal__scroll__pos.get<unsigned>()!=(unsigned(normal_offset)&1023)||d.p_normal__entering.get<bool>()!=(normal_offset<0)){std::cerr<<"Independent right-entry scroll mismatch\n";exit(1);}
  #ifdef ANLOGIC_RAM_MODEL
  if(d.p_spectrum_2e_audio__history__bram_2e_dob.get<unsigned>()!=expected_b){std::cerr<<"RAM B port mismatch\n";exit(1);}
  #endif
  if(fp&&!d.p_rst.get<bool>()){
    if(d.p_spec__bar__h_5b_0_5d_.get<unsigned>()!=bars[0]||d.p_spec__bar__peak_5b_0_5d_.get<unsigned>()!=peaks[0]){std::cerr<<"DFT ballistics mismatch bin 0\n";exit(1);}
    if(d.p_spec__bar__h_5b_1_5d_.get<unsigned>()!=bars[1]||d.p_spec__bar__peak_5b_1_5d_.get<unsigned>()!=peaks[1]){std::cerr<<"DFT ballistics mismatch bin 1\n";exit(1);}
    if(d.p_spec__bar__h_5b_2_5d_.get<unsigned>()!=bars[2]||d.p_spec__bar__peak_5b_2_5d_.get<unsigned>()!=peaks[2]){std::cerr<<"DFT ballistics mismatch bin 2\n";exit(1);}
    if(d.p_spec__bar__h_5b_3_5d_.get<unsigned>()!=bars[3]||d.p_spec__bar__peak_5b_3_5d_.get<unsigned>()!=peaks[3]){std::cerr<<"DFT ballistics mismatch bin 3\n";exit(1);}
    if(d.p_spec__bar__h_5b_4_5d_.get<unsigned>()!=bars[4]||d.p_spec__bar__peak_5b_4_5d_.get<unsigned>()!=peaks[4]){std::cerr<<"DFT ballistics mismatch bin 4\n";exit(1);}
    if(d.p_spec__bar__h_5b_5_5d_.get<unsigned>()!=bars[5]||d.p_spec__bar__peak_5b_5_5d_.get<unsigned>()!=peaks[5]){std::cerr<<"DFT ballistics mismatch bin 5\n";exit(1);}
    if(d.p_spec__bar__h_5b_6_5d_.get<unsigned>()!=bars[6]||d.p_spec__bar__peak_5b_6_5d_.get<unsigned>()!=peaks[6]){std::cerr<<"DFT ballistics mismatch bin 6\n";exit(1);}
    if(d.p_spec__bar__h_5b_7_5d_.get<unsigned>()!=bars[7]||d.p_spec__bar__peak_5b_7_5d_.get<unsigned>()!=peaks[7]){std::cerr<<"DFT ballistics mismatch bin 7\n";exit(1);}
    if(d.p_spec__bar__h_5b_8_5d_.get<unsigned>()!=bars[8]||d.p_spec__bar__peak_5b_8_5d_.get<unsigned>()!=peaks[8]){std::cerr<<"DFT ballistics mismatch bin 8\n";exit(1);}
    if(d.p_spec__bar__h_5b_9_5d_.get<unsigned>()!=bars[9]||d.p_spec__bar__peak_5b_9_5d_.get<unsigned>()!=peaks[9]){std::cerr<<"DFT ballistics mismatch bin 9\n";exit(1);}
    if(d.p_spec__bar__h_5b_10_5d_.get<unsigned>()!=bars[10]||d.p_spec__bar__peak_5b_10_5d_.get<unsigned>()!=peaks[10]){std::cerr<<"DFT ballistics mismatch bin 10\n";exit(1);}
    if(d.p_spec__bar__h_5b_11_5d_.get<unsigned>()!=bars[11]||d.p_spec__bar__peak_5b_11_5d_.get<unsigned>()!=peaks[11]){std::cerr<<"DFT ballistics mismatch bin 11\n";exit(1);}
    if(d.p_spec__bar__h_5b_12_5d_.get<unsigned>()!=bars[12]||d.p_spec__bar__peak_5b_12_5d_.get<unsigned>()!=peaks[12]){std::cerr<<"DFT ballistics mismatch bin 12\n";exit(1);}
    if(d.p_spec__bar__h_5b_13_5d_.get<unsigned>()!=bars[13]||d.p_spec__bar__peak_5b_13_5d_.get<unsigned>()!=peaks[13]){std::cerr<<"DFT ballistics mismatch bin 13\n";exit(1);}
    if(d.p_spec__bar__h_5b_14_5d_.get<unsigned>()!=bars[14]||d.p_spec__bar__peak_5b_14_5d_.get<unsigned>()!=peaks[14]){std::cerr<<"DFT ballistics mismatch bin 14\n";exit(1);}
    if(d.p_spec__bar__h_5b_15_5d_.get<unsigned>()!=bars[15]||d.p_spec__bar__peak_5b_15_5d_.get<unsigned>()!=peaks[15]){std::cerr<<"DFT ballistics mismatch bin 15\n";exit(1);}
  }
  if(d.p_feedback__frames.get<unsigned>()!=feedback_count||d.p_feedback__kind.get<unsigned>()!=feedback_kind){std::cerr<<"Feedback commit/count mismatch tick="<<golden<<" expected="<<feedback_count<<" got="<<d.p_feedback__frames.get<unsigned>()<<"\n";exit(1);}
  if(d.p_de__out.get<bool>()!=before.p_de__out.get<bool>()||d.p_hs__out.get<bool>()!=before.p_hs__out.get<bool>()||d.p_vs__out.get<bool>()!=before.p_vs__out.get<bool>()||d.p_rgb__out.get<unsigned>()!=before.p_rgb__out.get<unsigned>()){std::cerr<<"OSD golden pixel/control mismatch tick="<<golden<<" x="<<d.p_x__cnt.get<unsigned>()<<" y="<<d.p_y__cnt.get<unsigned>()<<" rgb="<<std::hex<<d.p_rgb__out.get<unsigned>()<<" ref="<<before.p_rgb__out.get<unsigned>()<<std::dec<<"\n";exit(1);}++golden;
 };
 d.p_rst.set(true);tick();if(d.p_active__hud__en.get<bool>()||d.p_hud__fade__step.get<unsigned>()){std::cerr<<"HUD startup flash\n";return 1;}d.p_rst.set(false);d.p_hud__en.set(true);d.p_display__valid.set(true);
 unsigned checks=0;
 for(unsigned w:{1u,2u,9u,10u,99u,100u,160u,333u,639u,640u})for(unsigned m=0;m<4;++m){
  unsigned h=w%479+1,dw=m==2?(w+1)/2:640,dh=m==2?(h+1)/2:480;
  d.p_bmp__width.set(w);d.p_bmp__height.set(h);d.p_scaled__width.set(dw);d.p_scaled__height.set(dh);d.p_scale__mode.set(m);
  for(unsigned i=0;i<100;++i)tick();
  if(d.p_source__w__bcd.get<unsigned>()!=bcd(w)||d.p_source__h__bcd.get<unsigned>()!=bcd(h)||d.p_display__w__bcd.get<unsigned>()!=bcd(dw)||d.p_display__h__bcd.get<unsigned>()!=bcd(dh)){std::cerr<<"OSD dimension conversion mismatch\n";return 1;}
  d.p_vs__in.set(true);for(int i=0;i<4;++i)tick();d.p_vs__in.set(false);for(int i=0;i<4;++i)tick();
  if(d.p_active__scale__mode.get<unsigned>()!=m){std::cerr<<"OSD mode mismatch\n";return 1;}
  ++checks;
 }
 struct Sync{bool hs,vs,de;};std::deque<Sync>q(1,{false,false,false});
 for(unsigned c=0;c<800*480+4;++c){bool de=c%800<640&&c<800*480,hs=c%800>=656&&c%800<752,vs=false;
  d.p_de__in.set(de);d.p_hs__in.set(hs);d.p_vs__in.set(vs);d.p_rgb__in.set(0x4080c0);q.push_back({hs,vs,de});auto e=q.front();q.pop_front();tick();
  if(d.p_de__out.get<bool>()!=e.de||d.p_hs__out.get<bool>()!=e.hs||d.p_vs__out.get<bool>()!=e.vs){std::cerr<<"OSD sync mismatch\n";return 1;}
  if(!e.de&&d.p_rgb__out.get<unsigned>()!=0){std::cerr<<"OSD blanking mismatch\n";return 1;}
 }
 // Golden frames exercise coloured text, emergency overlays and live spectrum/wave.
 for(unsigned frame=0;frame<5;++frame){
  d.p_audio__valid.set(false);d.p_de__in.set(false);d.p_vs__in.set(true);d.p_sw__in.set(frame);d.p_contrast__lvl__in.set(frame+1);d.p_alpha__mode.set(frame%3);
  d.p_emergency__mode.set(frame==3);d.p_color__mode.set(frame==2?2:0);d.p_cur__img__idx.set(frame);d.p_img__total__count.set(4);
  d.p_sdram__loading.set(frame==2);d.p_scada__active.set(frame==1);d.p_fade__active.set(frame==1);
  for(int i=0;i<8;++i)tick();d.p_vs__in.set(false);for(int i=0;i<8;++i)tick();
  for(unsigned cycle=0;cycle<800*480+4;++cycle){
   d.p_de__in.set(cycle<800*480&&cycle%800<640);d.p_hs__in.set(cycle%800>=656&&cycle%800<752);
   d.p_rgb__in.set(((cycle*17)&255)<<16|((cycle*31)&255)<<8|((cycle*7)&255));
   d.p_audio__valid.set(golden%521==0);int sample=(int((golden/521)%32)-16)*131072;d.p_audio__left.set(unsigned(sample)&0xffffff);tick();

  }
 }
 auto frame_tick=[&](){d.p_de__in.set(false);d.p_vs__in.set(true);for(unsigned i=0;i<8;i++)tick();d.p_vs__in.set(false);for(unsigned i=0;i<8;i++)tick();};
 d.p_hud__en.set(false);for(int i=0;i<17;i++)frame_tick();if(d.p_hud__fade__step.get<unsigned>()!=0)return 1;
 d.p_hud__en.set(true);for(int i=0;i<17;i++)frame_tick();if(d.p_hud__fade__step.get<unsigned>()!=16)return 1;
#ifdef PARAMETER_TEST
 d.p_hud__en.set(false);d.p_emergency__mode.set(false);d.p_audio__valid.set(false);for(unsigned i=0;i<18;i++)frame_tick();
 auto render_feedback=[&](){for(unsigned c=0;c<800*100+4;c++){d.p_de__in.set(c<800*100&&c%800<640);d.p_hs__in.set(c%800>=656&&c%800<752);d.p_rgb__in.set(0x2468ac);tick();}d.p_de__in.set(false);};
 for(unsigned kind=0;kind<8;kind++){
   switch(kind){case 0:d.p_scale__mode.set((previous_parameters[0]+1)%4);break;case 1:d.p_vol__mode.set((previous_parameters[1]+1)%5);break;case 2:d.p_sw__in.set((previous_parameters[2]+1)%4);break;case 3:d.p_contrast__lvl__in.set((previous_parameters[3]+1)%5);break;case 4:d.p_color__mode.set((previous_parameters[4]+1)%4);break;case 5:d.p_alpha__mode.set((previous_parameters[5]+1)%3);break;case 6:d.p_trans__mode.set((previous_parameters[6]+1)%4);break;case 7:d.p_auto__play__status.set(!previous_parameters[7]);break;}
   for(unsigned i=0;i<8;i++)tick();frame_tick();if(feedback_count!=120||feedback_kind!=kind)return 1;render_feedback();
   for(unsigned f=0;f<119;f++)frame_tick();if(feedback_count!=1)return 1;render_feedback();frame_tick();if(feedback_count!=0)return 1;render_feedback();
 }
 // Same-frame priority, repeated adjustment, suppression and emergency recovery.
 d.p_scale__mode.set((previous_parameters[0]+1)%4);d.p_vol__mode.set((previous_parameters[1]+1)%5);frame_tick();if(feedback_kind!=0||feedback_count!=120)return 1;
 for(unsigned i=0;i<60;i++)frame_tick();d.p_scale__mode.set((previous_parameters[0]+1)%4);frame_tick();if(feedback_count!=120)return 1;
 d.p_emergency__mode.set(true);frame_tick();if(feedback_count)return 1;render_feedback();d.p_emergency__mode.set(false);frame_tick();if(feedback_count)return 1;
 d.p_hud__en.set(true);d.p_vol__mode.set((previous_parameters[1]+1)%5);frame_tick();if(feedback_count)return 1;
 std::cout<<"PASS parameter_feedback: 8 parameter kinds, frame commits, priority/retrigger/120-frame timeout, HUD/emergency suppression/restore, strict feedback and unchanged-region pixels\n";
#endif
#ifdef MARQUEE_TEST
 d.p_hud__en.set(false);d.p_audio__valid.set(false);d.p_emergency__mode.set(false);for(int i=0;i<17;i++)frame_tick();
 unsigned preview_index=0;
 auto render=[&](){frame_tick();std::vector<unsigned char> pixels;
   for(unsigned c=0;c<800*480+4;c++){d.p_de__in.set(c<800*480&&c%800<640);d.p_hs__in.set(c%800>=656&&c%800<752);d.p_rgb__in.set(0x2468ac);tick();
    if(d.p_de__out.get<bool>()){unsigned rgb=d.p_rgb__out.get<unsigned>();pixels.push_back(rgb>>16);pixels.push_back(rgb>>8);pixels.push_back(rgb);}}
   d.p_de__in.set(false);if(pixels.size()!=640*480*3){std::cerr<<"Preview dimensions\n";exit(1);}
   std::ofstream file("output/verification/v261_marquee_frame_"+std::to_string(preview_index++)+".ppm",std::ios::binary);file<<"P6\n640 480\n255\n";file.write(reinterpret_cast<const char*>(pixels.data()),pixels.size());
 };
 auto restart=[&](){d.p_marq__normal__reset.set(true);tick();d.p_marq__normal__reset.set(false);};
 for(unsigned n:{1u,128u,3u}){
   custom_text="A";for(unsigned i=1;i<n;i++)custom_text+=char(32+(i*13+33)%64);
   d.p_marq__custom__valid.set(true);restart();render();
   // The first two frames advance one pixel: A enters at x=639, then x=638.
   for(unsigned frame=0;frame<4;frame++){frame_tick();if(normal_offset!=-640+int((frame+2)/2))return 1;}render();
   for(unsigned frame=0;frame<60;frame++)frame_tick();render();
   for(unsigned frame=0;normal_offset<0&&frame<1281;frame++)frame_tick();if(normal_offset!=0)return 1;render();
   int wrap_start=normal_offset;for(unsigned frame=0;frame<2048;frame++)frame_tick();if(normal_offset!=wrap_start)return 1;render();
 }
 d.p_marq__hidden.set(true);frame_tick();int frozen=normal_offset;for(int f=0;f<5;f++)frame_tick();if(normal_offset!=frozen)return 1;render();
 custom_text="UPDATED WHILE HIDDEN";restart();render();
 d.p_emergency__mode.set(true);frame_tick();render();
 custom_text="UPDATED DURING EMERGENCY";restart();frozen=normal_offset;for(int f=0;f<5;f++)frame_tick();if(normal_offset!=frozen)return 1;render();
 d.p_emergency__mode.set(false);frame_tick();render();
 d.p_marq__hidden.set(false);restart();render();for(int f=0;f<64;f++)frame_tick();render();
 // Repeat update while visible must restart from the right with no old text.
 custom_text="REPLACED";restart();render();
 d.p_marq__custom__valid.set(false);d.p_rst.set(true);tick();d.p_rst.set(false);d.p_hud__en.set(false);frame_tick();render();
 std::cout<<"PASS marquee_osd: independent signed source-coordinate model; 1/128/3 chars right entry, left movement, wrap, repeated updates, hidden/emergency pause/restore/reset; all RGB/DE/HS/VS pixels compared\n";
#endif
 d.p_audio__valid.set(false);d.p_audio__left.set(0);d.p_de__in.set(false);
 for(unsigned c=0;c<2500001;c++)tick();
 for(unsigned f=0;f<100;f++){d.p_vs__in.set(true);for(unsigned c=0;c<4;c++)tick();d.p_vs__in.set(false);for(unsigned c=0;c<4;c++)tick();}
 for(unsigned i=0;i<16;i++)if(bars[i]||peaks[i]){std::cerr<<"Paused display did not decay to zero\n";return 1;}
 std::cout<<"PASS OSD: "<<checks<<" original/output dimension and mode cases, complete frame control alignment, blanking, six golden frames with independent DFT/ballistics inputs and unchanged pixel renderer, waveform and emergency colours\n";
}
