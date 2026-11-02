#include "bmp.cc"
#include <iostream>
#include <vector>
using namespace cxxrtl_design;
static void put32(std::vector<unsigned>& b,unsigned a,unsigned v){for(unsigned i=0;i<4;++i)b[a+i]=(v>>(8*i))&255;}
int main(){
  unsigned checks=0;
  for(unsigned w: {1u,2u,3u,152u,160u,333u,640u}) {
    // 56 + 152*3 = 512: last byte and sector end are adjacent cycles.
    const unsigned h=w==152?1:3, offset=w==152?56:54, stride=(w*3+3)&~3u, size=offset+stride*h;
    std::vector<unsigned> b(((size+511)/512)*512,0),expected;
    b[0]='B';b[1]='M';put32(b,14,40);b[26]=1;put32(b,2,size);put32(b,10,offset);put32(b,14,40);put32(b,18,w);put32(b,22,h);b[26]=1;b[28]=24;
    for(unsigned y=0;y<h;++y)for(unsigned x=0;x<w;++x){
      unsigned rgb=((x*17%256)<<16)|((y*31)<<8)|((x+y)%256);
      unsigned a=offset+y*stride+x*3;b[a]=rgb&255;b[a+1]=(rgb>>8)&255;b[a+2]=(rgb>>16)&255;expected.push_back(rgb);
    }
    p_bmp__read d;
    auto tick=[&](){d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();};
    d.p_rst.set(true);tick();d.p_rst.set(false);d.p_sd__init__done.set(true);d.p_load__sector.set(16384);
    d.p_load__start.set(true);tick();d.p_load__start.set(false);tick();
    for(unsigned i=0;i<512;++i){d.p_sd__sec__read__data.set(b[i]);d.p_sd__sec__read__data__valid.set(true);tick();}
    d.p_sd__sec__read__data__valid.set(false);d.p_sd__sec__read__end.set(true);tick();d.p_sd__sec__read__end.set(false);
    if(!d.p_write__req.get<bool>()){std::cerr<<"BMP header rejected width="<<w<<"\n";return 1;}
    d.p_write__req__ack.set(true);for(int i=0;i<6;++i)tick();d.p_write__req__ack.set(false);
    unsigned n=0;bool done=false;
    for(unsigned i=0;i<b.size();++i){
      d.p_sd__sec__read__data.set(b[i]);d.p_sd__sec__read__data__valid.set(true);tick();
      if(d.p_bmp__data__wr__en.get<bool>()){
        if(n>=expected.size()||d.p_bmp__data.get<unsigned>()!=expected[n]){std::cerr<<"BMP pixel mismatch width="<<w<<" index="<<n<<"\n";return 1;}++n;++checks;
      }
      if(i%512==511){d.p_sd__sec__read__data__valid.set(false);d.p_sd__sec__read__end.set(true);tick();done=d.p_load__done.get<bool>();d.p_sd__sec__read__end.set(false);tick();}
    }
    if(n!=expected.size()||!done){std::cerr<<"BMP count/completion mismatch "<<n<<" != "<<expected.size()<<" done="<<done<<"\n";return 1;}
  }
  // Reject dimensions whose lower half previously masqueraded as a valid image.
  for(unsigned width: {0u,641u,0x10000001u,0xFFFFFFFFu}){
    p_bmp__read d;auto tick=[&](){d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();};
    std::vector<unsigned>b(512,0);b[0]='B';b[1]='M';put32(b,14,40);b[26]=1;put32(b,18,width);put32(b,22,3);b[28]=24;
    d.p_rst.set(true);tick();d.p_rst.set(false);d.p_load__start.set(true);tick();d.p_load__start.set(false);tick();
    for(unsigned v:b){d.p_sd__sec__read__data.set(v);d.p_sd__sec__read__data__valid.set(true);tick();}
    d.p_sd__sec__read__data__valid.set(false);d.p_sd__sec__read__end.set(true);tick();
    if(d.p_write__req.get<bool>()){std::cerr<<"Invalid BMP accepted "<<width<<"\n";return 1;}
  }
  // Reject malformed encoding/header lengths before requesting an SDRAM write.
  for(unsigned fault=0;fault<18;++fault){
    p_bmp__read d;auto tick=[&](){d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();};
    std::vector<unsigned>b(512,0);b[0]='B';b[1]='M';put32(b,2,78);put32(b,10,54);put32(b,14,40);put32(b,18,2);put32(b,22,3);b[26]=1;b[28]=24;
    switch(fault){case 0:put32(b,22,0);break;case 1:put32(b,22,481);break;case 2:put32(b,22,0xfffffffd);break;
      case 3:b[28]=32;break;case 4:put32(b,30,1);break;case 5:b[26]=2;break;case 6:put32(b,14,12);break;
      case 7:put32(b,10,53);break;case 8:put32(b,2,77);break;case 9:put32(b,10,0xfffffff8);break;
      case 10:b[27]=1;break;case 11:b[29]=1;break;case 12:b[31]=1;break;case 13:b[32]=1;break;case 14:b[33]=1;break;
      case 15:b[20]=1;break;case 16:b[24]=1;break;case 17:b[25]=1;break;}
    d.p_rst.set(true);tick();d.p_rst.set(false);d.p_load__start.set(true);tick();d.p_load__start.set(false);tick();
    for(unsigned v:b){d.p_sd__sec__read__data.set(v);d.p_sd__sec__read__data__valid.set(true);tick();}
    d.p_sd__sec__read__data__valid.set(false);d.p_sd__sec__read__end.set(true);tick();
    if(d.p_write__req.get<bool>()){std::cerr<<"Malformed BMP accepted fault="<<fault<<"\n";return 1;}
  }
  // Miss -> image -> skip its data -> miss -> second image, plus max-sector exit.
  for(unsigned max_sector:{102u,110u}){
    p_bmp__read d;auto tick=[&](){d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();};
    d.p_rst.set(true);tick();d.p_rst.set(false);d.p_sd__init__done.set(true);
    d.p_scan__start__sector.set(100);d.p_scan__max__sector.set(max_sector);d.p_scan__target__count.set(2);
    d.p_scan__start.set(true);tick();d.p_scan__start.set(false);tick();
    unsigned found=0;
    for(unsigned sector:{100u,101u,104u,105u}){
      if(d.p_sd__sec__read__addr.get<unsigned>()!=sector)return 1;
      std::vector<unsigned>b(512,0);
      if(sector==101||sector==105){b[0]='B';b[1]='M';put32(b,14,40);b[26]=1;put32(b,2,1494);put32(b,10,54);put32(b,18,160);put32(b,22,3);b[28]=24;}
      for(unsigned v:b){d.p_sd__sec__read__data.set(v);d.p_sd__sec__read__data__valid.set(true);tick();}
      d.p_sd__sec__read__data__valid.set(false);d.p_sd__sec__read__end.set(true);tick();
      if(d.p_scan__found__valid.get<bool>()){
        if(d.p_scan__found__sector.get<unsigned>()!=sector)return 1;
        ++found;
      }
      bool done=d.p_scan__done.get<bool>();d.p_sd__sec__read__end.set(false);tick();
      if(done)break;
    }
    if(!d.p_scan__done.get<bool>()||found!=(max_sector==102?1u:2u)){
      std::cerr<<"Scan termination/skip mismatch max="<<max_sector<<" found="<<found<<"\n";return 1;
    }
  }
  std::cout<<"PASS BMP: "<<checks<<" pixels, row padding, exact-sector completion, invalid dimensions, image skipping and scan limits\n";
}
