#include "sd_command_equivalence.cc"
#include <iostream>
#include <stdexcept>
using namespace cxxrtl_design;
int main(){p_sd__command__equivalence d;unsigned clocks=0,bytes=0,seed=7;bool error_seen=false;
auto tick=[&](){d.p_sys__clk.set(false);d.step();if(d.p_mismatch.get<bool>())throw std::runtime_error("SD protocol combinational mismatch");d.p_sys__clk.set(true);d.step();d.step();if(d.p_mismatch.get<bool>())throw std::runtime_error("SD protocol sequential mismatch");if(d.p_ref__error.get<bool>())error_seen=true;++clocks;};
auto transfer=[&](unsigned value){d.p_spi__data__out.set(value);d.p_spi__wr__ack.set(false);tick();tick();d.p_spi__wr__ack.set(true);tick();d.p_spi__wr__ack.set(false);tick();++bytes;};
auto reset=[&](){d.p_rst.set(true);d.p_cmd__req.set(false);d.p_block__read__req.set(false);d.p_block__write__req.set(false);tick();d.p_rst.set(false);tick();for(int i=0;i<12;++i)transfer(255);error_seen=false;};
d.p_spi__clk__div.set(4);d.p_cmd__r1.set(1);d.p_cmd.set(0x400000000095ull);
reset();
// Complete sector plus CRC, followed by timeout and reset recovery.
d.p_block__read__req.set(true);tick();d.p_block__read__req.set(false);transfer(0xfe);unsigned valid=0;
for(unsigned i=0;i<514;++i){d.p_spi__data__out.set(i&255);d.p_spi__wr__ack.set(false);tick();tick();d.p_spi__wr__ack.set(true);tick();if(d.p_ref__block__valid.get<bool>())++valid;d.p_spi__wr__ack.set(false);tick();}
if(valid!=512)throw std::runtime_error("Expected exactly 512 sector bytes");
reset();d.p_block__read__req.set(true);tick();d.p_block__read__req.set(false);for(unsigned i=0;i<50002;++i)transfer(255);if(!error_seen)throw std::runtime_error("Read token timeout not reported");
// Long command data exercises every nibble carry, high-byte carry and maximum length.
for(unsigned length:{1u,255u,256u,4096u,65535u}){reset();d.p_cmd__data__len.set(length);d.p_cmd__req.set(true);tick();d.p_cmd__req.set(false);for(unsigned i=0;i<7;++i)transfer(255);transfer(1);for(unsigned i=0;i<length;++i)transfer((i*37)&255);}
// Response timeout reaches 0xffff without overflow changing the command contract.
reset();d.p_cmd__data__len.set(0);d.p_cmd__req.set(true);tick();d.p_cmd__req.set(false);for(unsigned i=0;i<65538;++i)transfer(255);
// Arbitrary reset and SPI acknowledgement patterns verify exact cycle behaviour.
for(unsigned i=0;i<200000;++i){seed=seed*1664525u+1013904223u;d.p_rst.set(i%4096==0);d.p_spi__wr__ack.set(seed&1);d.p_spi__data__out.set(seed>>24);d.p_cmd__req.set((seed&255)==4);d.p_block__read__req.set((seed&255)==9);d.p_block__write__req.set((seed&255)==16);d.p_block__write__data.set(seed>>16);tick();}
std::cout<<"PASS SD command equivalence: "<<clocks<<" clocks, "<<bytes<<" SPI transfers, exact old/new outputs, 512-byte sector, carries, long responses, timeouts and reset recovery\n";
}
