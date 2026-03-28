/**
 * @file tb_axis_scope.sv
 * @brief Testbench unitario para el modulo axis_scope
 *
 * Usa fork/join para enviar datos y leer salidas en paralelo,
 * evitando deadlock cuando el scope baja TREADY durante output.
 */

`timescale 1ns/1ps

module tb_axis_scope;

    //=========================================================================
    // Parametros
    //=========================================================================
    
    localparam real CLK_PERIOD = 8.0;
    localparam int DATA_WIDTH = 16;
    localparam int BUFFER_DEPTH = 4096;
    localparam int NUM_CH = 2;

    //=========================================================================
    // Imports
    //=========================================================================
    
    import axi_stream_pkg::*;

    //=========================================================================
    // Senales
    //=========================================================================
    
    logic aclk;
    logic aresetn;
    scope_config_t config_i;
    scope_status_t status_o;
    logic trigger_in;
    
    logic [DATA_WIDTH-1:0] s_axis_tdata;
    logic s_axis_tvalid;
    logic s_axis_tready;
    
    logic [DATA_WIDTH-1:0] m_axis_tdata;
    logic m_axis_tvalid;
    logic m_axis_tready;
    logic m_axis_tlast;

    //=========================================================================
    // DUT
    //=========================================================================
    
    axis_scope #(
        .DATA_WIDTH   (DATA_WIDTH),
        .BUFFER_DEPTH (BUFFER_DEPTH),
        .NUM_CH       (NUM_CH)
    ) dut (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .config_i      (config_i),
        .status_o      (status_o),
        .trigger_in    (trigger_in),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tlast  (m_axis_tlast)
    );

    //=========================================================================
    // Reloj
    //=========================================================================
    
    initial begin
        aclk = 0;
        forever #(CLK_PERIOD/2) aclk = ~aclk;
    end

    //=========================================================================
    // Variables de verificacion
    //=========================================================================
    
    int sent_count;
    int received_count;
    int trigger_index;
    logic capture_complete;
    logic send_done;
    int test_errors;
    int cfg_pre;
    int cfg_post;
    
    // Memorias para datos
    logic signed [DATA_WIDTH-1:0] sent_data [0:4095];
    logic signed [DATA_WIDTH-1:0] received_data [0:4095];

    //=========================================================================
    // Monitor de salida (always, recibe datos continuamente)
    //=========================================================================
    
    always @(posedge aclk) begin
        if (aresetn && m_axis_tvalid && m_axis_tready) begin
            if (received_count < 4096) begin
                received_data[received_count] = m_axis_tdata;
            end
            received_count = received_count + 1;
            
            if (m_axis_tlast) begin
                capture_complete = 1;
                $display("[MON] TLAST recibido. Total: %0d samples", received_count);
            end
        end
    end

    //=========================================================================
    // Tasks basicas
    //=========================================================================
    
    task automatic do_reset();
        aresetn = 0;
        config_i = '0;
        trigger_in = 0;
        s_axis_tdata = 0;
        s_axis_tvalid = 0;
        m_axis_tready = 1;
        sent_count = 0;
        received_count = 0;
        trigger_index = -1;
        capture_complete = 0;
        send_done = 0;
        cfg_pre = 0;
        cfg_post = 0;
        
        repeat(10) @(posedge aclk);
        aresetn = 1;
        @(posedge aclk);
    endtask
    
    task automatic configure(int pre, int post);
        config_i.enable = 1;
        config_i.arm = 0;
        config_i.pre_samples = pre;
        config_i.post_samples = post;
        cfg_pre = pre;
        cfg_post = post;
        @(posedge aclk);
        $display("[TB] Config: pre=%0d, post=%0d", pre, post);
    endtask
    
    task automatic arm();
        config_i.arm = 1;
        @(posedge aclk);
        config_i.arm = 0;
        @(posedge aclk);
        $display("[TB] Armed");
    endtask

    //=========================================================================
    // Task de envio con timeout en TREADY
    //=========================================================================
    
    task automatic send_data_nonblocking(int count, int trig_at);
        int tready_timeout;
        int i;
        
        $display("[TB] Enviando %0d muestras, trigger en %0d", count, trig_at);
        
        for (i = 0; i < count; i++) begin
            s_axis_tdata = i[DATA_WIDTH-1:0];
            s_axis_tvalid = 1;
            
            // Generar trigger
            if (i == trig_at) begin
                trigger_in = 1;
                trigger_index = i;
                $display("[TB] Trigger en sample %0d", i);
            end
            
            @(posedge aclk);
            
            // Esperar TREADY con timeout
            tready_timeout = 0;
            while (!s_axis_tready && tready_timeout < 1000) begin
                @(posedge aclk);
                tready_timeout++;
            end
            
            // Si timeout, el scope ya no acepta datos
            if (tready_timeout >= 1000) begin
                $display("[TB] TREADY timeout en sample %0d, scope en output", i);
                s_axis_tvalid = 0;
                trigger_in = 0;
                break;
            end
            
            // Desactivar trigger despues de un ciclo
            if (trigger_in) begin
                trigger_in = 0;
            end
            
            if (sent_count < 4096) begin
                sent_data[sent_count] = i[DATA_WIDTH-1:0];
            end
            sent_count = sent_count + 1;
        end
        
        s_axis_tvalid = 0;
        trigger_in = 0;
        send_done = 1;
        $display("[TB] Envio completo: %0d samples", sent_count);
    endtask

    //=========================================================================
    // Task de espera de captura
    //=========================================================================
    
    task automatic wait_capture(int timeout_cycles);
        int cnt;
        cnt = 0;
        
        while (!capture_complete && cnt < timeout_cycles) begin
            @(posedge aclk);
            cnt++;
        end
        
        if (cnt >= timeout_cycles) begin
            $display("[TB] ERROR: Timeout esperando captura");
            test_errors++;
        end else begin
            $display("[TB] Captura completa en %0d ciclos", cnt);
        end
    endtask

    //=========================================================================
    // Task de verificacion
    //
    // El scope RTL siempre devuelve pre_samples + post_samples muestras,
    // independientemente de cuantas muestras haya antes del trigger.
    //=========================================================================
    
    task automatic verify(int exp_total);
        $display("[TB] Verificando: esperado=%0d, recibido=%0d", 
                 exp_total, received_count);
        
        if (received_count != exp_total) begin
            $display("[TB] ERROR: Conteo incorrecto!");
            test_errors++;
        end else begin
            $display("[TB] OK: Conteo correcto");
        end
    endtask

    //=========================================================================
    // Tests
    //=========================================================================
    
    task automatic test_basic();
        $display("\n========== TEST: Basic Capture ==========");
        do_reset();
        configure(100, 200);
        arm();
        
        fork
            send_data_nonblocking(500, 200);
            wait_capture(100000);
        join
        
        repeat(100) @(posedge aclk);
        
        // Esperamos pre + post = 300 samples
        verify(cfg_pre + cfg_post);
        
        if (test_errors == 0)
            $display("[TB] test_basic: PASSED");
        else
            $display("[TB] test_basic: FAILED");
    endtask
    
    task automatic test_pre_only();
        $display("\n========== TEST: Pre-trigger Only ==========");
        do_reset();
        configure(50, 0);
        arm();
        
        fork
            send_data_nonblocking(100, 60);
            wait_capture(50000);
        join
        
        repeat(100) @(posedge aclk);
        
        // Esperamos pre + post = 50 samples
        verify(cfg_pre + cfg_post);
        
        if (test_errors == 0)
            $display("[TB] test_pre_only: PASSED");
        else
            $display("[TB] test_pre_only: FAILED");
    endtask
    
    task automatic test_post_only();
        $display("\n========== TEST: Post-trigger Only ==========");
        do_reset();
        configure(0, 100);
        arm();
        
        fork
            send_data_nonblocking(200, 50);
            wait_capture(50000);
        join
        
        repeat(100) @(posedge aclk);
        
        // Esperamos pre + post = 100 samples
        verify(cfg_pre + cfg_post);
        
        if (test_errors == 0)
            $display("[TB] test_post_only: PASSED");
        else
            $display("[TB] test_post_only: FAILED");
    endtask
    
    task automatic test_early_trigger();
        $display("\n========== TEST: Early Trigger ==========");
        do_reset();
        configure(100, 50);
        arm();
        
        // Trigger llega en sample 30, antes de llenar el buffer pre (100)
        // El scope RTL devuelve pre_samples + post_samples = 150 samples
        fork
            send_data_nonblocking(200, 30);
            wait_capture(50000);
        join
        
        repeat(100) @(posedge aclk);
        
        // El RTL devuelve siempre pre + post
        verify(cfg_pre + cfg_post);
        
        if (test_errors == 0)
            $display("[TB] test_early_trigger: PASSED");
        else
            $display("[TB] test_early_trigger: FAILED");
    endtask
    
    task automatic test_small_window();
        $display("\n========== TEST: Small Window ==========");
        do_reset();
        configure(10, 10);
        arm();
        
        fork
            send_data_nonblocking(100, 50);
            wait_capture(50000);
        join
        
        repeat(100) @(posedge aclk);
        
        // Esperamos pre + post = 20 samples
        verify(cfg_pre + cfg_post);
        
        if (test_errors == 0)
            $display("[TB] test_small_window: PASSED");
        else
            $display("[TB] test_small_window: FAILED");
    endtask

    //=========================================================================
    // Secuencia Principal
    //=========================================================================
    
    initial begin
        $display("\n");
        $display("+------------------------------------------------------------+");
        $display("|            TESTBENCH: axis_scope                           |");
        $display("+------------------------------------------------------------+");
        
        test_errors = 0;
        
        test_basic();
        test_pre_only();
        test_post_only();
        test_early_trigger();
        test_small_window();
        
        $display("\n");
        $display("+------------------------------------------------------------+");
        $display("|                    RESUMEN                                 |");
        $display("+------------------------------------------------------------+");
        
        if (test_errors == 0) begin
            $display("|  >>> ALL TESTS PASSED                                     |");
        end else begin
            $display("|  >>> FAILED: %3d errors                                    |", test_errors);
        end
        
        $display("+------------------------------------------------------------+");
        $display("\n>>> Simulacion completada <<<\n");
        $finish;
    end

    //=========================================================================
    // Watchdog
    //=========================================================================
    
    initial begin
        #(CLK_PERIOD * 1000000);
        $display("[ERROR] Watchdog timeout");
        $finish;
    end

endmodule
