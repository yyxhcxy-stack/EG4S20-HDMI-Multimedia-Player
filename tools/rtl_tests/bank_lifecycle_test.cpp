#include "bank_lifecycle.cc"
#include <iostream>
#include <stdexcept>
using namespace cxxrtl_design;
int main(){try{
p_sd__card__bmp d;unsigned frames=0,requests=0,pending=0;bool finish=false,previous=false;unsigned owned=0;bool valid=false;
auto tick=[&](){
 d.p_clk.set(false);d.step();d.step();
 bool req=d.p_write__req.get<bool>();
 if(req&&!previous){
   unsigned bank=d.p_write__buf__idx.get<unsigned>();
   if(valid&&bank==owned)throw std::runtime_error("Writer overwrote reader-owned bank before handoff");
   requests++;pending=18;
 }
 previous=req;
 d.p_write__req__ack.set(req);
 if(pending&&!--pending)finish=!finish;
 d.p_write__finish__toggle.set(finish);
 d.p_reader__bank.set(owned);d.p_reader__valid.set(valid);
 d.p_clk.set(true);d.step();d.step();
};
auto run=[&](unsigned n){while(n--)tick();};
auto press=[&](){d.p_key__next.set(false);run(35);d.p_key__next.set(true);run(35);};
d.p_rst.set(true);d.p_key__next.set(true);d.p_key__auto.set(true);d.p_SD__MISO.set(true);d.p_bmp__width.set(640);d.p_bmp__height.set(480);run(10);d.p_rst.set(false);run(200);
if(!d.p_display__valid.get<bool>()||requests!=1||d.p_cur__img__idx.get<unsigned>()!=0)throw std::runtime_error("Boot did not commit bank 0");
valid=true;owned=0;run(20);
for(unsigned i=1;i<=40;i++){
 press();run(100);
 unsigned expected=i%4;
 if(d.p_cur__img__idx.get<unsigned>()!=expected||requests!=i+1)throw std::runtime_error("Mixed cached sector/index or lost next request");
 unsigned bank=d.p_disp__buf__idx.get<unsigned>();
 unsigned ws[]={1,3,333,640},hs[]={1,5,221,480};
 if(d.p_disp__bmp__width.get<unsigned>()!=ws[expected]||d.p_disp__bmp__height.get<unsigned>()!=hs[expected])throw std::runtime_error("Mixed frame dimensions");
 // Queue another NEXT during the transition while reader still owns old bank.
 press();unsigned before=requests;run(500);
 if(requests!=before)throw std::runtime_error("Queued NEXT ignored reader ownership");
 owned=bank;run(200); // Memory reader accepted new bank; queued request may proceed.
 i++;expected=i%4;
 if(requests!=i+1||d.p_cur__img__idx.get<unsigned>()!=expected)throw std::runtime_error("Handoff did not resume queued NEXT");
 owned=d.p_disp__buf__idx.get<unsigned>();run(20);frames+=2;
}
// Reset discards ownership and partial requests, restoring first-image boot.
d.p_rst.set(true);valid=false;pending=0;previous=false;finish=false;run(10);unsigned before=requests;d.p_rst.set(false);run(200);
if(requests!=before+1||d.p_cur__img__idx.get<unsigned>()!=0)throw std::runtime_error("Reset boot failed");
std::cout<<"PASS bank_lifecycle: "<<frames<<" mixed-size commits, queued NEXT held until actual reader handoff, cached sector/index consistency and reset; SD transport/BMP parser mocked only\n";
}catch(const std::exception&e){std::cerr<<e.what()<<"\n";return 1;}}
