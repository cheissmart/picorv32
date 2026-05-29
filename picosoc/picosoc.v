/*
 *  PicoSoC - A simple example SoC using PicoRV32
 *
 *  Copyright (C) 2017  Claire Xenia Wolf <claire@yosyshq.com>
 *
 *  Permission to use, copy, modify, and/or distribute this software for any
 *  purpose with or without fee is hereby granted, provided that the above
 *  copyright notice and this permission notice appear in all copies.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 *  WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 *  MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 *  ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 *  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 *  ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 *  OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 */

`ifndef PICORV32_REGS
`ifdef PICORV32_V
`error "picosoc.v must be read before picorv32.v!"
`endif

`define PICORV32_REGS picosoc_regs
`endif

`ifndef PICOSOC_MEM
`define PICOSOC_MEM picosoc_mem
`endif

// this macro can be used to check if the verilog files in your
// design are read in the correct order.
`define PICOSOC_V

module picosoc (
	input clk,
	input resetn,

	output        iomem_valid,
	input         iomem_ready,
	output [ 3:0] iomem_wstrb,
	output [31:0] iomem_addr,
	output [31:0] iomem_wdata,
	input  [31:0] iomem_rdata,

	input  irq_5,
	input  irq_6,
	input  irq_7,

	output ser_tx,
	input  ser_rx,

	output flash_csb,
	output flash_clk,

	output flash_io0_oe,
	output flash_io1_oe,
	output flash_io2_oe,
	output flash_io3_oe,

	output flash_io0_do,
	output flash_io1_do,
	output flash_io2_do,
	output flash_io3_do,

	input  flash_io0_di,
	input  flash_io1_di,
	input  flash_io2_di,
	input  flash_io3_di
);
	parameter [0:0] BARREL_SHIFTER = 1;
	parameter [0:0] ENABLE_MUL = 1;
	parameter [0:0] ENABLE_DIV = 1;
	parameter [0:0] ENABLE_FAST_MUL = 0;
	parameter [0:0] ENABLE_COMPRESSED = 1;
	parameter [0:0] ENABLE_COUNTERS = 1;
	parameter [0:0] ENABLE_IRQ_QREGS = 0;

	parameter integer MEM_WORDS = 256;
	parameter [31:0] STACKADDR = (4*MEM_WORDS);       // end of memory
	parameter [31:0] PROGADDR_RESET = 32'h 0010_0000; // 1 MB into flash
	parameter [31:0] PROGADDR_IRQ = 32'h 0000_0000;

	reg [31:0] irq;
	wire irq_stall = 0;
	wire irq_uart = 0;

	always @* begin
		irq = 0;
		irq[3] = irq_stall;
		irq[4] = irq_uart;
		irq[5] = irq_5;
		irq[6] = irq_6;
		irq[7] = irq_7;
	end

	wire mem_valid;
	wire mem_instr;
	wire mem_ready;
	wire [31:0] mem_addr;
	wire [31:0] mem_wdata;
	wire [3:0] mem_wstrb;
	wire [31:0] mem_rdata;

	wire spimem_ready;
	wire [31:0] spimem_rdata;

	wire spimem_cache_valid;
	wire spimem_cache_ready;
	wire [23:0] spimem_cache_addr;
	wire [31:0] spimem_cache_rdata;

	reg ram_ready;
	wire [31:0] ram_rdata;

	assign iomem_valid = mem_valid && (mem_addr[31:24] > 8'h 01);
	assign iomem_wstrb = mem_wstrb;
	assign iomem_addr = mem_addr;
	assign iomem_wdata = mem_wdata;

	wire spimemio_cfgreg_sel = mem_valid && (mem_addr == 32'h 0200_0000);
	wire [31:0] spimemio_cfgreg_do;

	wire        simpleuart_reg_div_sel = mem_valid && (mem_addr == 32'h 0200_0004);
	wire [31:0] simpleuart_reg_div_do;

	wire        simpleuart_reg_dat_sel = mem_valid && (mem_addr == 32'h 0200_0008);
	wire [31:0] simpleuart_reg_dat_do;
	wire        simpleuart_reg_dat_wait;

	assign mem_ready = (iomem_valid && iomem_ready) || spimem_cache_ready || ram_ready || spimemio_cfgreg_sel ||
			simpleuart_reg_div_sel || (simpleuart_reg_dat_sel && !simpleuart_reg_dat_wait);

	assign mem_rdata = (iomem_valid && iomem_ready) ? iomem_rdata : spimem_cache_ready ? spimem_cache_rdata : ram_ready ? ram_rdata :
			spimemio_cfgreg_sel ? spimemio_cfgreg_do : simpleuart_reg_div_sel ? simpleuart_reg_div_do :
			simpleuart_reg_dat_sel ? simpleuart_reg_dat_do : 32'h 0000_0000;

	picorv32 #(
		.STACKADDR(STACKADDR),
		.PROGADDR_RESET(PROGADDR_RESET),
		.PROGADDR_IRQ(PROGADDR_IRQ),
		.BARREL_SHIFTER(BARREL_SHIFTER),
		.COMPRESSED_ISA(ENABLE_COMPRESSED),
		.ENABLE_COUNTERS(ENABLE_COUNTERS),
		.ENABLE_MUL(ENABLE_MUL),
		.ENABLE_DIV(ENABLE_DIV),
		.ENABLE_FAST_MUL(ENABLE_FAST_MUL),
		.ENABLE_IRQ(1),
		.ENABLE_IRQ_QREGS(ENABLE_IRQ_QREGS)
	) cpu (
		.clk         (clk        ),
		.resetn      (resetn     ),
		.mem_valid   (mem_valid  ),
		.mem_instr   (mem_instr  ),
		.mem_ready   (mem_ready  ),
		.mem_addr    (mem_addr   ),
		.mem_wdata   (mem_wdata  ),
		.mem_wstrb   (mem_wstrb  ),
		.mem_rdata   (mem_rdata  ),
		.irq         (irq        )
	);

	spimem_cache_direct_mapped spimem_cache (
		.clk           (clk),
		.resetn        (resetn),

		.cpu_valid     (mem_valid && mem_addr >= 4*MEM_WORDS && mem_addr < 32'h 0200_0000),
		.cpu_ready     (spimem_cache_ready),
		.cpu_addr      (mem_addr[23:0]),
		.cpu_rdata     (spimem_cache_rdata),

		.spimem_valid  (spimem_cache_valid),
		.spimem_ready  (spimem_ready),
		.spimem_addr   (spimem_cache_addr),
		.spimem_rdata  (spimem_rdata)
	);

	spimemio spimemio (
		.clk    (clk),
		.resetn (resetn),
		.valid  (spimem_cache_valid),
		.ready  (spimem_ready),
		.addr   (spimem_cache_addr),
		.rdata  (spimem_rdata),

		.flash_csb    (flash_csb   ),
		.flash_clk    (flash_clk   ),

		.flash_io0_oe (flash_io0_oe),
		.flash_io1_oe (flash_io1_oe),
		.flash_io2_oe (flash_io2_oe),
		.flash_io3_oe (flash_io3_oe),

		.flash_io0_do (flash_io0_do),
		.flash_io1_do (flash_io1_do),
		.flash_io2_do (flash_io2_do),
		.flash_io3_do (flash_io3_do),

		.flash_io0_di (flash_io0_di),
		.flash_io1_di (flash_io1_di),
		.flash_io2_di (flash_io2_di),
		.flash_io3_di (flash_io3_di),

		.cfgreg_we(spimemio_cfgreg_sel ? mem_wstrb : 4'b 0000),
		.cfgreg_di(mem_wdata),
		.cfgreg_do(spimemio_cfgreg_do)
	);

	simpleuart simpleuart (
		.clk         (clk         ),
		.resetn      (resetn      ),

		.ser_tx      (ser_tx      ),
		.ser_rx      (ser_rx      ),

		.reg_div_we  (simpleuart_reg_div_sel ? mem_wstrb : 4'b 0000),
		.reg_div_di  (mem_wdata),
		.reg_div_do  (simpleuart_reg_div_do),

		.reg_dat_we  (simpleuart_reg_dat_sel ? mem_wstrb[0] : 1'b 0),
		.reg_dat_re  (simpleuart_reg_dat_sel && !mem_wstrb),
		.reg_dat_di  (mem_wdata),
		.reg_dat_do  (simpleuart_reg_dat_do),
		.reg_dat_wait(simpleuart_reg_dat_wait)
	);

	always @(posedge clk)
		ram_ready <= mem_valid && !mem_ready && mem_addr < 4*MEM_WORDS;

	`PICOSOC_MEM #(
		.WORDS(MEM_WORDS)
	) memory (
		.clk(clk),
		.wen((mem_valid && !mem_ready && mem_addr < 4*MEM_WORDS) ? mem_wstrb : 4'b0),
		.addr(mem_addr[23:2]),
		.wdata(mem_wdata),
		.rdata(ram_rdata)
	);
endmodule

// This is a simple cache that forwards read requests from the CPU to the SPI flash.
module spimem_cache_forward (
	input clk,
	input resetn,

	input         cpu_valid, // request from CPU to read data
	output        cpu_ready, // data is ready to be read by the CPU
	input  [23:0] cpu_addr,	// address to read from
	output [31:0] cpu_rdata, // data read by the CPU

	output        spimem_valid, // request read from SPI flash
	input         spimem_ready, // SPI flash is ready with data
	output [23:0] spimem_addr, // address to read from SPI flash
	input  [31:0] spimem_rdata // data read from SPI flash
);
	wire cache_hit = 1'b0;

	assign spimem_valid = cpu_valid && !cache_hit;
	assign spimem_addr = cpu_addr;

	assign cpu_ready = cpu_valid && (cache_hit || spimem_ready);
	assign cpu_rdata = cache_hit ? 32'h 0000_0000 : spimem_rdata;
endmodule

module spimem_cache_direct_mapped #(
	parameter integer CACHE_SIZE = 8, // number of cache lines
	parameter integer LINE_SIZE = 1   // number of words per cache line
) ( 
	input clk,
	input resetn,

	input         cpu_valid, // request from CPU to read data
	output        cpu_ready, // data is ready to be read by the CPU
	input  [23:0] cpu_addr,	// address to read from
	output [31:0] cpu_rdata, // data read by the CPU

	output        spimem_valid, // request read from SPI flash
	input         spimem_ready, // SPI flash is ready with data
	output [23:0] spimem_addr, // address to read from SPI flash
	input  [31:0] spimem_rdata // data read from SPI flash
);
	localparam integer CACHE_WORDS = CACHE_SIZE * LINE_SIZE;

	reg [31:0] cache_line_addr [0:CACHE_SIZE-1];
	reg [31:0] cache_data [0:CACHE_WORDS-1];
	reg cache_valid [0:CACHE_SIZE-1];

	reg fill_active;
	reg [31:0] fill_line_addr;
	reg [31:0] fill_index;
	reg [31:0] fill_count;

	wire [31:0] cpu_word_addr = cpu_addr[23:2];
	wire [31:0] cpu_line_addr = cpu_word_addr / LINE_SIZE;
	wire [31:0] cpu_index = cpu_line_addr % CACHE_SIZE;
	wire [31:0] cpu_offset = cpu_word_addr % LINE_SIZE;
	wire [31:0] cpu_cache_word = cpu_index * LINE_SIZE + cpu_offset;

	wire cache_hit = cache_valid[cpu_index] && (cache_line_addr[cpu_index] == cpu_line_addr);

	wire start_fill = cpu_valid && !cache_hit && !fill_active;
	wire [31:0] fill_cur_line_addr = fill_active ? fill_line_addr : cpu_line_addr;
	wire [31:0] fill_cur_index = fill_active ? fill_index : cpu_index;
	wire [31:0] fill_cur_count = fill_active ? fill_count : 0;
	wire [31:0] fill_cur_cache_word = fill_cur_index * LINE_SIZE + fill_cur_count;
	wire [31:0] fill_cur_spimem_word_addr = fill_cur_line_addr * LINE_SIZE + fill_cur_count;

	assign spimem_valid = fill_active || start_fill;
	assign spimem_addr = {fill_cur_spimem_word_addr[21:0], 2'b00};

	integer i;
	always @(posedge clk) begin
		if (!resetn) begin
			fill_active <= 1'b0;
			for (i = 0; i < CACHE_SIZE; i = i + 1)
				cache_valid[i] <= 1'b0;
		end else begin
			if (start_fill)
				cache_valid[cpu_index] <= 1'b0;

			if (spimem_valid && spimem_ready) begin
				cache_data[fill_cur_cache_word] <= spimem_rdata;

				if (fill_cur_count == LINE_SIZE-1) begin
					cache_line_addr[fill_cur_index] <= fill_cur_line_addr;
					cache_valid[fill_cur_index] <= 1'b1;
					fill_active <= 1'b0;
				end else begin
					fill_active <= 1'b1;
					fill_line_addr <= fill_cur_line_addr;
					fill_index <= fill_cur_index;
					fill_count <= fill_cur_count + 1;
				end
			end else if (start_fill) begin
				fill_active <= 1'b1;
				fill_line_addr <= cpu_line_addr;
				fill_index <= cpu_index;
				fill_count <= 0;
			end
		end
	end

	assign cpu_ready = cpu_valid && (cache_hit ||
			(spimem_valid && spimem_ready && fill_cur_count == LINE_SIZE-1));
	assign cpu_rdata = cache_hit ? cache_data[cpu_cache_word] :
			(cpu_offset == fill_cur_count ? spimem_rdata : cache_data[cpu_cache_word]);
endmodule


// Implementation note:
// Replace the following two modules with wrappers for your SRAM cells.

module picosoc_regs (
	input clk, wen,
	input [5:0] waddr,
	input [5:0] raddr1,
	input [5:0] raddr2,
	input [31:0] wdata,
	output [31:0] rdata1,
	output [31:0] rdata2
);
	reg [31:0] regs [0:31];

	always @(posedge clk)
		if (wen) regs[waddr[4:0]] <= wdata;

	assign rdata1 = regs[raddr1[4:0]];
	assign rdata2 = regs[raddr2[4:0]];
endmodule

module picosoc_mem #(
	parameter integer WORDS = 256
) (
	input clk,
	input [3:0] wen,
	input [21:0] addr,
	input [31:0] wdata,
	output reg [31:0] rdata
);
	reg [31:0] mem [0:WORDS-1];

	always @(posedge clk) begin
		rdata <= mem[addr];
		if (wen[0]) mem[addr][ 7: 0] <= wdata[ 7: 0];
		if (wen[1]) mem[addr][15: 8] <= wdata[15: 8];
		if (wen[2]) mem[addr][23:16] <= wdata[23:16];
		if (wen[3]) mem[addr][31:24] <= wdata[31:24];
	end
endmodule
