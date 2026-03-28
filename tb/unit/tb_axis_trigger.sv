/**
 * @file tb_axis_trigger.sv
 * @brief Testbench unitario para el modulo axis_trigger
 *
 * Compara el comportamiento del RTL con vectores generados por
 * el modelo Python de referencia.
 */

`timescale 1ns/1ps

module tb_axis_trigger;

    //=========================================================================
    // Parametros
    //=========================================================================
    
    localparam real CLK_PERIOD = 8.0;  // 125 MHz
    localparam int DATA_WIDTH = 16;
    localparam int MAX_SAMPLES = 100000;
    localparam int PIPE_DELAY = 2;  // Latencia del pipeline RTL

    //=========================================================================
    // Imports
    //=========================================================================
    
    import axi_stream_pkg::*;

    //=========================================================================
    // Senales
    //=========================================================================
    
    logic aclk;
    logic aresetn;
    trigger_config_t config_i;
    
    logic [DATA_WIDTH-1:0] s_axis_tdata;
    logic s_axis_tvalid;
    logic s_axis_tready;
    
    logic [DATA_WIDTH-1:0] m_axis_tdata;
    logic m_axis_tvalid;
    logic m_axis_tready;
    
    logic trigger_out;

    //=========================================================================
    // Memorias de test
    //=========================================================================
    
    logic [DATA_WIDTH-1:0] stimulus_mem [0:MAX_SAMPLES-1];
    logic expected_mem [0:MAX_SAMPLES-1];
    
    int num_samples;
    int cfg_threshold;
    int cfg_mode;
    
    string vectors_dir;

    //=========================================================================
    // DUT
    //=========================================================================
    
    axis_trigger #(
        .DATA_WIDTH(DATA_WIDTH),
        .PIPE_STAGES(PIPE_DELAY)
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
    // Reloj
    //=========================================================================
    
    initial begin
        aclk = 0;
        forever #(CLK_PERIOD/2) aclk = ~aclk;
    end

    //=========================================================================
    // Estadisticas
    //=========================================================================
    
    int triggers_detected;
    int triggers_expected;
    int true_positives;
    int false_positives;
    int false_negatives;
    
    // Buffer para registrar triggers detectados
    logic trigger_history [0:MAX_SAMPLES-1];
    
    // Indice de la muestra siendo enviada
    int send_index;
    
    // Flag de test en progreso
    logic test_running;

    //=========================================================================
    // Monitor de triggers con compensacion de pipeline
    //=========================================================================
    
    // Pipeline de indices para rastrear que muestra corresponde a cada trigger
    int index_pipeline [0:PIPE_DELAY];
    
    always @(posedge aclk) begin
        if (!aresetn) begin
            for (int i = 0; i <= PIPE_DELAY; i++) begin
                index_pipeline[i] <= -1;
            end
        end else if (s_axis_tvalid && s_axis_tready) begin
            // Shift del pipeline de indices
            for (int i = PIPE_DELAY; i > 0; i--) begin
                index_pipeline[i] <= index_pipeline[i-1];
            end
            index_pipeline[0] <= send_index;
        end
    end
    
    // Capturar triggers y atribuirlos al indice correcto
    always @(posedge aclk) begin
        if (aresetn && m_axis_tvalid && m_axis_tready && test_running) begin
            if (trigger_out && index_pipeline[PIPE_DELAY-1] >= 0) begin
                // Declarar variable con automatic explicito
                automatic int trigger_idx;
                trigger_idx = index_pipeline[PIPE_DELAY-1] - 1;
                if (trigger_idx >= 0 && trigger_idx < MAX_SAMPLES) begin
                    trigger_history[trigger_idx] = 1;
                end
            end
        end
    end

    //=========================================================================
    // Tasks
    //=========================================================================
    
    task automatic read_config(string filename);
        int fd;
        string line;
        string param_name;
        int param_value;
        
        cfg_threshold = 500;
        cfg_mode = 0;
        num_samples = 1000;
        
        fd = $fopen(filename, "r");
        if (fd == 0) begin
            $display("[CONFIG] No se pudo abrir %s, usando defaults", filename);
            return;
        end
        
        while (!$feof(fd)) begin
            void'($fgets(line, fd));
            if (line.len() < 3 || line[0] == "/" || line[0] == "#") continue;
            
            if ($sscanf(line, "%s %d", param_name, param_value) == 2) begin
                case (param_name)
                    "THRESHOLD":   cfg_threshold = param_value;
                    "MODE":        cfg_mode = param_value;
                    "NUM_SAMPLES": num_samples = param_value;
                endcase
            end
        end
        $fclose(fd);
    endtask
    
    task automatic apply_reset();
        aresetn = 0;
        test_running = 0;
        repeat(5) @(posedge aclk);
        aresetn = 1;
        @(posedge aclk);
    endtask
    
    task automatic configure_trigger();
        config_i.enable    = 1;
        config_i.threshold = cfg_threshold;
        config_i.mode      = trigger_mode_e'(cfg_mode);
        config_i.ch_mask   = 2'b11;
        
        $display("[CONFIG] Trigger: threshold=%0d, mode=%s", 
                 cfg_threshold,
                 cfg_mode == 0 ? "RISING" :
                 cfg_mode == 1 ? "FALLING" :
                 cfg_mode == 2 ? "BOTH" : "LEVEL");
    endtask
    
    task automatic send_samples();
        $display("[TEST] Enviando %0d muestras...", num_samples);
        
        test_running = 1;
        send_index = 0;
        
        for (int i = 0; i < num_samples; i++) begin
            s_axis_tdata  = stimulus_mem[i];
            s_axis_tvalid = 1;
            
            @(posedge aclk);
            while (!s_axis_tready) @(posedge aclk);
            
            send_index = i + 1;
        end
        
        s_axis_tvalid = 0;
        
        // Esperar que el pipeline se vacia
        repeat(PIPE_DELAY + 10) @(posedge aclk);
        
        test_running = 0;
    endtask
    
    task automatic compare_results();
        triggers_detected = 0;
        triggers_expected = 0;
        true_positives = 0;
        false_positives = 0;
        false_negatives = 0;
        
        for (int i = 0; i < num_samples; i++) begin
            logic detected = trigger_history[i];
            logic expected = expected_mem[i];
            
            if (expected) triggers_expected++;
            if (detected) triggers_detected++;
            
            if (detected && expected) begin
                true_positives++;
            end else if (detected && !expected) begin
                false_positives++;
                if (false_positives <= 5)
                    $display("[%0t] FALSE POSITIVE en muestra %0d", $time, i);
            end else if (!detected && expected) begin
                false_negatives++;
                if (false_negatives <= 5)
                    $display("[%0t] FALSE NEGATIVE en muestra %0d", $time, i);
            end
        end
    endtask
    
    task automatic print_summary();
        int mismatches;
        mismatches = false_positives + false_negatives;
        
        $display("");
        $display("+-----------------------------------------------------------+");
        $display("|                 RESUMEN DE RESULTADOS                     |");
        $display("+-----------------------------------------------------------+");
        $display("|  Muestras procesadas:   %33d |", num_samples);
        $display("|  Triggers esperados:    %33d |", triggers_expected);
        $display("|  Triggers detectados:   %33d |", triggers_detected);
        $display("|  True Positives:        %33d |", true_positives);
        $display("|  False Positives:       %33d |", false_positives);
        $display("|  False Negatives:       %33d |", false_negatives);
        $display("+-----------------------------------------------------------+");
        
        if (mismatches == 0)
            $display("|  >>> PASS                                                |");
        else
            $display("|  >>> FAIL: %3d discrepancias                             |", mismatches);
        
        $display("+-----------------------------------------------------------+");
    endtask
    
    task automatic run_test(string tname);
        string stim_file, exp_file, cfg_file;
        
        stim_file = {vectors_dir, "/", tname, "_stimulus.hex"};
        exp_file  = {vectors_dir, "/", tname, "_expected.hex"};
        cfg_file  = {vectors_dir, "/", tname, "_config.txt"};
        
        $display("\n========== Test: %s ==========", tname);
        
        // Inicializar memorias
        for (int i = 0; i < MAX_SAMPLES; i++) begin
            stimulus_mem[i] = 0;
            expected_mem[i] = 0;
            trigger_history[i] = 0;
        end
        
        // Leer vectores
        read_config(cfg_file);
        
        $display("[LOAD] Stimulus: %s", stim_file);
        $readmemh(stim_file, stimulus_mem);
        
        $display("[LOAD] Expected: %s", exp_file);
        $readmemh(exp_file, expected_mem);
        
        // Ejecutar
        apply_reset();
        configure_trigger();
        m_axis_tready = 1;
        
        send_samples();
        compare_results();
        print_summary();
    endtask

    //=========================================================================
    // Secuencia principal
    //=========================================================================
    
    initial begin
        if (!$value$plusargs("VECTORS_DIR=%s", vectors_dir))
            vectors_dir = "../sim/vectors";
        
        $display("\n");
        $display("+-----------------------------------------------------------+");
        $display("|     TESTBENCH: axis_trigger (QuestaSim Flow)              |");
        $display("+-----------------------------------------------------------+");
        $display("Vectors directory: %s", vectors_dir);
        
        // Inicializar
        aresetn = 0;
        config_i = '0;
        s_axis_tdata = 0;
        s_axis_tvalid = 0;
        m_axis_tready = 1;
        test_running = 0;
        send_index = 0;
        
        // Ejecutar tests
        run_test("trigger_rising_ramp");
        run_test("trigger_falling_ramp");
        run_test("trigger_both_sine");
        run_test("trigger_rising_pulse");
        run_test("trigger_level_random");
        
        $display("\n>>> Simulacion completada <<<\n");
        $finish;
    end

    //=========================================================================
    // Watchdog
    //=========================================================================
    
    initial begin
        #(CLK_PERIOD * 2000000);
        $display("[ERROR] Watchdog timeout - simulacion abortada");
        $finish;
    end

endmodule
