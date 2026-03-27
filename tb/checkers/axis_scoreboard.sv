/**
 * @file axis_scoreboard.sv
 * @brief Scoreboard para comparación automática RTL vs Modelo ESL
 *
 * Compara transacciones capturadas del DUT RTL contra las esperadas
 * del modelo de referencia ESL. Este es el corazón de la verificación.
 *
 * @par Arquitectura del Testbench Híbrido:
 * @code
 *   ┌──────────────────┐       ┌──────────────────┐
 *   │  Modelo ESL      │       │  DUT RTL         │
 *   │  (Python)        │       │                  │
 *   └────────┬─────────┘       └────────┬─────────┘
 *            │                          │
 *            │ Expected                 │ Actual
 *            │ Transactions             │ Transactions
 *            ▼                          ▼
 *   ┌─────────────────────────────────────────────┐
 *   │              SCOREBOARD                     │  ◄── ESTE MÓDULO
 *   │                                             │
 *   │  ┌─────────────┐    ┌─────────────┐        │
 *   │  │  Expected   │    │   Actual    │        │
 *   │  │   Queue     │    │   Queue     │        │
 *   │  └──────┬──────┘    └──────┬──────┘        │
 *   │         │                  │               │
 *   │         └────────┬─────────┘               │
 *   │                  │                         │
 *   │                  ▼                         │
 *   │         ┌─────────────────┐                │
 *   │         │   Comparador    │                │
 *   │         └────────┬────────┘                │
 *   │                  │                         │
 *   │                  ▼                         │
 *   │         ┌─────────────────┐                │
 *   │         │  Match/Mismatch │                │
 *   │         │    Statistics   │                │
 *   │         └─────────────────┘                │
 *   └─────────────────────────────────────────────┘
 * @endcode
 */

`ifndef AXIS_SCOREBOARD_SV
`define AXIS_SCOREBOARD_SV

import transaction_pkg::*;

/**
 * @brief Scoreboard para comparación de transacciones AXI-Stream
 */
class axis_scoreboard #(
    parameter int DATA_WIDTH = 16
);
    
    //=========================================================================
    // Estadísticas
    //=========================================================================
    
    typedef struct {
        int unsigned total_expected;
        int unsigned total_actual;
        int unsigned matches;
        int unsigned mismatches;
        int unsigned data_errors;
        int unsigned tlast_errors;
        int unsigned missing;
        int unsigned extra;
    } scoreboard_stats_t;
    
    //=========================================================================
    // Propiedades
    //=========================================================================
    
    /** @brief Cola de transacciones esperadas (del modelo ESL) */
    axis_transaction_t expected_queue[$];
    
    /** @brief Mailbox de transacciones actuales (del DUT) */
    mailbox #(axis_transaction_t) actual_mbx;
    
    /** @brief Estadísticas */
    scoreboard_stats_t stats;
    
    /** @brief Historial de errores */
    verify_result_t error_log[$];
    
    /** @brief Máximo de errores a loggear */
    int max_errors_to_log;
    
    /** @brief Flag para logging verbose */
    bit verbose;
    
    /** @brief Nombre del scoreboard */
    string name;
    
    /** @brief Flag para detener */
    protected bit stop_flag;
    
    /** @brief Tolerancia para comparación (±tolerance) */
    int tolerance;
    
    //=========================================================================
    // Constructor
    //=========================================================================
    
    /**
     * @brief Constructor
     *
     * @param actual_mbx       Mailbox con transacciones del DUT
     * @param name             Nombre para logging
     * @param verbose          Habilitar mensajes de debug
     * @param max_errors       Máximo de errores a registrar
     * @param tolerance        Tolerancia numérica
     */
    function new(
        mailbox #(axis_transaction_t) actual_mbx,
        string name = "scoreboard",
        bit verbose = 0,
        int max_errors = 100,
        int tolerance = 0
    );
        this.actual_mbx = actual_mbx;
        this.name = name;
        this.verbose = verbose;
        this.max_errors_to_log = max_errors;
        this.tolerance = tolerance;
        this.stop_flag = 0;
        reset_stats();
    endfunction
    
    //=========================================================================
    // Métodos para cargar esperados
    //=========================================================================
    
    /**
     * @brief Agrega una transacción esperada
     */
    function void add_expected(axis_transaction_t txn);
        expected_queue.push_back(txn);
        stats.total_expected++;
    endfunction
    
    /**
     * @brief Carga esperados desde archivo .hex generado por Python
     *
     * @param filename Ruta al archivo .hex
     * @return Número de transacciones cargadas
     */
    function int load_expected_from_hex(string filename);
        int fd;
        int count = 0;
        logic [DATA_WIDTH-1:0] data;
        axis_transaction_t txn;
        
        fd = $fopen(filename, "r");
        if (fd == 0) begin
            $error("[%s] No se pudo abrir %s", name, filename);
            return 0;
        end
        
        while (!$feof(fd)) begin
            if ($fscanf(fd, "%h\n", data) == 1) begin
                txn = create_axis_data(data, 0, count);
                add_expected(txn);
                count++;
            end
        end
        
        $fclose(fd);
        
        if (verbose)
            $display("[%s] Cargadas %0d transacciones de %s", 
                     name, count, filename);
        
        return count;
    endfunction
    
    /**
     * @brief Carga esperados desde array
     */
    function void load_expected_from_array(logic [DATA_WIDTH-1:0] data[]);
        foreach (data[i]) begin
            add_expected(create_axis_data(data[i], 0, i));
        end
    endfunction
    
    //=========================================================================
    // Proceso de comparación
    //=========================================================================
    
    /**
     * @brief Proceso principal del scoreboard
     *
     * Compara continuamente transacciones actuales vs esperadas.
     */
    task run();
        axis_transaction_t actual_txn;
        axis_transaction_t expected_txn;
        verify_result_t result;
        
        stop_flag = 0;
        
        while (!stop_flag) begin
            // Esperar transacción actual del DUT
            actual_mbx.get(actual_txn);
            stats.total_actual++;
            
            // Comparar con esperada
            if (expected_queue.size() > 0) begin
                expected_txn = expected_queue.pop_front();
                result = compare_transactions(expected_txn, actual_txn);
                
                if (result.result == CMP_MATCH) begin
                    stats.matches++;
                    if (verbose)
                        $display("[%0t] %s: MATCH #%0d: data=0x%04X",
                                 $time, name, stats.matches, actual_txn.data);
                end else begin
                    stats.mismatches++;
                    log_error(result);
                end
            end else begin
                // Transacción extra (no esperada)
                stats.extra++;
                result.result = CMP_MISMATCH;
                result.actual = actual_txn.data;
                result.expected = 'X;
                result.index = stats.total_actual - 1;
                result.message = "Extra transaction (not expected)";
                log_error(result);
            end
        end
        
        // Verificar transacciones faltantes
        check_remaining();
    endtask
    
    /**
     * @brief Detiene el scoreboard
     */
    function void stop();
        stop_flag = 1;
    endfunction
    
    /**
     * @brief Verifica transacciones restantes en cola de esperados
     */
    function void check_remaining();
        if (expected_queue.size() > 0) begin
            stats.missing = expected_queue.size();
            $warning("[%s] %0d transacciones esperadas no recibidas",
                     name, stats.missing);
        end
    endfunction
    
    //=========================================================================
    // Comparación
    //=========================================================================
    
    /**
     * @brief Compara dos transacciones
     */
    protected function verify_result_t compare_transactions(
        axis_transaction_t expected,
        axis_transaction_t actual
    );
        verify_result_t result;
        int diff;
        
        result.expected = expected.data;
        result.actual = actual.data;
        result.index = actual.seq_num;
        result.timestamp = actual.timestamp;
        
        // Comparar datos con tolerancia
        diff = $signed(actual.data) - $signed(expected.data);
        if (diff < 0) diff = -diff;
        
        if (diff <= tolerance) begin
            // Comparar TLAST
            if (expected.last !== actual.last) begin
                result.result = CMP_MISMATCH;
                result.message = $sformatf("TLAST mismatch: exp=%b, act=%b",
                                          expected.last, actual.last);
                stats.tlast_errors++;
            end else begin
                result.result = CMP_MATCH;
                result.message = "OK";
            end
        end else begin
            result.result = CMP_MISMATCH;
            result.message = $sformatf("Data mismatch: exp=0x%04X, act=0x%04X (diff=%0d)",
                                      expected.data, actual.data, diff);
            stats.data_errors++;
        end
        
        return result;
    endfunction
    
    /**
     * @brief Registra un error
     */
    protected function void log_error(verify_result_t result);
        if (error_log.size() < max_errors_to_log) begin
            error_log.push_back(result);
        end
        
        $error("[%0t] %s: %s at index %0d",
               $time, name, result.message, result.index);
    endfunction
    
    //=========================================================================
    // Estadísticas y reportes
    //=========================================================================
    
    /**
     * @brief Resetea estadísticas
     */
    function void reset_stats();
        stats = '{default: 0};
        expected_queue.delete();
        error_log.delete();
    endfunction
    
    /**
     * @brief Retorna 1 si pasó todos los checks
     */
    function bit passed();
        return (stats.mismatches == 0) && 
               (stats.missing == 0) && 
               (stats.extra == 0);
    endfunction
    
    /**
     * @brief Imprime resumen de resultados
     */
    function void print_summary();
        string status;
        
        status = passed() ? "PASS" : "FAIL";
        
        $display("");
        $display("╔════════════════════════════════════════════════════════════╗");
        $display("║           SCOREBOARD: %-20s              ║", name);
        $display("╠════════════════════════════════════════════════════════════╣");
        $display("║  Transacciones esperadas:  %-30d  ║", stats.total_expected);
        $display("║  Transacciones recibidas:  %-30d  ║", stats.total_actual);
        $display("║  ──────────────────────────────────────────────────────    ║");
        $display("║  Matches:                  %-30d  ║", stats.matches);
        $display("║  Mismatches:               %-30d  ║", stats.mismatches);
        $display("║    - Errores de datos:     %-30d  ║", stats.data_errors);
        $display("║    - Errores de TLAST:     %-30d  ║", stats.tlast_errors);
        $display("║  Faltantes:                %-30d  ║", stats.missing);
        $display("║  Extra:                    %-30d  ║", stats.extra);
        $display("╠════════════════════════════════════════════════════════════╣");
        $display("║  >>> RESULTADO: %-10s                                 ║", status);
        $display("╚════════════════════════════════════════════════════════════╝");
        $display("");
        
        // Mostrar primeros errores si hay
        if (!passed() && error_log.size() > 0) begin
            $display("Primeros errores:");
            for (int i = 0; i < error_log.size() && i < 5; i++) begin
                $display("  [%0d] %s", error_log[i].index, error_log[i].message);
            end
            if (error_log.size() > 5)
                $display("  ... y %0d errores más", error_log.size() - 5);
        end
    endfunction
    
    /**
     * @brief Retorna estadísticas
     */
    function scoreboard_stats_t get_stats();
        return stats;
    endfunction

endclass : axis_scoreboard

`endif // AXIS_SCOREBOARD_SV
