/**
 * @file trigger_scoreboard.sv
 * @brief Scoreboard para verificación del módulo trigger
 *
 * Compara las transacciones observadas en la entrada y salida del trigger
 * con los valores esperados. Usa el modelo Python/TLM como referencia.
 */

class trigger_scoreboard extends uvm_scoreboard;

    //=========================================================================
    // Factory Registration
    //=========================================================================
    
    `uvm_component_utils(trigger_scoreboard)
    
    //=========================================================================
    // Analysis Ports
    //=========================================================================
    
    /// Puerto para transacciones de entrada (stimulus)
    uvm_analysis_imp_input #(axis_seq_item, trigger_scoreboard) input_export;
    
    /// Puerto para transacciones de salida (DUT output)
    uvm_analysis_imp_output #(axis_seq_item, trigger_scoreboard) output_export;
    
    /// Puerto para eventos de trigger
    uvm_analysis_imp_trigger #(bit, trigger_scoreboard) trigger_export;
    
    //=========================================================================
    // Configuración
    //=========================================================================
    
    /// Umbral configurado
    int threshold = 500;
    
    /// Modo de trigger
    int mode = 0;  // RISING
    
    /// Profundidad del pipeline (para delay de comparación)
    int pipeline_depth = 2;
    
    /// Valores esperados (cargados desde archivo)
    bit expected_triggers[$];
    
    //=========================================================================
    // Estadísticas
    //=========================================================================
    
    int unsigned samples_received;
    int unsigned triggers_expected;
    int unsigned triggers_detected;
    int unsigned true_positives;
    int unsigned false_positives;
    int unsigned false_negatives;
    
    //=========================================================================
    // Estado interno
    //=========================================================================
    
    /// Cola de triggers detectados (para alinear con expected)
    bit trigger_queue[$];
    
    /// Índice actual
    int current_index;
    
    //=========================================================================
    // Métodos
    //=========================================================================
    
    function new(string name = "trigger_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        samples_received  = 0;
        triggers_expected = 0;
        triggers_detected = 0;
        true_positives    = 0;
        false_positives   = 0;
        false_negatives   = 0;
        current_index     = 0;
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        input_export   = new("input_export", this);
        output_export  = new("output_export", this);
        trigger_export = new("trigger_export", this);
    endfunction
    
    /**
     * @brief Carga valores esperados desde archivo
     */
    function bit load_expected(string filename);
        int fd;
        string line;
        int value;
        
        expected_triggers.delete();
        
        fd = $fopen(filename, "r");
        if (fd == 0) begin
            `uvm_error("SCOREBOARD", $sformatf("Cannot open file: %s", filename))
            return 0;
        end
        
        while (!$feof(fd)) begin
            if ($fgets(line, fd)) begin
                if (line.len() < 1 || line[0] == "/" || line[0] == "#") continue;
                
                if ($sscanf(line, "%d", value) == 1) begin
                    expected_triggers.push_back(value != 0);
                    if (value != 0) triggers_expected++;
                end
            end
        end
        
        $fclose(fd);
        
        `uvm_info("SCOREBOARD", $sformatf("Cargados %0d valores esperados, %0d triggers",
                  expected_triggers.size(), triggers_expected), UVM_MEDIUM)
        
        return 1;
    endfunction
    
    /**
     * @brief Recibe transacción de entrada
     */
    virtual function void write_input(axis_seq_item item);
        samples_received++;
    endfunction
    
    /**
     * @brief Recibe transacción de salida
     */
    virtual function void write_output(axis_seq_item item);
        // Las transacciones de salida llegan con delay del pipeline
    endfunction
    
    /**
     * @brief Recibe evento de trigger
     */
    virtual function void write_trigger(bit trigger);
        trigger_queue.push_back(trigger);
        
        if (trigger) begin
            triggers_detected++;
        end
        
        // Comparar con esperado
        compare_trigger();
    endfunction
    
    /**
     * @brief Compara trigger detectado vs esperado
     */
    protected function void compare_trigger();
        if (current_index >= expected_triggers.size()) return;
        
        // Considerar delay del pipeline
        int compare_index = current_index;
        
        if (compare_index < 0 || compare_index >= expected_triggers.size()) return;
        
        bit expected = expected_triggers[compare_index];
        bit detected = trigger_queue.size() > 0 ? trigger_queue.pop_front() : 0;
        
        if (detected && expected) begin
            true_positives++;
        end else if (detected && !expected) begin
            false_positives++;
            `uvm_warning("SCOREBOARD", 
                $sformatf("FALSE POSITIVE en índice %0d", compare_index))
        end else if (!detected && expected) begin
            false_negatives++;
            `uvm_warning("SCOREBOARD", 
                $sformatf("FALSE NEGATIVE en índice %0d", compare_index))
        end
        
        current_index++;
    endfunction
    
    /**
     * @brief Check phase - verificar resultados finales
     */
    virtual function void check_phase(uvm_phase phase);
        int mismatches = false_positives + false_negatives;
        
        if (mismatches > 0) begin
            `uvm_error("SCOREBOARD", $sformatf(
                "FAIL: %0d mismatches (FP=%0d, FN=%0d)",
                mismatches, false_positives, false_negatives))
        end else begin
            `uvm_info("SCOREBOARD", "PASS: Todos los triggers coinciden", UVM_LOW)
        end
    endfunction
    
    /**
     * @brief Report phase - imprimir estadísticas
     */
    virtual function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD", $sformatf(
            "\n" +
            "+-----------------------------------------------------------+\n" +
            "|                 RESULTADOS DEL SCOREBOARD                 |\n" +
            "+-----------------------------------------------------------+\n" +
            "|  Samples recibidos:     %33d |\n" +
            "|  Triggers esperados:    %33d |\n" +
            "|  Triggers detectados:   %33d |\n" +
            "|  True Positives:        %33d |\n" +
            "|  False Positives:       %33d |\n" +
            "|  False Negatives:       %33d |\n" +
            "+-----------------------------------------------------------+",
            samples_received, triggers_expected, triggers_detected,
            true_positives, false_positives, false_negatives), UVM_LOW)
    endfunction
    
endclass : trigger_scoreboard

// Declaraciones de analysis_imp con sufijos
`uvm_analysis_imp_decl(_input)
`uvm_analysis_imp_decl(_output)
`uvm_analysis_imp_decl(_trigger)
