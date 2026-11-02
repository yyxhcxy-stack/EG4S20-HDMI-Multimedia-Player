#include "cdc_reset.cc"
#include <iostream>
#include <deque>
using namespace cxxrtl_design;
int main(){p_cdc__reset d; unsigned delivered=0;
for(unsigned phase=0;phase<17;phase++){
 std::deque<unsigned> expected; unsigned sequence=0;bool prevdst=false;
 for(unsigned n=0;n<30000;n++){
  bool reset=n<19||(n>=10000&&n<10017)||(n>=20000&&n<20004)||(n>=24904&&n<24908);
  // Stop destination through a reset release and vary asynchronous phase.
  bool dst=(n>=9900&&n<10200)?false:((n+phase)%14<7);
  bool src=n%10<5;
  d.p_rst.set(reset);d.p_srcclk.set(src);d.p_dstclk.set(dst);d.p_send.set(false);
  if(reset)expected.clear();
  if(!reset&&n%400==100){++sequence;d.p_data=cxxrtl::value<80>{sequence,sequence^0xa5a5f00du,sequence&65535};d.p_send.set(true);}
  if(!reset&&src&&n%10==0&&d.p_send.get<bool>()&&(d.p_c_2e_src__release.get<unsigned>()&4)==0&&d.p_c_2e_ack__sync.get<unsigned>()/2==d.p_c_2e_request.get<unsigned>())expected.push_back(sequence);
  d.step();d.step();
  // send is a pulse at rising source; payload is unchanged until next send.
  if(dst&&!prevdst&&d.p_valid.get<bool>()&&!reset){
   unsigned got=d.p_result.data[0];
   if(expected.empty()||got!=expected.front()||d.p_result.data[1]!=(got^0xa5a5f00du)||d.p_result.data[2]!=(got&65535)){std::cerr<<"CDC stale/mixed/lost payload phase="<<phase<<" n="<<n<<" got="<<got<<" queue="<<expected.size()<<"\n";return 1;}
   expected.pop_front();delivered++;
  }
  if(reset&&d.p_valid.get<bool>()){std::cerr<<"Valid during reset\n";return 1;}
  prevdst=dst;
 }
}
if(delivered<1000)return 1;std::cout<<"PASS cdc_reset: 17 asynchronous phases, "<<delivered<<" atomic payloads; stopped clock, asynchronous assertion, synchronized release, mid-transaction resets, no stale results\n";
}
