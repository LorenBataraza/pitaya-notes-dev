`timescale 1 ns / 1 ps

module axis_pulse_height_analyzer #
(
  parameter integer AXIS_TDATA_WIDTH = 16,    // Width of data bus in bits
  parameter         AXIS_TDATA_SIGNED = "FALSE", // Data format: "TRUE" for signed, "FALSE" for unsigned
  parameter integer CNTR_WIDTH = 16           // Width of internal counter
)
(
  // System signals
  input  wire                           aclk,      // System clock
  input  wire                           aresetn,   // System reset (active low)

  // Configuration inputs
  input  wire [CNTR_WIDTH-1:0]          cfg_data,  // Delay counter threshold value
  input  wire [AXIS_TDATA_WIDTH-1:0]    min_data,  // Minimum pulse height threshold
  input  wire [AXIS_TDATA_WIDTH-1:0]    max_data,  // Maximum pulse height threshold

  // Slave side (AXI Stream input)
  output wire                           s_axis_tready,  // Always ready to accept data
  input  wire [AXIS_TDATA_WIDTH-1:0]    s_axis_tdata,   // Input data stream
  input  wire                           s_axis_tvalid,  // Input data valid signal

  // Master side (AXI Stream output)
  input  wire                           m_axis_tready,  // Output ready signal from downstream
  output wire [AXIS_TDATA_WIDTH-1:0]    m_axis_tdata,   // Output pulse height data
  output wire                           m_axis_tvalid   // Output data valid signal
);

  // Internal registers for storing intermediate values
  reg [AXIS_TDATA_WIDTH-1:0] int_data_reg[1:0], int_data_next[1:0]; // Data pipeline: [0]=current, [1]=previous sample
  reg [AXIS_TDATA_WIDTH-1:0] int_min_reg, int_min_next;             // Minimum value (pulse baseline)
  reg [AXIS_TDATA_WIDTH-1:0] int_tdata_reg, int_tdata_next;         // Output data register
  reg [CNTR_WIDTH-1:0] int_cntr_reg, int_cntr_next;                 // Delay counter
  reg int_enbl_reg, int_enbl_next;                                  // Measurement enable flag
  reg int_rising_reg, int_rising_next;                              // Rising edge detection register
  reg int_tvalid_reg, int_tvalid_next;                              // Output valid register

  // Internal combinatorial signals
  wire [AXIS_TDATA_WIDTH-1:0] int_tdata_wire; // Calculated pulse height (peak - baseline)
  wire int_mincut_wire;      // Flag: pulse height > minimum threshold
  wire int_maxcut_wire;      // Flag: pulse height < maximum threshold  
  wire int_rising_wire;      // Current rising edge detection
  wire int_delay_wire;       // Flag: delay counter active

  // Delay counter check: true when counter hasn't reached cfg_data
  assign int_delay_wire = int_cntr_reg < cfg_data;

  // Generate blocks for signed/unsigned data handling
  generate
    if(AXIS_TDATA_SIGNED == "TRUE")
    begin : SIGNED
      // Signed data operations
      assign int_rising_wire = $signed(int_data_reg[1]) < $signed(s_axis_tdata); // Rising edge detection
      assign int_tdata_wire = $signed(int_data_reg[0]) - $signed(int_min_reg);   // Pulse height calculation
      assign int_mincut_wire = $signed(int_tdata_wire) > $signed(min_data);      // Min threshold check
      assign int_maxcut_wire = $signed(int_tdata_wire) < $signed(max_data);      // Max threshold check
    end
    else
    begin : UNSIGNED
      // Unsigned data operations  
      assign int_rising_wire = int_data_reg[1] < s_axis_tdata;     // Rising edge detection
      assign int_tdata_wire = int_data_reg[0] - int_min_reg;       // Pulse height calculation
      assign int_mincut_wire = int_tdata_wire > min_data;          // Min threshold check
      assign int_maxcut_wire = int_tdata_wire < max_data;          // Max threshold check
    end
  endgenerate

  // Sequential always block: Register updates on clock edges
  always @(posedge aclk)
  begin
    if(~aresetn)  // Active low reset: initialize all registers
    begin
      int_data_reg[0] <= {(AXIS_TDATA_WIDTH){1'b0}};  // Clear data pipeline
      int_data_reg[1] <= {(AXIS_TDATA_WIDTH){1'b0}};
      int_tdata_reg <= {(AXIS_TDATA_WIDTH){1'b0}};    // Clear output data
      int_min_reg <= {(AXIS_TDATA_WIDTH){1'b0}};      // Clear minimum register
      int_cntr_reg <= {(CNTR_WIDTH){1'b0}};           // Clear delay counter
      int_enbl_reg <= 1'b0;                           // Disable measurement
      int_rising_reg <= 1'b0;                         // Clear rising edge flag
      int_tvalid_reg <= 1'b0;                         // Clear output valid
    end
    else  // Normal operation: update registers with next values
    begin
      int_data_reg[0] <= int_data_next[0];
      int_data_reg[1] <= int_data_next[1];
      int_tdata_reg <= int_tdata_next;
      int_min_reg <= int_min_next;
      int_cntr_reg <= int_cntr_next;
      int_enbl_reg <= int_enbl_next;
      int_rising_reg <= int_rising_next;
      int_tvalid_reg <= int_tvalid_next;
    end
  end

  // Combinatorial always block: Next state logic
  always @*
  begin
    // Default: maintain current values (infer latches)
    int_data_next[0] = int_data_reg[0];
    int_data_next[1] = int_data_reg[1];
    int_tdata_next = int_tdata_reg;
    int_min_next = int_min_reg;
    int_cntr_next = int_cntr_reg;
    int_enbl_next = int_enbl_reg;
    int_rising_next = int_rising_reg;
    int_tvalid_next = int_tvalid_reg;

    // Shift new data into the pipeline when valid input arrives
    if(s_axis_tvalid)
    begin
      int_data_next[0] = s_axis_tdata;        // Current sample -> pipeline[0]
      int_data_next[1] = int_data_reg[0];     // Previous sample -> pipeline[1] 
      int_rising_next = int_rising_wire;      // Update rising edge detection
    end

    // Increment delay counter during initial delay period
    if(s_axis_tvalid & int_delay_wire)
    begin
      int_cntr_next = int_cntr_reg + 1'b1;    // Count until cfg_data is reached
    end

    // Minimum detection: Find pulse baseline after delay period
    // Trigger: Delay complete + falling-to-rising transition
    if(s_axis_tvalid & ~int_delay_wire & ~int_rising_reg & int_rising_wire)
    begin
      int_min_next = int_data_reg[1];         // Store the minimum value (pulse start)
      int_enbl_next = 1'b1;                   // Enable peak detection
    end

    // Maximum detection: Find pulse peak and calculate height
    // Trigger: Enabled + rising-to-falling transition + above min threshold
    if(s_axis_tvalid & int_enbl_reg & int_rising_reg & ~int_rising_wire & int_mincut_wire)
    begin
      // Store pulse height if within range, else store zero
      int_tdata_next = int_maxcut_wire ? int_tdata_wire : {(AXIS_TDATA_WIDTH){1'b0}};
      int_tvalid_next = int_maxcut_wire;      // Set valid only if within max threshold
      int_cntr_next = {(CNTR_WIDTH){1'b0}};   // Reset counter for next pulse
      int_enbl_next = 1'b0;                   // Disable until next pulse detection
    end

    // Clear output when data is read by master
    if(m_axis_tready & int_tvalid_reg)
    begin
      int_tdata_next = {(AXIS_TDATA_WIDTH){1'b0}};  // Clear output data
      int_tvalid_next = 1'b0;                       // Clear valid flag
    end
  end

  // Continuous assignments for AXI Stream interface
  assign s_axis_tready = 1'b1;                // Always ready to accept input data
  assign m_axis_tdata = int_tdata_reg;        // Output calculated pulse height
  assign m_axis_tvalid = int_tvalid_reg;      // Output data valid signal

endmodule
