/**
 * @file tb_axis_ram_writer.sv
 * @brief Testbench unitario para el modulo axis_ram_writer
 *
 * Simula un slave AXI4 para verificar las transacciones generadas.
 * Sintaxis compatible con QuestaSim 10.7c.
 */

`timescale 1ns/1ps

module tb_axis_ram_writer;

    //=========================================================================
    // Parametros
    //=========================================================================
    
    localparam real CLK_PERIOD = 8.0;
    localparam int DATA_WIDTH = 16;
    localparam int AXI_DATA_W = 64;
    localparam int AXI_ADDR_W = 32;
    localparam int FIFO_DEPTH = 1024;
    
    localparam logic [31:0] BASE_ADDR = 32'h1000_0000;
    localparam int MEMORY_SIZE = 65536;

    //=========================================================================
    // Imports
    //=========================================================================
    
    import axi_stream_pkg::*;

    //=========================================================================
    // Senales
    //=========================================================================
    
    logic aclk;
    logic aresetn;
    
    // AXI-Stream Slave
    logic [DATA_WIDTH-1:0] s_axis_tdata;
    logic s_axis_tvalid;
    logic s_axis_tready;
    logic s_axis_tlast;
    
    // AXI4 Master Write
    logic [AXI_ADDR_W-1:0] m_axi_awaddr;
    logic [7:0] m_axi_awlen;
    logic [2:0] m_axi_awsize;
    logic [1:0] m_axi_awburst;
    logic m_axi_awvalid;
    logic m_axi_awready;
    
    logic [AXI_DATA_W-1:0] m_axi_wdata;
    logic [(AXI_DATA_W/8)-1:0] m_axi_wstrb;
    logic m_axi_wlast;
    logic m_axi_wvalid;
    logic m_axi_wready;
    
    logic [1:0] m_axi_bresp;
    logic m_axi_bvalid;
    logic m_axi_bready;

    //=========================================================================
    // Configuracion
    //=========================================================================
    
    ram_writer_config_t config_i;

    //=========================================================================
    // DUT
    //=========================================================================
    
    axis_ram_writer #(
        .AXI_DATA_W    (AXI_DATA_W),
        .AXI_ADDR_W    (AXI_ADDR_W),
        .FIFO_DEPTH    (FIFO_DEPTH),
        .DATA_WIDTH    (DATA_WIDTH)
    ) dut (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .config_i       (config_i),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready)
    );

    //=========================================================================
    // Reloj
    //=========================================================================
    
    initial begin
        aclk = 0;
        forever #(CLK_PERIOD/2) aclk = ~aclk;
    end

    //=========================================================================
    // Memoria simulada (AXI Slave)
    //=========================================================================
    
    reg [7:0] memory [0:MEMORY_SIZE-1];
    
    int axi_aw_count;
    int axi_w_count;
    int axi_b_count;
    int total_bytes;
    int test_errors;
    
    // Estado del slave AXI
    logic [31:0] current_addr;
    logic [7:0] current_len;
    int beat_count;

    //=========================================================================
    // Inicializacion de memoria
    //=========================================================================
    
    integer init_idx;
    initial begin
        for (init_idx = 0; init_idx < MEMORY_SIZE; init_idx = init_idx + 1) begin
            memory[init_idx] = 8'h00;
        end
    end

    //=========================================================================
    // Proceso AW (direcciones)
    //=========================================================================
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axi_awready <= 1;
            current_addr <= 0;
            current_len <= 0;
            beat_count <= 0;
        end else begin
            if (m_axi_awvalid && m_axi_awready) begin
                current_addr <= m_axi_awaddr;
                current_len <= m_axi_awlen;
                beat_count <= 0;
                axi_aw_count <= axi_aw_count + 1;
                $display("[AXI] AW: addr=0x%08X, len=%0d", m_axi_awaddr, m_axi_awlen);
            end
        end
    end
    
    //=========================================================================
    // Proceso W (datos) - escritura byte a byte
    //=========================================================================
    
    integer w_byte_idx;
    integer w_mem_offset;
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axi_wready <= 1;
        end else begin
            if (m_axi_wvalid && m_axi_wready) begin
                // Escribir cada byte individualmente
                for (w_byte_idx = 0; w_byte_idx < 8; w_byte_idx = w_byte_idx + 1) begin
                    if (m_axi_wstrb[w_byte_idx]) begin
                        w_mem_offset = (current_addr - BASE_ADDR + beat_count*8 + w_byte_idx);
                        if (w_mem_offset >= 0 && w_mem_offset < MEMORY_SIZE) begin
                            memory[w_mem_offset] <= m_axi_wdata[w_byte_idx*8 +: 8];
                        end
                        total_bytes <= total_bytes + 1;
                    end
                end
                
                beat_count <= beat_count + 1;
                axi_w_count <= axi_w_count + 1;
                
                if (m_axi_wlast) begin
                    $display("[AXI] W: burst complete, %0d beats", beat_count + 1);
                end
            end
        end
    end
    
    //=========================================================================
    // Proceso B (respuestas)
    //=========================================================================
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axi_bvalid <= 0;
            m_axi_bresp <= 2'b00;
        end else begin
            if (m_axi_wvalid && m_axi_wready && m_axi_wlast && !m_axi_bvalid) begin
                m_axi_bvalid <= 1;
            end else if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 0;
                axi_b_count <= axi_b_count + 1;
            end
        end
    end

    //=========================================================================
    // Tasks
    //=========================================================================
    
    integer reset_idx;
    
    task automatic do_reset();
        aresetn = 0;
        config_i = '0;
        s_axis_tdata = 0;
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
        
        axi_aw_count = 0;
        axi_w_count = 0;
        axi_b_count = 0;
        total_bytes = 0;
        beat_count = 0;
        
        // Limpiar memoria
        for (reset_idx = 0; reset_idx < MEMORY_SIZE; reset_idx = reset_idx + 1) begin
            memory[reset_idx] = 8'h00;
        end
        
        repeat(10) @(posedge aclk);
        aresetn = 1;
        @(posedge aclk);
    endtask
    
    task automatic configure();
        config_i.enable = 1;
        config_i.base_addr = BASE_ADDR;
        config_i.buffer_size = MEMORY_SIZE;
        @(posedge aclk);
        $display("[TB] Config: base=0x%08X", BASE_ADDR);
    endtask
    
    task automatic send_sample(input logic [DATA_WIDTH-1:0] data, input logic last);
        s_axis_tdata = data;
        s_axis_tvalid = 1;
        s_axis_tlast = last;
        
        @(posedge aclk);
        while (!s_axis_tready) @(posedge aclk);
        
        s_axis_tvalid = 0;
        s_axis_tlast = 0;
    endtask
    
    integer pkt_idx;
    logic pkt_is_last;
    
    task automatic send_packet(input int count);
        $display("[TB] Enviando %0d samples...", count);
        
        for (pkt_idx = 0; pkt_idx < count; pkt_idx = pkt_idx + 1) begin
            pkt_is_last = (pkt_idx == count - 1);
            send_sample(pkt_idx[DATA_WIDTH-1:0], pkt_is_last);
        end
        
        // Esperar que se procesen los bursts
        repeat(1000) @(posedge aclk);
    endtask
    
    integer verify_idx;
    integer verify_offset;
    logic [15:0] verify_expected;
    logic [15:0] verify_got;
    int verify_errors;
    
    task automatic verify_memory(input int count);
        verify_errors = 0;
        
        $display("[TB] Verificando %0d samples...", count);
        
        // Dar tiempo para que las escrituras se completen
        repeat(100) @(posedge aclk);
        
        for (verify_idx = 0; verify_idx < count; verify_idx = verify_idx + 1) begin
            verify_offset = verify_idx * 2;
            verify_expected = verify_idx[15:0];
            verify_got = {memory[verify_offset+1], memory[verify_offset]};
            
            if (verify_got !== verify_expected) begin
                if (verify_errors < 5) begin
                    $display("[TB] Mismatch en sample %0d: esperado=0x%04X, obtenido=0x%04X", 
                             verify_idx, verify_expected, verify_got);
                end
                verify_errors = verify_errors + 1;
            end
        end
        
        if (verify_errors == 0) begin
            $display("[TB] PASSED: %0d samples verificados", count);
        end else begin
            $display("[TB] FAILED: %0d errores", verify_errors);
            test_errors = test_errors + verify_errors;
        end
    endtask

    //=========================================================================
    // Tests
    //=========================================================================
    
    task automatic test_basic();
        $display("\n========== TEST: Basic Write ==========");
        do_reset();
        configure();
        
        send_packet(64);
        verify_memory(64);
    endtask
    
    task automatic test_larger();
        $display("\n========== TEST: Larger Packet ==========");
        do_reset();
        configure();
        
        send_packet(256);
        verify_memory(256);
    endtask
    
    integer multi_idx;
    logic multi_is_last;
    logic [DATA_WIDTH-1:0] multi_data;
    
    task automatic test_multiple();
        $display("\n========== TEST: Multiple Packets ==========");
        do_reset();
        configure();
        
        // Primer paquete
        send_packet(32);
        repeat(200) @(posedge aclk);
        
        // Segundo paquete (valores offset +100)
        $display("[TB] Enviando segundo paquete...");
        for (multi_idx = 0; multi_idx < 32; multi_idx = multi_idx + 1) begin
            multi_is_last = (multi_idx == 31);
            multi_data = multi_idx + 100;
            send_sample(multi_data, multi_is_last);
        end
        
        repeat(500) @(posedge aclk);
        
        // Verificar primer paquete (el segundo lo sobrescribe en otro offset)
        $display("[TB] Verificando primer paquete...");
        verify_memory(32);
    endtask

    //=========================================================================
    // Main
    //=========================================================================
    
    initial begin
        $display("\n");
        $display("+------------------------------------------------------------+");
        $display("|         TESTBENCH: axis_ram_writer                         |");
        $display("+------------------------------------------------------------+");
        
        test_errors = 0;
        
        test_basic();
        test_larger();
        test_multiple();
        
        $display("\n");
        $display("+------------------------------------------------------------+");
        $display("|                    RESUMEN                                 |");
        $display("+------------------------------------------------------------+");
        $display("|  Transacciones AW: %-38d  |", axi_aw_count);
        $display("|  Beats W:          %-38d  |", axi_w_count);
        $display("|  Respuestas B:     %-38d  |", axi_b_count);
        $display("|  Total bytes:      %-38d  |", total_bytes);
        $display("+------------------------------------------------------------+");
        
        if (test_errors == 0) begin
            $display("|  >>> ALL TESTS PASSED                                     |");
        end else begin
            $display("|  >>> FAILED: %3d total errors                              |", test_errors);
        end
        
        $display("+------------------------------------------------------------+");
        $display("\n>>> Simulacion completada <<<\n");
        $finish;
    end

    //=========================================================================
    // Watchdog
    //=========================================================================
    
    initial begin
        #(CLK_PERIOD * 500000);
        $display("[ERROR] Watchdog timeout");
        $finish;
    end

endmodule
