/**
 * @file tb_trigger_uvm_top.sv
 * @brief Top module del testbench UVM para el trigger
 *
 * Instancia el DUT, las interfaces, y arranca UVM.
 *
 * @par Uso:
 * @code
 *   vsim tb_trigger_uvm_top +UVM_TESTNAME=trigger_rising_ramp_test
 * @endcode
 */

`timescale 1ns/1ps

module tb_trigger_uvm_top;

    import uvm_pkg::*;
    import axi_stream_pkg::*;
    import mcpha_uvm_pkg::*;
    
    //=========================================================================
    // Parámetros
    //=========================================================================
    
    localparam real CLK_PERIOD = 8.0;  // 125 MHz
    localparam int DATA_WIDTH = 16;
    
    //=========================================================================
    // Señales de reloj y reset
    //=========================================================================
    
    logic aclk;
    logic aresetn;
    
    // Generador de reloj
    initial begin
        aclk = 0;
        forever #(CLK_PERIOD/2) aclk = ~aclk;
    end
    
    // Reset inicial
    initial begin
        aresetn = 0;
        repeat(10) @(posedge aclk);
        aresetn = 1;
    end
    
    //=========================================================================
    // Interfaces
    //=========================================================================
    
    axis_if #(.DATA_WIDTH(DATA_WIDTH)) input_if  (aclk, aresetn);
    axis_if #(.DATA_WIDTH(DATA_WIDTH)) output_if (aclk, aresetn);
    
    //=========================================================================
    // Configuración del DUT
    //=========================================================================
    
    trigger_config_t trigger_config;
    logic trigger_out;
    
    // Configuración inicial (puede ser cambiada por el test)
    initial begin
        trigger_config.enable    = 1'b1;
        trigger_config.mode      = TRIG_RISING;
        trigger_config.threshold = 16'd500;
        trigger_config.ch_mask   = 2'b11;
    end
    
    //=========================================================================
    // DUT: axis_trigger
    //=========================================================================
    
    axis_trigger dut (
        .aclk           (aclk),
        .aresetn        (aresetn),
        
        // Configuración
        .config_i       (trigger_config),
        
        // AXI-Stream entrada
        .s_axis_tdata   (input_if.tdata),
        .s_axis_tvalid  (input_if.tvalid),
        .s_axis_tready  (input_if.tready),
        
        // AXI-Stream salida
        .m_axis_tdata   (output_if.tdata),
        .m_axis_tvalid  (output_if.tvalid),
        .m_axis_tready  (output_if.tready),
        
        // Salida de trigger
        .trigger_out    (trigger_out)
    );
    
    // TLAST no se usa en este módulo, conectar a 0
    assign input_if.tlast = 1'b0;
    assign output_if.tlast = 1'b0;
    
    //=========================================================================
    // Configuración de UVM
    //=========================================================================
    
    initial begin
        // Registrar interfaces en config_db
        uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top", "input_vif", input_if);
        uvm_config_db#(virtual axis_if)::set(null, "uvm_test_top", "output_vif", output_if);
        
        // Registrar señal de trigger
        // (se puede acceder via hierarchical reference en el scoreboard)
        
        // Iniciar UVM
        run_test();
    end
    
    //=========================================================================
    // Monitoreo de trigger para el scoreboard
    //=========================================================================
    
    // El scoreboard necesita observar trigger_out
    // Esto se puede hacer via bind o hierarchical reference
    
    //=========================================================================
    // Dump de señales
    //=========================================================================
    
    initial begin
        string dump_file;
        
        if ($value$plusargs("DUMP_FILE=%s", dump_file)) begin
            $dumpfile(dump_file);
        end else begin
            $dumpfile("tb_trigger_uvm.vcd");
        end
        
        $dumpvars(0, tb_trigger_uvm_top);
    end
    
    //=========================================================================
    // Timeout global
    //=========================================================================
    
    initial begin
        #100ms;
        `uvm_fatal("TIMEOUT", "Simulación excedió timeout global")
    end

endmodule : tb_trigger_uvm_top
