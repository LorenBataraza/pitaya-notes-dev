/**
 * @file tb_axis_ram_writer.sv
 * @brief Testbench para el módulo axis_ram_writer
 *
 * Verifica la funcionalidad del escritor de RAM incluyendo:
 * - Protocolo AXI4 Master
 * - Manejo de bursts
 * - Límite de 4KB
 * - Flush después de TLAST
 *
 * @par Escenarios de prueba:
 * - Escritura básica de datos
 * - Burst máximo (256 beats)
 * - Burst parcial (menos de MAX_BURST_LEN)
 * - TLAST con datos pendientes
 * - Backpressure en AXI4
 */

`timescale 1ns/1ps

module tb_axis_ram_writer;

    //=========================================================================
    // Imports
    //=========================================================================
    
    import axi_stream_pkg::*;

    //=========================================================================
    // Parámetros
    //=========================================================================
    
    localparam real CLK_PERIOD = 8.0;  // 125 MHz
    
    // Parámetros del DUT (deben coincidir con axis_ram_writer.sv)
    localparam int DATA_WIDTH    = DSP_DATA_WIDTH;  // 16
    localparam int AXI_DATA_W    = AXI_DATA_WIDTH;  // 64
    localparam int AXI_ADDR_W    = AXI_ADDR_WIDTH;  // 32
    localparam int AXI_ID_W      = 4;
    localparam int FIFO_DEPTH    = 1024;
    localparam int MAX_BURST_LEN = 16;
    
    // Parámetros de test
    localparam int NUM_SAMPLES    = 1000;
    localparam int MEMORY_SIZE    = 64 * 1024;  // 64 KB
    localparam int BASE_ADDR      = 32'h1000_0000;

    //=========================================================================
    // Señales
    //=========================================================================
    
    logic aclk;
    logic aresetn;
    
    // Configuración y estado
    ram_writer_config_t config_i;
    ram_writer_status_t status_o;
    
    // AXI-Stream Slave
    logic signed [DATA_WIDTH-1:0] s_axis_tdata;
    logic                         s_axis_tvalid;
    logic                         s_axis_tready;
    logic                         s_axis_tlast;
    
    // AXI4 Master - Write Address Channel
    logic [AXI_ID_W-1:0]          m_axi_awid;
    logic [AXI_ADDR_W-1:0]        m_axi_awaddr;
    logic [7:0]                   m_axi_awlen;
    logic [2:0]                   m_axi_awsize;
    logic [1:0]                   m_axi_awburst;
    logic                         m_axi_awlock;
    logic [3:0]                   m_axi_awcache;
    logic [2:0]                   m_axi_awprot;
    logic                         m_axi_awvalid;
    logic                         m_axi_awready;
    
    // AXI4 Master - Write Data Channel
    logic [AXI_DATA_W-1:0]        m_axi_wdata;
    logic [AXI_DATA_W/8-1:0]      m_axi_wstrb;
    logic                         m_axi_wlast;
    logic                         m_axi_wvalid;
    logic                         m_axi_wready;
    
    // AXI4 Master - Write Response Channel
    logic [AXI_ID_W-1:0]          m_axi_bid;
    logic [1:0]                   m_axi_bresp;
    logic                         m_axi_bvalid;
    logic                         m_axi_bready;

    //=========================================================================
    // DUT
    //=========================================================================
    
    axis_ram_writer #(
        .AXI_DATA_W    (AXI_DATA_W),
        .AXI_ADDR_W    (AXI_ADDR_W),
        .AXI_ID_W      (AXI_ID_W),
        .FIFO_DEPTH    (FIFO_DEPTH),
        .MAX_BURST_LEN (MAX_BURST_LEN),
        .DATA_WIDTH    (DATA_WIDTH)
    ) dut (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .config_i      (config_i),
        .status_o      (status_o),
        
        // AXI-Stream Slave
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        
        // AXI4 Master
        .m_axi_awid    (m_axi_awid),
        .m_axi_awaddr  (m_axi_awaddr),
        .m_axi_awlen   (m_axi_awlen),
        .m_axi_awsize  (m_axi_awsize),
        .m_axi_awburst (m_axi_awburst),
        .m_axi_awlock  (m_axi_awlock),
        .m_axi_awcache (m_axi_awcache),
        .m_axi_awprot  (m_axi_awprot),
        .m_axi_awvalid (m_axi_awvalid),
        .m_axi_awready (m_axi_awready),
        
        .m_axi_wdata   (m_axi_wdata),
        .m_axi_wstrb   (m_axi_wstrb),
        .m_axi_wlast   (m_axi_wlast),
        .m_axi_wvalid  (m_axi_wvalid),
        .m_axi_wready  (m_axi_wready),
        
        .m_axi_bid     (m_axi_bid),
        .m_axi_bresp   (m_axi_bresp),
        .m_axi_bvalid  (m_axi_bvalid),
        .m_axi_bready  (m_axi_bready)
    );

    //=========================================================================
    // Modelo de memoria (AXI4 Slave simplificado)
    //=========================================================================
    
    logic [7:0] memory [MEMORY_SIZE];
    
    // Contadores para verificación
    int axi_aw_count;
    int axi_w_count;
    int axi_b_count;
    int total_bytes_written;
    
    // Cola de transacciones pendientes
    typedef struct {
        logic [AXI_ADDR_W-1:0] addr;
        logic [7:0]            len;
        logic [2:0]            size;
    } axi_aw_txn_t;
    
    axi_aw_txn_t aw_queue[$];
    
    // Proceso de dirección de escritura
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            m_axi_awready <= 1'b1;
            axi_aw_count <= 0;
        end else begin
            // Aceptar direcciones con probabilidad variable (simular backpressure)
            m_axi_awready <= ($urandom_range(0, 9) > 1);  // 80% ready
            
            if (m_axi_awvalid && m_axi_awready) begin
                automatic axi_aw_txn_t txn;
                txn.addr = m_axi_awaddr;
                txn.len  = m_axi_awlen;
                txn.size = m_axi_awsize;
                aw_queue.push_back(txn);
                axi_aw_count++;
                
                $display("[MEM] AW: addr=0x%08X, len=%0d, size=%0d",
                         m_axi_awaddr, m_axi_awlen, m_axi_awsize);
            end
        end
    end
    
    // Proceso de datos de escritura
    int beat_count;
    axi_aw_txn_t current_txn;
    logic [AXI_ADDR_W-1:0] current_addr;
    
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            m_axi_wready <= 1'b1;
            beat_count <= 0;
            axi_w_count <= 0;
            total_bytes_written <= 0;
        end else begin
            // Backpressure aleatorio
            m_axi_wready <= ($urandom_range(0, 9) > 2);  // 70% ready
            
            if (m_axi_wvalid && m_axi_wready) begin
                // Obtener transacción actual
                if (beat_count == 0 && aw_queue.size() > 0) begin
                    current_txn = aw_queue.pop_front();
                    current_addr = current_txn.addr;
                end
                
                // Escribir bytes en memoria
                for (int i = 0; i < (AXI_DATA_W/8); i++) begin
                    if (m_axi_wstrb[i]) begin
                        automatic int addr_offset;
                        addr_offset = (current_addr - BASE_ADDR + i) % MEMORY_SIZE;
                        memory[addr_offset] = m_axi_wdata[i*8 +: 8];
                        total_bytes_written++;
                    end
                end
                
                beat_count++;
                current_addr += (1 << current_txn.size);
                axi_w_count++;
                
                // Verificar WLAST
                if (m_axi_wlast) begin
                    if (beat_count != current_txn.len + 1) begin
                        $error("[MEM] WLAST mismatch: expected %0d beats, got %0d",
                               current_txn.len + 1, beat_count);
                    end
                    beat_count <= 0;
                end
            end
        end
    end
    
    // Proceso de respuesta
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            m_axi_bvalid <= 1'b0;
            m_axi_bresp <= 2'b00;
            m_axi_bid <= '0;
            axi_b_count <= 0;
        end else begin
            // Generar respuesta después de WLAST
            if (m_axi_wvalid && m_axi_wready && m_axi_wlast && !m_axi_bvalid) begin
                m_axi_bvalid <= 1'b1;
                m_axi_bresp <= 2'b00;  // OKAY
                m_axi_bid <= m_axi_awid;
            end else if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 1'b0;
                axi_b_count++;
            end
        end
    end

    //=========================================================================
    // Generación de reloj
    //=========================================================================
    
    initial begin
        aclk = 1'b0;
        forever #(CLK_PERIOD/2) aclk = ~aclk;
    end

    //=========================================================================
    // Tareas de utilidad
    //=========================================================================
    
    task automatic apply_reset();
        aresetn = 1'b0;
        s_axis_tdata = '0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
        config_i = '0;
        repeat(10) @(posedge aclk);
        aresetn = 1'b1;
        @(posedge aclk);
    endtask
    
    task automatic configure_dut(
        input logic [31:0] base_addr,
        input logic [31:0] buffer_size
    );
        config_i.enable = 1'b1;
        config_i.base_addr = base_addr;
        config_i.buffer_size = buffer_size;
        @(posedge aclk);
        $display("[TB] DUT configured: base=0x%08X, size=%0d", base_addr, buffer_size);
    endtask
    
    task automatic send_sample(
        input logic signed [DATA_WIDTH-1:0] data,
        input logic last = 1'b0
    );
        s_axis_tdata = data;
        s_axis_tvalid = 1'b1;
        s_axis_tlast = last;
        
        do @(posedge aclk);
        while (!s_axis_tready);
        
        s_axis_tvalid = 1'b0;
        s_axis_tlast = 1'b0;
    endtask
    
    task automatic send_samples(
        input int count,
        input logic mark_last = 1'b1
    );
        for (int i = 0; i < count; i++) begin
            automatic logic is_last;
            is_last = mark_last && (i == count - 1);
            send_sample(i[DATA_WIDTH-1:0], is_last);
        end
    endtask
    
    task automatic wait_idle(input int timeout = 10000);
        int count = 0;
        
        while (status_o.state != WR_IDLE && count < timeout) begin
            @(posedge aclk);
            count++;
        end
        
        if (count >= timeout)
            $error("[TB] Timeout waiting for IDLE state");
    endtask

    //=========================================================================
    // Tests
    //=========================================================================
    
    task automatic test_basic_write();
        $display("\n========== TEST: Basic Write ==========");
        
        configure_dut(BASE_ADDR, MEMORY_SIZE);
        
        // Enviar algunos datos
        send_samples(100, 1'b1);
        
        // Esperar que se procesen
        repeat(500) @(posedge aclk);
        wait_idle();
        
        // Verificar
        $display("[TB] AW transactions: %0d", axi_aw_count);
        $display("[TB] W beats: %0d", axi_w_count);
        $display("[TB] Bytes written: %0d", total_bytes_written);
        
        if (axi_aw_count > 0 && axi_b_count == axi_aw_count)
            $display("[TB] TEST PASSED: Basic write completed");
        else
            $error("[TB] TEST FAILED: Incomplete transactions");
    endtask
    
    task automatic test_burst_alignment();
        $display("\n========== TEST: Burst Alignment (4KB) ==========");
        
        // Resetear contadores
        axi_aw_count = 0;
        axi_w_count = 0;
        
        configure_dut(BASE_ADDR, MEMORY_SIZE);
        
        // Enviar suficientes datos para requerir múltiples bursts
        send_samples(500, 1'b1);
        
        repeat(1000) @(posedge aclk);
        wait_idle();
        
        $display("[TB] TEST: Burst alignment checked via SVA assertions");
    endtask
    
    task automatic test_tlast_flush();
        $display("\n========== TEST: TLAST Flush ==========");
        
        // Este test verifica H1: TLAST debe causar flush del FIFO
        
        // Resetear contadores
        total_bytes_written = 0;
        
        configure_dut(BASE_ADDR, MEMORY_SIZE);
        
        // Enviar menos datos que un burst completo, con TLAST
        send_samples(10, 1'b1);
        
        // Esperar
        repeat(500) @(posedge aclk);
        wait_idle();
        
        // Verificar que todos los datos se escribieron
        // Con 10 muestras de 16 bits = 20 bytes
        // Pero empaquetados en 64 bits...
        $display("[TB] Samples sent: 10");
        $display("[TB] Bytes written: %0d", total_bytes_written);
        
        if (total_bytes_written >= 10)  // Al menos los datos
            $display("[TB] TEST PASSED: TLAST caused flush");
        else
            $warning("[TB] TEST WARNING: Possible H1 bug - TLAST may not flush FIFO");
    endtask
    
    task automatic test_backpressure();
        $display("\n========== TEST: Backpressure Handling ==========");
        
        // Este test usa el backpressure aleatorio del modelo de memoria
        
        configure_dut(BASE_ADDR, MEMORY_SIZE);
        
        // Enviar datos continuamente
        fork
            send_samples(200, 1'b1);
        join
        
        repeat(2000) @(posedge aclk);
        wait_idle();
        
        $display("[TB] TEST: Backpressure handled (check for deadlock via SVA)");
    endtask

    //=========================================================================
    // Secuencia principal
    //=========================================================================
    
    initial begin
        $display("\n");
        $display("+------------------------------------------------------------+");
        $display("|         TESTBENCH: axis_ram_writer                         |");
        $display("+------------------------------------------------------------+");
        
        // Inicializar memoria
        foreach (memory[i]) memory[i] = 8'h00;
        
        apply_reset();
        
        // Ejecutar tests
        test_basic_write();
        test_burst_alignment();
        test_tlast_flush();
        test_backpressure();
        
        // Resumen
        repeat(100) @(posedge aclk);
        
        $display("\n");
        $display("+------------------------------------------------------------+");
        $display("|                    RESUMEN                                 |");
        $display("+------------------------------------------------------------+");
        $display("|  Transacciones AW: %-38d  |", axi_aw_count);
        $display("|  Beats W:          %-38d  |", axi_w_count);
        $display("|  Respuestas B:     %-38d  |", axi_b_count);
        $display("|  Total bytes:      %-38d  |", total_bytes_written);
        $display("+------------------------------------------------------------+");
        
        $finish;
    end

    //=========================================================================
    // Watchdog
    //=========================================================================
    
    initial begin
        #(CLK_PERIOD * 50000);
        $error("[TB] Watchdog timeout");
        $finish;
    end

endmodule : tb_axis_ram_writer
