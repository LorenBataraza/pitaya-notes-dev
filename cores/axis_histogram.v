`timescale 1 ns / 1 ps

module axis_histogram #
(
  parameter integer AXIS_TDATA_WIDTH = 16,    // Width of input data bus in bits
  parameter integer BRAM_DATA_WIDTH = 32,     // Width of BRAM data (bin count values)
  parameter integer BRAM_ADDR_WIDTH = 14      // Width of BRAM address (determines number of bins: 2^14 = 16384 bins)
)
(
  // System signals
  input  wire                         aclk,     // System clock
  input  wire                         aresetn,  // System reset (active low)

  // Slave side (AXI Stream input)
  input  wire [AXIS_TDATA_WIDTH-1:0]  s_axis_tdata,  // Input data value (becomes bin address)
  input  wire                         s_axis_tvalid, // Input data valid signal
  output wire                         s_axis_tready, // Ready to accept new data

  // BRAM port (Block RAM interface for histogram storage)
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 b_bram CLK" *)
  output wire                         b_bram_clk,    // BRAM clock
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 b_bram RST" *)
  output wire                         b_bram_rst,    // BRAM reset
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 b_bram EN" *)
  output wire                         b_bram_en,     // BRAM enable
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 b_bram WE" *)
  output wire [BRAM_DATA_WIDTH/8-1:0] b_bram_we,     // BRAM write enable (byte-wise)
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 b_bram ADDR" *)
  output wire [BRAM_ADDR_WIDTH-1:0]   b_bram_addr,   // BRAM address (bin index)
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 b_bram DIN" *)
  output wire [BRAM_DATA_WIDTH-1:0]   b_bram_wdata,  // BRAM write data (updated bin count)
  (* X_INTERFACE_INFO = "xilinx.com:interface:bram:1.0 b_bram DOUT" *)
  input  wire [BRAM_DATA_WIDTH-1:0]   b_bram_rdata   // BRAM read data (current bin count)
);

  // Internal registers for FSM and data processing
  reg [BRAM_ADDR_WIDTH-1:0] int_addr_reg, int_addr_next;  // BRAM address register (bin index)
  reg [BRAM_DATA_WIDTH-1:0] int_data_reg, int_data_next;  // BRAM data register (updated count)
  reg [1:0] int_case_reg, int_case_next;                  // FSM state register (3 states)
  reg int_tready_reg, int_tready_next;                    // Ready signal register
  reg int_we_reg, int_we_next;                            // Write enable register

  // Sequential always block: Register updates on clock edges
  always @(posedge aclk)
  begin
    if(~aresetn)  // Active low reset: initialize all registers
    begin
      int_addr_reg <= {(BRAM_ADDR_WIDTH){1'b0}};  // Clear address register
      int_data_reg <= {(BRAM_DATA_WIDTH){1'b0}};  // Clear data register
      int_case_reg <= 2'd0;                       // Reset to state 0
      int_tready_reg <= 1'b1;                     // Ready to accept data initially
      int_we_reg <= 1'b0;                         // Disable BRAM write
    end
    else  // Normal operation: update registers with next values
    begin
      int_addr_reg <= int_addr_next;
      int_data_reg <= int_data_next;
      int_case_reg <= int_case_next;
      int_tready_reg <= int_tready_next;
      int_we_reg <= int_we_next;
    end
  end

  always @*
  begin
    // Default: maintain current values (infer latches)
    int_addr_next = int_addr_reg;
    int_data_next = int_data_reg;
    int_case_next = int_case_reg;
    int_tready_next = int_tready_reg;
    int_we_next = int_we_reg;

    // Finite State Machine with 3 states
    case(int_case_reg)
      2'd0:  // STATE 0: Wait for new input data
      begin
        if(s_axis_tvalid)  // When valid data arrives
        begin
          int_addr_next = s_axis_tdata[BRAM_ADDR_WIDTH-1:0];  // Use input data as bin address
          int_tready_next = 1'b0;      // Not ready during processing
          int_case_next = 2'd1;        // Move to read state
        end
      end
      
      2'd1:  // STATE 1: Read current bin count and prepare update
      begin
        // Increment the current bin count (read from BRAM)
        int_data_next = b_bram_rdata + 1'b1;
        
        // Set write enable only if current count is not at maximum (all 1s)
        // This prevents overflow by stopping at maximum value
        int_we_next = ~&b_bram_rdata;  // ~& is NOR reduction: 1 only if not all bits are 1
        
        int_case_next = 2'd2;  // Move to write state
      end
      
      2'd2:  // STATE 2: Complete the write operation
      begin
        int_tready_next = 1'b1;  // Ready for next input
        int_we_next = 1'b0;      // Disable BRAM write
        int_case_next = 2'd0;    // Return to idle state
      end
    endcase
  end

  // AXI Stream interface assignments
  assign s_axis_tready = int_tready_reg;  // Control when module can accept new data

  // BRAM interface assignments
  assign b_bram_clk = aclk;       // BRAM shares system clock
  assign b_bram_rst = ~aresetn;   // BRAM reset (active high)
  
  // BRAM enable: active during read or write operations
  assign b_bram_en = int_we_reg | s_axis_tvalid;
  
  // BRAM write enable: byte-wise enable signals (all bytes when writing)
  assign b_bram_we = {(BRAM_DATA_WIDTH/8){int_we_reg}};
  
  // BRAM address: use registered address during writes, input data during reads
  assign b_bram_addr = int_we_reg ? int_addr_reg : s_axis_tdata[BRAM_ADDR_WIDTH-1:0];
  
  // BRAM write data: updated bin count
  assign b_bram_wdata = int_data_reg;

endmodule
