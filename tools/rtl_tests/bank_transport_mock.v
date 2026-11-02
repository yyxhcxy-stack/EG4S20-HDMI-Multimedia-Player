// Controller lifecycle test mock, not a physical SD/BMP model.
module bmp_read(
    input                       clk,
    input                       rst,
    output                      ready,

    // 上电扫描：从 scan_start_sector 开始，顺序寻找前 scan_target_count 张 BMP
    input                       scan_start,
    input  [31:0]               scan_start_sector,
    input  [31:0]               scan_max_sector,
    input  [3:0]                scan_target_count,
    output reg                  scan_done,
    output reg                  scan_found_valid,
    output reg [31:0]           scan_found_sector,
    output reg [3:0]            scan_found_total,

    // 按指定扇区加载一张图到 SDRAM
    input                       load_start,
    input  [31:0]               load_sector,
    input                       load_abort,
    output reg                  load_done,

    input                       sd_init_done,
    output reg [3:0]            state_code,
    input  [15:0]               bmp_width,
    input  [15:0]               bmp_height,
    output reg [15:0]           bmp_orig_width,
    output reg [15:0]           bmp_orig_height,

    output reg                  write_req,
    input                       write_req_ack,

    output reg                  sd_sec_read,
    output reg [31:0]           sd_sec_read_addr,
    input  [7:0]                sd_sec_read_data,
    input                       sd_sec_read_data_valid,
    input                       sd_sec_read_end,

    output reg                  bmp_data_wr_en,
    output reg [23:0]           bmp_data
);
reg [3:0] scan_n; reg [7:0] delay_n; reg busy;
assign ready = !busy && scan_n==0;
always @(posedge clk or posedge rst) begin
 if(rst) begin scan_n<=0;busy<=0;delay_n<=0;scan_done<=0;scan_found_valid<=0;scan_found_sector<=0;scan_found_total<=0;load_done<=0;write_req<=0;state_code<=0;bmp_orig_width<=0;bmp_orig_height<=0;sd_sec_read<=0;sd_sec_read_addr<=0;bmp_data_wr_en<=0;bmp_data<=0;end
 else begin
 scan_done<=0;scan_found_valid<=0;load_done<=0;
 if(scan_start)scan_n<=1;
 else if(scan_n!=0) begin
   if(scan_n<=4)begin scan_found_valid<=1;scan_found_sector<=scan_n*1000;scan_found_total<=scan_n;scan_n<=scan_n+1;end
   else begin scan_n<=0;scan_done<=1;end
 end
 if(load_start)begin busy<=1;write_req<=1;sd_sec_read_addr<=load_sector;delay_n<=0;
 case(load_sector)
 1000:begin bmp_orig_width<=1;bmp_orig_height<=1;end
 2000:begin bmp_orig_width<=3;bmp_orig_height<=5;end
 3000:begin bmp_orig_width<=333;bmp_orig_height<=221;end
 4000:begin bmp_orig_width<=640;bmp_orig_height<=480;end
 default:begin bmp_orig_width<=0;bmp_orig_height<=0;end endcase end
 if(busy)begin
 if(write_req_ack)begin write_req<=0;delay_n<=1;end
 else if(delay_n!=0)begin if(delay_n==8)begin busy<=0;load_done<=1;delay_n<=0;end else delay_n<=delay_n+1;end
 end
 if(load_abort)begin busy<=0;write_req<=0;delay_n<=0;end
 end
end
endmodule

module sd_card_top
#(
	parameter  SPI_LOW_SPEED_DIV = 248,         // SD card low speed mode frequency division parameter,spi clk speed = clk speed /((SPI_LOW_SPEED_DIV + 2) * 2 )
	parameter  SPI_HIGH_SPEED_DIV = 0           // SD card high speed mode frequency division parameter,spi clk speed = clk speed /((SPI_HIGH_SPEED_DIV + 2) * 2 )
)
(
	input            clk,
	input            rst,
	output           SD_nCS,                    //SD card chip select (SPI mode)
	output           SD_DCLK,                   //SD card clock
	output           SD_MOSI,                   //SD card controller data output
	input            SD_MISO,                   //SD card controller data input
	output           sd_init_done,              //SD card initialization is complete
	input            sd_sec_read,               //SD card sector read
	input[31:0]      sd_sec_read_addr,          //SD card sector read address
	output[7:0]      sd_sec_read_data,          //SD card sector read data
	output           sd_sec_read_data_valid,    //SD card sector read data valid
	output           sd_sec_read_end,           //SD card sector read end
	input            sd_sec_write,              //SD card sector write
	input[31:0]      sd_sec_write_addr,         //SD card sector write address
	input[7:0]       sd_sec_write_data,         //SD card sector write data
	output           sd_sec_write_data_req,     //SD card sector write data next clock is valid
	output           sd_sec_write_end           //SD card sector write end
);
assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=1;assign sd_init_done=SD_MISO;
assign sd_sec_read_data=0;assign sd_sec_read_data_valid=0;assign sd_sec_read_end=0;
assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
endmodule
