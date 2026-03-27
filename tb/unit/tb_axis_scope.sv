/**
 * @file tb_axis_scope.sv
 * @brief Testbench para el módulo axis_scope
 *
 * Verifica la funcionalidad del buffer de captura estilo osciloscopio:
 * - Buffer circular con pre-trigger
 * - Captura post-trigger
 * - Máquina de estados
 * - Transferencia de datos capturados
 *
 * @par Escenarios de prueba:
 * - Captura básica con trigger
 * - Solo pre-trigger (pre_samples = N, post_samples = 0)
 * - Solo post-trigger (pre_samples = 0, post_samples = N)
 * - Trigger temprano (menos muestras de pre que las configuradas)
 * - Múltiples triggers (solo el primero debe contar)
 * - Backpressure durante transferencia
 */

`timescale 1ns/1ps

module tb_axis_scope;

    //=========================================================================
    // Imports
    //=========================================================================
    
    import axi_stream_pkg::*;

    //=========================================================================
    // Parámetros
    //=========================================================================
    
    localparam real CLK_PERIOD = 8.0;  // 125 MHz
    
    // Parámetros del DUT
    localparam int DATA_WIDTH   = DSP_DATA_WIDTH;  // 16
    localparam int BUFFER_DEPTH = 4096;
    localparam int NUM_CH       = NUM_CHANNELS;    // 2
    
    // Parámetros de test
    localparam int DEFAULT_PRE  = 100;
    localparam int DEFAULT_POST = 200;

    //=========================================================================
    // Señales
    //=========================================================================
    
    logic aclk;
    logic aresetn;
    
    // Configuración y estado
    scope_config_t config_i;
    scope_status_t status_o;
    
    // Trigger
    logic trigger_in;
    
    // AXI-Stream Slave (entrada)
    logic signed [DATA_WIDTH-1:0] s_axis_tdata;
    logic                         s_axis_tvalid;
    logic                         s_axis_tready;
    
    // AXI-Stream Master (salida)
    logic signed [DATA_WIDTH-1:0] m_axis_tdata;
    logic                         m_axis_tvalid;
    logic                         m_axis_tready;
    logic                         m_axis_tlast;

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
        
        // AXI-Stream Slave
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        
        // AXI-Stream Master
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tlast  (m_axis_tlast)
    );

    //=========================================================================
    // Generación de reloj
    //=========================================================================
    
    initial begin
        aclk = 1'b0;
        forever #(CLK_PERIOD/2) aclk = ~aclk;
    end

    //=========================================================================
    // Variables de verificación
    //=========================================================================
    
    // Almacenamiento de datos enviados
    logic signed [DATA_WIDTH-1:0] sent_data[$];
    int sent_count;
    
    // Almacenamiento de datos recibidos
    logic signed [DATA_WIDTH-1:0] received_data[$];
    int received_count;
    
    // Índice del trigger
    int trigger_index;
    
    // Banderas de estado
    logic capture_done;

    //=========================================================================
    // Monitor de salida
    //=========================================================================
    
    always_ff @(posedge aclk) begin
        if (aresetn && m_axis_tvalid && m_axis_tready) begin
            received_data.push_back(m_axis_tdata);
            received_count++;
            
            if (m_axis_tlast) begin
                capture_done <= 1'b1;
                $display("[MON] TLAST received. Total samples: %0d", received_count);
            end
        end
    end

    //=========================================================================
    // Tareas de utilidad
    //=========================================================================
    
    task automatic apply_reset();
        aresetn = 1'b0;
        config_i = '0;
        trigger_in = 1'b0;
        s_axis_tdata = '0;
        s_axis_tvalid = 1'b0;
        m_axis_tready = 1'b1;
        
        sent_data.delete();
        received_data.delete();
        sent_count = 0;
        received_count = 0;
        trigger_index = -1;
        capture_done = 1'b0;
        
        repeat(10) @(posedge aclk);
        aresetn = 1'b1;
        @(posedge aclk);
    endtask
    
    task automatic configure_scope(
        input logic [15:0] pre_samples,
        input logic [15:0] post_samples
    );
        config_i.enable = 1'b1;
        config_i.arm = 1'b0;
        config_i.pre_samples = pre_samples;
        config_i.post_samples = post_samples;
        @(posedge aclk);
        
        $display("[TB] Scope configured: pre=%0d, post=%0d", pre_samples, post_samples);
    endtask
    
    task automatic arm_scope();
        config_i.arm = 1'b1;
        @(posedge aclk);
        config_i.arm = 1'b0;
        
        // Esperar a que esté armado
        wait(status_o.armed);
        $display("[TB] Scope armed");
    endtask
    
    task automatic send_sample(
        input logic signed [DATA_WIDTH-1:0] data
    );
        s_axis_tdata = data;
        s_axis_tvalid = 1'b1;
        
        do @(posedge aclk);
        while (!s_axis_tready);
        
        sent_data.push_back(data);
        sent_count++;
        
        s_axis_tvalid = 1'b0;
    endtask
    
    task automatic send_continuous_data(
        input int count,
        input int trigger_at = -1  // -1 = sin trigger
    );
        for (int i = 0; i < count; i++) begin
            automatic logic signed [DATA_WIDTH-1:0] sample;
            sample = i[DATA_WIDTH-1:0];
            
            send_sample(sample);
            
            // Generar trigger en el momento indicado
            if (i == trigger_at) begin
                trigger_in = 1'b1;
                trigger_index = i;
                @(posedge aclk);
                trigger_in = 1'b0;
                $display("[TB] Trigger at sample %0d", i);
            end
        end
    endtask
    
    task automatic wait_capture_done(input int timeout = 50000);
        int count = 0;
        
        while (!capture_done && count < timeout) begin
            @(posedge aclk);
            count++;
        end
        
        if (count >= timeout)
            $error("[TB] Timeout waiting for capture completion");
    endtask
    
    task automatic verify_capture(
        input int expected_pre,
        input int expected_post
    );
        int expected_total;
        int expected_first_idx;
        int errors = 0;
        
        expected_total = expected_pre + expected_post;
        expected_first_idx = trigger_index - expected_pre;
        
        $display("[TB] Verification:");
        $display("[TB]   Expected samples: %0d (pre=%0d, post=%0d)",
                 expected_total, expected_pre, expected_post);
        $display("[TB]   Received samples: %0d", received_count);
        $display("[TB]   Trigger at: %0d, first sample index: %0d",
                 trigger_index, expected_first_idx);
        
        // Verificar cantidad
        if (received_count != expected_total) begin
            $error("[TB] Sample count mismatch: expected %0d, got %0d",
                   expected_total, received_count);
            errors++;
        end
        
        // Verificar contenido
        for (int i = 0; i < received_count && i < received_data.size(); i++) begin
            automatic int expected_idx;
            automatic logic signed [DATA_WIDTH-1:0] expected_val;
            
            expected_idx = expected_first_idx + i;
            if (expected_idx >= 0 && expected_idx < sent_data.size()) begin
                expected_val = sent_data[expected_idx];
                
                if (received_data[i] !== expected_val) begin
                    if (errors < 10) begin  // Limitar mensajes de error
                        $error("[TB] Data mismatch at %0d: expected %0d, got %0d",
                               i, expected_val, received_data[i]);
                    end
                    errors++;
                end
            end
        end
        
        if (errors == 0)
            $display("[TB] VERIFICATION PASSED");
        else
            $error("[TB] VERIFICATION FAILED: %0d errors", errors);
    endtask

    //=========================================================================
    // Tests
    //=========================================================================
    
    task automatic test_basic_capture();
        $display("\n========== TEST: Basic Capture ==========");
        
        apply_reset();
        configure_scope(DEFAULT_PRE, DEFAULT_POST);
        arm_scope();
        
        // Enviar datos con trigger en medio
        send_continuous_data(500, 200);  // Trigger en muestra 200
        
        // Esperar captura completa
        wait_capture_done();
        
        // Verificar
        verify_capture(DEFAULT_PRE, DEFAULT_POST);
    endtask
    
    task automatic test_pre_only();
        $display("\n========== TEST: Pre-trigger Only ==========");
        
        apply_reset();
        configure_scope(150, 0);  // Solo pre-trigger
        arm_scope();
        
        send_continuous_data(300, 200);
        
        wait_capture_done();
        verify_capture(150, 0);
    endtask
    
    task automatic test_post_only();
        $display("\n========== TEST: Post-trigger Only ==========");
        
        apply_reset();
        configure_scope(0, 150);  // Solo post-trigger
        arm_scope();
        
        send_continuous_data(300, 50);  // Trigger temprano
        
        wait_capture_done();
        verify_capture(0, 150);
    endtask
    
    task automatic test_early_trigger();
        $display("\n========== TEST: Early Trigger ==========");
        
        // Trigger antes de tener suficientes muestras de pre
        
        apply_reset();
        configure_scope(100, 100);
        arm_scope();
        
        // Trigger en muestra 30 (solo hay 30 muestras de pre disponibles)
        send_continuous_data(300, 30);
        
        wait_capture_done();
        
        // Debería capturar lo que hay disponible
        $display("[TB] Early trigger: expected ~%0d pre samples available", 30);
    endtask
    
    task automatic test_multiple_triggers();
        $display("\n========== TEST: Multiple Triggers (ignore after first) ==========");
        
        apply_reset();
        configure_scope(50, 100);
        arm_scope();
        
        // Enviar datos con múltiples triggers
        for (int i = 0; i < 400; i++) begin
            automatic logic signed [DATA_WIDTH-1:0] sample;
            sample = i[DATA_WIDTH-1:0];
            send_sample(sample);
            
            // Primer trigger
            if (i == 100) begin
                trigger_in = 1'b1;
                trigger_index = i;
                @(posedge aclk);
                trigger_in = 1'b0;
                $display("[TB] First trigger at %0d", i);
            end
            
            // Segundo trigger (debería ignorarse)
            if (i == 120) begin
                trigger_in = 1'b1;
                @(posedge aclk);
                trigger_in = 1'b0;
                $display("[TB] Second trigger at %0d (should be ignored)", i);
            end
        end
        
        wait_capture_done();
        verify_capture(50, 100);  // Verificar que usó el primer trigger
    endtask
    
    task automatic test_backpressure_output();
        $display("\n========== TEST: Output Backpressure ==========");
        
        apply_reset();
        configure_scope(50, 50);
        arm_scope();
        
        // Habilitar backpressure aleatorio en la salida
        fork
            begin
                forever begin
                    @(posedge aclk);
                    m_axis_tready = ($urandom_range(0, 9) > 3);  // 60% ready
                end
            end
            
            begin
                send_continuous_data(200, 100);
                wait_capture_done();
            end
        join_any
        disable fork;
        
        // Restaurar ready
        m_axis_tready = 1'b1;
        repeat(100) @(posedge aclk);
        
        $display("[TB] Backpressure test: received %0d samples", received_count);
        
        if (received_count == 100)  // pre + post
            $display("[TB] TEST PASSED: Backpressure handled correctly");
        else
            $error("[TB] TEST FAILED: Expected 100 samples");
    endtask
    
    task automatic test_state_transitions();
        $display("\n========== TEST: State Transitions ==========");
        
        apply_reset();
        
        // Verificar IDLE inicial
        if (status_o.armed || status_o.triggered || status_o.done)
            $error("[TB] Initial state incorrect");
        else
            $display("[TB] Initial state: IDLE - OK");
        
        configure_scope(20, 20);
        arm_scope();
        
        // Verificar ARMED
        if (!status_o.armed)
            $error("[TB] Not armed after arm command");
        else
            $display("[TB] State: ARMED - OK");
        
        // Enviar datos y trigger
        send_continuous_data(100, 50);
        
        // Esperar trigger detectado
        repeat(10) @(posedge aclk);
        if (!status_o.triggered)
            $warning("[TB] triggered flag not set");
        else
            $display("[TB] State: TRIGGERED - OK");
        
        wait_capture_done();
        
        // Verificar DONE
        if (!status_o.done)
            $error("[TB] done flag not set after capture");
        else
            $display("[TB] State: DONE - OK");
    endtask

    //=========================================================================
    // Secuencia principal
    //=========================================================================
    
    initial begin
        $display("\n");
        $display("+------------------------------------------------------------+");
        $display("|            TESTBENCH: axis_scope                           |");
        $display("+------------------------------------------------------------+");
        
        // Ejecutar tests
        test_basic_capture();
        test_pre_only();
        test_post_only();
        test_early_trigger();
        test_multiple_triggers();
        test_backpressure_output();
        test_state_transitions();
        
        // Resumen final
        repeat(100) @(posedge aclk);
        
        $display("\n");
        $display("+------------------------------------------------------------+");
        $display("|                    FIN DE TESTS                            |");
        $display("+------------------------------------------------------------+");
        
        $finish;
    end

    //=========================================================================
    // Watchdog
    //=========================================================================
    
    initial begin
        #(CLK_PERIOD * 100000);
        $error("[TB] Watchdog timeout");
        $finish;
    end

endmodule : tb_axis_scope
