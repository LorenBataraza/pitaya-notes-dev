/**
 * @file tb_axis_trigger.sv
 * @brief Testbench unitario para el módulo axis_trigger con soporte QuestaSim
 *
 * Este testbench verifica el comportamiento funcional del detector
 * de eventos comparando automáticamente con vectores generados por
 * el modelo Python de referencia.
 *
 * @par Características:
 * - Lectura de estímulos desde archivos .hex ($readmemh)
 * - Comparación automática con respuesta esperada
 * - Compatible con flujo de regresión QuestaSim
 * - Scoreboard con estadísticas detalladas
 *
 * @par Uso:
 * @code
 *   vsim tb_axis_trigger +VECTORS_DIR=../sim/vectors +TEST=trigger_rising_ramp
 * @endcode
 */

`timescale 1ns/1ps

module tb_axis_trigger;

    //=========================================================================
    // Parámetros del testbench
    //=========================================================================
    
    /** @brief Período del reloj en ns (125 MHz) */
    localparam real CLK_PERIOD = 8.0;
    
    /** @brief Ancho de datos del DUT */
    localparam int DATA_WIDTH = 16;
    
    /** @brief Máximo número de muestras soportado */
    localparam int MAX_SAMPLES = 100000;
    
    /** @brief Timeout para tests en ciclos de reloj */
    localparam int TEST_TIMEOUT = 200000;

    //=========================================================================
    // Imports
    //=========================================================================
    
    import axi_stream_pkg::*;

    //=========================================================================
    // Señales de interfaz
    //=========================================================================
    
    // Reloj y reset
    logic aclk;
    logic aresetn;
    
    // Configuración
    trigger_config_t config_i;
    
    // AXI-Stream Slave
    logic signed [DATA_WIDTH-1:0] s_axis_tdata;
    logic                         s_axis_tvalid;
    logic                         s_axis_tready;
    
    // AXI-Stream Master
    logic signed [DATA_WIDTH-1:0] m_axis_tdata;
    logic                         m_axis_tvalid;
    logic                         m_axis_tready;
    
    // Salida de trigger
    logic trigger_out;

    //=========================================================================
    // Variables para lectura de vectores
    //=========================================================================
    
    // Memorias para estímulos y respuestas esperadas
    logic [DATA_WIDTH-1:0] stimulus_mem [0:MAX_SAMPLES-1];
    logic                  expected_mem [0:MAX_SAMPLES-1];
    
    // Configuración del test (leída de archivo)
    int cfg_threshold;
    int cfg_mode;
    int cfg_num_samples;
    
    // Directorio de vectores (pasado por +VECTORS_DIR)
    string vectors_dir;
    string test_name;
    
    // Número de muestras actual
    int num_samples;

    //=========================================================================
    // DUT (Device Under Test)
    //=========================================================================
    
    axis_trigger #(
        .DATA_WIDTH(DATA_WIDTH),
        .PIPE_STAGES(2)
    ) dut (
        .aclk(aclk),
        .aresetn(aresetn),
        .config_i(config_i),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .trigger_out(trigger_out)
    );

    //=========================================================================
    // Generación de reloj
    //=========================================================================
    
    initial begin
        aclk = 1'b0;
        forever #(CLK_PERIOD/2) aclk = ~aclk;
    end

    //=========================================================================
    // Scoreboard y estadísticas
    //=========================================================================
    
    /** @brief Contadores de estadísticas */
    int total_samples;
    int triggers_detected;
    int triggers_expected;
    int true_positives;   // Trigger correcto
    int false_positives;  // Trigger cuando no debía
    int false_negatives;  // No trigger cuando debía
    int mismatches;
    
    /** @brief Cola de triggers esperados con delay del pipeline */
    logic expected_queue[$];
    
    /**
     * @brief Monitor del scoreboard
     *
     * Compara triggers detectados vs esperados considerando
     * la latencia del pipeline.
     */
    always @(posedge aclk) begin
        if (aresetn && s_axis_tvalid && s_axis_tready) begin
            // Agregar valor esperado a la cola (con delay del pipeline)
            if (total_samples < num_samples) begin
                expected_queue.push_back(expected_mem[total_samples]);
            end
            total_samples++;
        end
        
        // Verificar trigger (con delay del pipeline de 2 ciclos)
        if (aresetn && expected_queue.size() >= 2) begin
            logic expected_trigger;
            expected_trigger = expected_queue.pop_front();
            
            if (expected_trigger)
                triggers_expected++;
            
            // Comparar
            if (trigger_out && expected_trigger) begin
                true_positives++;
                triggers_detected++;
            end else if (trigger_out && !expected_trigger) begin
                false_positives++;
                triggers_detected++;
                mismatches++;
                $display("[%0t] FALSE POSITIVE: Trigger en muestra %0d", 
                         $time, total_samples - 2);
            end else if (!trigger_out && expected_trigger) begin
                false_negatives++;
                mismatches++;
                $display("[%0t] FALSE NEGATIVE: Esperado trigger en muestra %0d", 
                         $time, total_samples - 2);
            end
        end
    end

    //=========================================================================
    // Tasks de utilidad
    //=========================================================================
    
    /**
     * @brief Lee configuración desde archivo
     */
    task automatic read_config(string filename);
        int fd;
        string line;
        string param_name;
        int param_value;
        
        fd = $fopen(filename, "r");
        if (fd == 0) begin
            $display("[ERROR] No se pudo abrir %s", filename);
            return;
        end
        
        while (!$feof(fd)) begin
            void'($fgets(line, fd));
            
            // Ignorar comentarios y líneas vacías
            if (line[0] == "/" || line.len() < 3)
                continue;
            
            // Parsear "NOMBRE VALOR"
            if ($sscanf(line, "%s %d", param_name, param_value) == 2) begin
                case (param_name)
                    "THRESHOLD":   cfg_threshold = param_value;
                    "MODE":        cfg_mode = param_value;
                    "NUM_SAMPLES": cfg_num_samples = param_value;
                    "ENABLE":      ; // Ya habilitado por defecto
                endcase
            end
        end
        
        $fclose(fd);
        
        $display("[CONFIG] Threshold=%0d, Mode=%0d, Samples=%0d",
                 cfg_threshold, cfg_mode, cfg_num_samples);
    endtask
    
    /**
     * @brief Aplica reset al sistema
     */
    task automatic apply_reset(int cycles = 5);
        aresetn = 1'b0;
        repeat(cycles) @(posedge aclk);
        aresetn = 1'b1;
        @(posedge aclk);
    endtask
    
    /**
     * @brief Configura el trigger desde valores leídos
     */
    task automatic configure_from_file();
        config_i.enable    = 1'b1;
        config_i.threshold = cfg_threshold;
        config_i.mode      = trigger_mode_e'(cfg_mode);
        config_i.ch_mask   = 2'b11;
        
        $display("[CONFIG] Trigger configurado: threshold=%0d, mode=%s",
                 cfg_threshold, config_i.mode.name());
    endtask
    
    /**
     * @brief Envía todas las muestras del vector de estímulo
     */
    task automatic send_all_samples();
        $display("[TEST] Enviando %0d muestras...", num_samples);
        
        for (int i = 0; i < num_samples; i++) begin
            s_axis_tdata  = stimulus_mem[i];
            s_axis_tvalid = 1'b1;
            
            do @(posedge aclk);
            while (!s_axis_tready);
            
            @(posedge aclk);
        end
        
        s_axis_tvalid = 1'b0;
        
        // Esperar que se procese el pipeline
        repeat(10) @(posedge aclk);
    endtask
    
    /**
     * @brief Imprime resumen de resultados
     */
    function automatic void print_summary();
        real accuracy;
        
        if (triggers_expected > 0)
            accuracy = 100.0 * true_positives / triggers_expected;
        else
            accuracy = 100.0;
        
        $display("");
        $display("+-----------------------------------------------------------+");
        $display("|                 RESUMEN DE RESULTADOS                     |");
        $display("+-------------------------------------------------------------+");
        $display("|  Test:            %-40s |", test_name);
        $display("|  Muestras:        %-40d |", total_samples);
        $display("+-------------------------------------------------------------+");
        $display("|  Triggers esperados:    %-33d |", triggers_expected);
        $display("|  Triggers detectados:   %-33d |", triggers_detected);
        $display("|  True Positives:        %-33d |", true_positives);
        $display("|  False Positives:       %-33d |", false_positives);
        $display("|  False Negatives:       %-33d |", false_negatives);
        $display("|  Accuracy:              %-32.1f%% |", accuracy);
        $display("+-------------------------------------------------------------+");
        if (mismatches == 0) begin
            $display("|  >>> PASS: Todos los triggers coinciden                    |");
        end else begin
            $display("|  >>> FAIL: %3d discrepancias encontradas                   |", mismatches);
        end
        $display("+-------------------------------------------------------------+");
        $display("");
    endfunction

    //=========================================================================
    // Test principal con vectores de archivo
    //=========================================================================
    
    task automatic run_vector_test(string tname);
        string stim_file, exp_file, cfg_file;
        
        test_name = tname;
        
        // Construir paths de archivos
        stim_file = {vectors_dir, "/", tname, "_stimulus.hex"};
        exp_file  = {vectors_dir, "/", tname, "_expected.hex"};
        cfg_file  = {vectors_dir, "/", tname, "_config.txt"};
        
        $display("\n========== Test: %s ==========", tname);
        
        // Leer configuración
        read_config(cfg_file);
        num_samples = cfg_num_samples;
        
        // Leer vectores
        $display("[LOAD] Leyendo estímulos: %s", stim_file);
        $readmemh(stim_file, stimulus_mem);
        
        $display("[LOAD] Leyendo esperados: %s", exp_file);
        $readmemh(exp_file, expected_mem);
        
        // Resetear contadores
        total_samples = 0;
        triggers_detected = 0;
        triggers_expected = 0;
        true_positives = 0;
        false_positives = 0;
        false_negatives = 0;
        mismatches = 0;
        expected_queue.delete();
        
        // Ejecutar test
        apply_reset();
        configure_from_file();
        
        m_axis_tready = 1'b1;  // Siempre ready en salida
        
        send_all_samples();
        
        // Procesar queue restante
        while (expected_queue.size() > 0) begin
            @(posedge aclk);
        end
        
        print_summary();
    endtask

    //=========================================================================
    // Secuencia principal
    //=========================================================================
    
    initial begin
        // Obtener parámetros de línea de comandos
        if (!$value$plusargs("VECTORS_DIR=%s", vectors_dir)) begin
            vectors_dir = "../sim/vectors";
        end
        
        $display("\n");
        $display("+-----------------------------------------------------------+");
        $display("|     TESTBENCH: axis_trigger (QuestaSim Flow)             |");
        $display("+-----------------------------------------------------------+");
        $display("Vectors directory: %s", vectors_dir);
        
        // Valores iniciales
        aresetn       = 1'b0;
        config_i      = '0;
        s_axis_tdata  = '0;
        s_axis_tvalid = 1'b0;
        m_axis_tready = 1'b1;
        
        // Ejecutar suite de tests
        run_vector_test("trigger_rising_ramp");
        run_vector_test("trigger_falling_ramp");
        run_vector_test("trigger_both_sine");
        run_vector_test("trigger_rising_pulse");
        run_vector_test("trigger_level_random");
        
        // Fin
        $display("\n>>> Simulación completada <<<\n");
        $finish;
    end

    //=========================================================================
    // Watchdog
    //=========================================================================
    
    initial begin
        #(CLK_PERIOD * TEST_TIMEOUT);
        $display("[ERROR] Watchdog timeout - simulación abortada");
        $finish;
    end

    //=========================================================================
    // Dump de señales para debug
    //=========================================================================
    
    initial begin
        $dumpfile("tb_axis_trigger.vcd");
        $dumpvars(0, tb_axis_trigger);
    end

endmodule : tb_axis_trigger
