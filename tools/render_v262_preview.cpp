#include "osd_preview.cc"
#include <fstream>
#include <stdexcept>
#include <iostream>
using namespace cxxrtl_design;
int main(){p_osd__display d;
 auto tick=[&](){d.p_video__clk.set(false);d.p_clk50.set(false);d.step();d.p_clk50.set(true);d.step();d.step();d.p_clk50.set(false);d.step();d.p_clk50.set(true);d.p_video__clk.set(true);d.step();d.step();d.step();};
 d.p_rst.set(true);for(int i=0;i<10;i++)tick();d.p_rst.set(false);d.p_display__valid.set(true);d.p_scale__mode.set(3);d.p_alpha__mode.set(1);d.p_img__total__count.set(4);d.p_bmp__width.set(333);d.p_bmp__height.set(221);d.p_scaled__width.set(640);d.p_scaled__height.set(424);
 auto frame=[&](){d.p_de__in.set(false);d.p_vs__in.set(true);for(int i=0;i<100;i++)tick();d.p_vs__in.set(false);for(int i=0;i<100;i++)tick();};
 auto render=[&](const char*name){frame();std::ofstream file(std::string("output/v262_preview/")+name+".ppm",std::ios::binary);file<<"P6\n640 480\n255\n";unsigned count=0;
 for(unsigned c=0;c<800*480+4;c++){unsigned x=c%800,y=c/800;d.p_de__in.set(c<800*480&&x<640);d.p_hs__in.set(x>=656&&x<752);d.p_rgb__in.set(((x*255/640)<<16)|((y*255/480)<<8)|0x60);tick();if(d.p_de__out.get<bool>()){unsigned rgb=d.p_rgb__out.get<unsigned>();char bytes[]={char(rgb>>16),char(rgb>>8),char(rgb)};file.write(bytes,3);count++;}}if(count!=640*480)throw std::runtime_error("Preview pixel count");};
 render("default");d.p_contrast__lvl__in.set(1);render("feedback");d.p_hud__en.set(true);for(int i=0;i<18;i++)frame();render("hud");d.p_emergency__mode.set(true);render("emergency");std::cout<<"Four actual RTL frames rendered\n";
}
