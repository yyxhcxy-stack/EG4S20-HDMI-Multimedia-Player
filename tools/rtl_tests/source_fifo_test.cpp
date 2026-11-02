#include "source_fifo.cc"
#include <deque>
#include <iostream>
using namespace cxxrtl_design;
int main(){
 p_scaling__source__fifo d;std::deque<unsigned> expected;unsigned seed=1,checks=0;bool overflow=false;
 auto tick=[&](){d.p_clk.set(false);d.step();d.p_clk.set(true);d.step();d.step();};
 d.p_aclr.set(true);tick();d.p_aclr.set(false);
 for(unsigned c=0;c<12000;++c){
  seed=seed*1664525u+1013904223u;
  bool clear=c==6000,wr=c<514||(c>=1200&&(seed&1)),rd=(c>=514&&c<1200)||(c>=1200&&(seed&8));
  if(clear){expected.clear();overflow=false;}
  bool pop=rd&&!expected.empty()&&!clear,push=wr&&expected.size()<512&&!clear;unsigned front=pop?expected.front():0;
  if(pop)expected.pop_front();if(push)expected.push_back(seed);if(wr&&!push&&!clear)overflow=true;
  d.p_aclr.set(clear);d.p_write__valid.set(wr);d.p_read__enable.set(rd);d.p_write__data.set(seed);tick();
  if((pop&&d.p_read__data.get<unsigned>()!=front)||d.p_used__words.get<unsigned>()!=expected.size()||d.p_empty.get<bool>()!=expected.empty()||d.p_overflow.get<bool>()!=overflow){std::cerr<<"Source FIFO mismatch cycle="<<c<<"\n";return 1;}++checks;
 }
 std::cout<<"PASS source FIFO: "<<checks<<" cycles, capacity 512, empty/full requests, simultaneous read/write, wraparound, overflow and reset\n";
}
