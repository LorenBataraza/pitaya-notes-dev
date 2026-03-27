/**
 * @file tb_hybrid_trigger.sv
 * @brief Testbench híbrido ESL+RTL para axis_trigger
 *
 * Este testbench demuestra la arquitectura de simulación mixta:
 * - Driver convierte transacciones a señales RTL
 * - Monitor captura señales y genera transacciones
 * - Scoreboard compara con modelo ESL de referencia
 *
 * @par Arquitectura:
 * @code
 *   ┌──────────────────────────────────────────────────────────────┐
 *   │                    TESTBENCH HÍBRIDO                         │
 *   │                                                              │
 *   │  ┌──────────────────┐                                        │
 *   │  │  Generador de    │  (Vector files from Python)            │
 *   │  │  Estímulos       │                                        │
 *   │  └────────┬─────────┘                                        │
 *   │           │ axis_transaction_t                               │
 *   │           ▼                                                  │
 *   │  ┌──────────────────┐       ┌──────────────────┐            │
 *   │  │   axis_driver    │       │   axis_monitor   │            │
 *   │  │   (TXN→Signals)  │       │   (Signals→TXN)  │            │
 *   │  └────────┬─────────┘       └────────▲─────────┘            │
 *   │           │                          │                       │
 *   │           ▼                          │                       │
 *   │  ┌────────────────────────────────────────────┐             │
 *   │  │              axis_trigger (DUT)            │             │
 *   │  │         + axis_trigger_sva (bind)          │             │
 *   │  └────────────────────────────────────────────┘             │
 *   │                                                              │
 *   │  ┌──────────────────┐       ┌──────────────────┐            │
 *   │  │  Expected Data   │       │    Scoreboard    │            │
 *   │  │  (from Python)   │──────►│   (Comparador)   │            │
 *   │  └──────────────────┘       └──────────────────┘            │
 *   └──────────────────────────────────────────────────────────────┘
 * @endcode
 */

`timescale 1ns/1ps

// Includes
`include "rtl_enhanced/common/transaction_pkg.sv"
`include "rtl/common/axi_stream_pkg.sv"
`include "tb/adapters/axis_txn_driver.sv"
`include "tb/adapters/axis_txn_monitor.sv"
`include "tb/checkers/axis_scoreboard.sv"

module tb_hybrid_trigger;

    //=========================================================================
    // Parámetros
    //=========================================================================
    
    localparam real CLK_PERIOD = 8.0;  // 125 MHz
    localparam int DATA_WIDTH = 16;
    localparam int MAX_SAMPLES = 10000;
    
    //=========================================================================
    // Imports
    //=========================================================================
    
    import transaction_pkg::*;
    import axi_stream_pkg::*;
    
    //=========================================================================
    // Señales
    //=========================================================================
    
    logic aclk;
    logic aresetn;
    
    // Configuración
    trigger_config_t config_i;
    
    //=========================================================================
    // Interfaces
    //=========================================================================
    
    // Interfaz de entrada (driver → DUT)
    axis_master_if #(DATA_WIDTH) axis_in_if (aclk, aresetn);
    
    // Interfaz de salida (DUT → monitor)
    axis_monitor_if #(DATA_WIDTH) axis_out_if (aclk, aresetn);
    
    //=========================================================================
    // DUT
    //=========================================================================
    
    axis_trigger #(
        .DATA_WIDTH(DATA_WIDTH),
        .PIPE_STAGES(2)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .config_i(config_i),
        
        // Conexión con interfaz de entrada
        .s_axis_tdata(axis_in_if.tdata),
        .s_axis_tvalid(axis_in_if.tvalid),
        .s_axis_tready(axis_in_if.tready),
        
        // Conexión con interfaz de salida
        .m_axis_tdata(axis_out_if.tdata),
        .m_axis_tvalid(axis_out_if.tvalid),
        .m_axis_tready(axis_out_if.tready),
        
        .trigger_out(trigger_out)
    );
    
    logic trigger_out;
    
    // Conexiones de la interfaz de monitor
    assign axis_out_if.tlast = 1'b0;  // El trigger no usa TLAST
    
    //=========================================================================
    // Reloj
    //=========================================================================
    
    initial begin
        aclk = 1'b0;
        forever #(CLK_PERIOD/2) aclk = ~aclk;
    end
    
    //=========================================================================
    // Componentes del testbench
    //=========================================================================
    
    // Mailbox para transacciones capturadas
    mailbox #(axis_transaction_t) captured_txns;
    
    // Driver y Monitor
    axis_txn_driver #(DATA_WIDTH) driver;
    axis_txn_monitor #(DATA_WIDTH) monitor;
    
    // Scoreboard
    axis_scoreboard #(DATA_WIDTH) scoreboard;
    
    //=========================================================================
    // Tareas de utilidad
    //=========================================================================
    
    task automatic apply_reset();
        aresetn = 1'b0;
        axis_out_if.tready = 1'b1;
        repeat(10) @(posedge aclk);
        aresetn = 1'b1;
        @(posedge aclk);
    endtask
    
    task automatic configure_trigger(
        input logic enable,
        input logic [DATA_WIDTH-1:0] threshold,
        input trigger_mode_e mode
    );
        config_i.enable = enable;
        config_i.threshold = threshold;
        config_i.mode = mode;
        config_i.ch_mask = 2'b11;
        @(posedge aclk);
        
        $display("[TB] Trigger configured: enable=%b, threshold=%0d, mode=%s",
                 enable, threshold, mode.name());
    endtask
    
    //=========================================================================
    // Test con vectores del modelo Python
    //=========================================================================
    
    task automatic run_vector_test(string test_name);
        string stim_file, exp_file;
        int num_expected;
        
        $display("\n========== Test: %s ==========", test_name);
        
        // Paths de archivos
        stim_file = {"../sim/vectors/", test_name, "_stimulus.hex"};
        exp_file  = {"../sim/vectors/", test_name, "_expected.hex"};
        
        // Resetear componentes
        scoreboard.reset_stats();
        driver.reset();
        
        // Cargar esperados
        num_expected = scoreboard.load_expected_from_hex(exp_file);
        $display("[TB] Loaded %0d expected values from %s", num_expected, exp_file);
        
        // Cargar y enviar estímulos
        begin
            int fd;
            logic [DATA_WIDTH-1:0] data;
            int count = 0;
            
            fd = $fopen(stim_file, "r");
            if (fd == 0) begin
                $error("[TB] Cannot open %s", stim_file);
                return;
            end
            
            while (!$feof(fd)) begin
                if ($fscanf(fd, "%h\n", data) == 1) begin
                    driver.send(create_axis_data(data, 0, count));
                    count++;
                end
            end
            
            $fclose(fd);
            $display("[TB] Sent %0d samples from %s", count, stim_file);
        end
        
        // Esperar que se procesen
        driver.wait_empty();
        repeat(100) @(posedge aclk);
        
        // Detener monitor y scoreboard
        monitor.stop();
        scoreboard.stop();
        scoreboard.check_remaining();
        
        // Resultados
        scoreboard.print_summary();
    endtask
    
    //=========================================================================
    // Test directo (sin archivos)
    //=========================================================================
    
    task automatic run_direct_test();
        axis_transaction_t txn;
        
        $display("\n========== Test Directo ==========");
        
        // Configurar trigger
        configure_trigger(1'b1, 16'd500, TRIG_RISING);
        
        // Cargar esperados manualmente
        // Para una rampa 0→1023, el trigger debería ocurrir cuando cruza 500
        for (int i = 0; i < 1024; i++) begin
            scoreboard.add_expected(create_axis_data(i));
        end
        
        // Enviar rampa
        for (int i = 0; i < 1024; i++) begin
            driver.send(create_axis_data(i));
        end
        
        driver.wait_empty();
        repeat(100) @(posedge aclk);
        
        monitor.stop();
        scoreboard.stop();
        scoreboard.print_summary();
    endtask
    
    //=========================================================================
    // Secuencia principal
    //=========================================================================
    
    initial begin
        $display("\n");
        $display("╔════════════════════════════════════════════════════════════╗");
        $display("║     TESTBENCH HÍBRIDO: axis_trigger                        ║");
        $display("║     Simulación mixta ESL + RTL                             ║");
        $display("╚════════════════════════════════════════════════════════════╝");
        
        // Inicializar
        captured_txns = new();
        
        driver = new(axis_in_if.driver, "driver", 0);
        monitor = new(axis_out_if.monitor, captured_txns, "monitor", 0);
        scoreboard = new(captured_txns, "scoreboard", 0);
        
        // Valores iniciales
        config_i = '0;
        axis_out_if.tready = 1'b1;
        
        // Reset
        apply_reset();
        
        // Iniciar procesos en paralelo
        fork
            driver.run();
            monitor.run();
            scoreboard.run();
        join_none
        
        // Ejecutar tests
        run_direct_test();
        
        // Tests con vectores de Python (si existen)
        // run_vector_test("trigger_rising_ramp");
        // run_vector_test("trigger_both_sine");
        
        // Finalizar
        repeat(100) @(posedge aclk);
        
        $display("\n>>> Simulación completada <<<\n");
        $finish;
    end
    
    //=========================================================================
    // Monitor de triggers
    //=========================================================================
    
    int trigger_count = 0;
    int last_trigger_sample = -1;
    
    always @(posedge aclk) begin
        if (aresetn && trigger_out) begin
            trigger_count++;
            $display("[TB] Trigger #%0d detected", trigger_count);
        end
    end
    
    //=========================================================================
    // Watchdog
    //=========================================================================
    
    initial begin
        #(CLK_PERIOD * 100000);
        $error("[TB] Watchdog timeout");
        $finish;
    end

endmodule : tb_hybrid_trigger
