#include "fonts.cc"
#include <fstream>
#include <iostream>
#include <vector>
using namespace cxxrtl_design;
std::vector<unsigned> load(const char* path){std::ifstream f(path);std::vector<unsigned>v;unsigned x;while(f>>std::hex>>x)v.push_back(x);return v;}
int main(){
 auto a=load("tools/rtl_tests/font_rom_8x16_reference.hex"),b=load("tools/rtl_tests/font_rom_8x8_reference.hex");
 if(a.size()!=2048||b.size()!=512)return 1;
 p_font__test d;unsigned checks=0;
 for(unsigned ascii=0;ascii<128;++ascii)for(unsigned row=0;row<16;++row){
   unsigned norm=ascii>=0x61&&ascii<=0x7a?ascii-0x20:ascii;
   unsigned idx=ascii>=1&&ascii<=16?64+ascii-1:(norm>=0x20&&norm<=0x5f?norm-0x20:0);
   unsigned addr8=checks%512;
   d.p_clk.set(false);d.step();d.p_ascii__code.set(ascii);d.p_row.set(row);d.p_char__idx.set(addr8/8);d.p_row8.set(addr8%8);d.step();
   d.p_clk.set(true);d.step();d.step();
   if(d.p_data16.get<unsigned>()!=a[idx*16+row]||d.p_data8.get<unsigned>()!=b[addr8]){
     std::cerr<<"Font changed at ASCII="<<ascii<<" row="<<row<<"\n";return 1;
   }++checks;
 }
 std::cout<<"PASS fonts: "<<checks<<" ASCII/CJK/alias rows and all 512 LCD ROM addresses match original glyphs\n";
}
