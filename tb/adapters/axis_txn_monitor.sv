/**
 * @file axis_txn_monitor.sv
 * @brief Monitor de señales AXI-Stream a transacciones
 *
 * Captura señales RTL del protocolo AXI-Stream y las convierte
 * a transacciones de alto nivel. Este es el "Monitor" del testbench híbrido.
 *
 * @par Arquitectura del Testbench Híbrido:
 * @code
 *   ┌──────────────────┐
 *   │  DUT RTL         │
 *   └────────┬─────────┘
 *            │ Señales: tdata, tvalid, tready, tlast
 *            ▼
 *   ┌──────────────────┐
 *   │ axis_txn_monitor │  ◄── ESTE MÓDULO
 *   │  (Adaptador)     │
 *   └────────┬─────────┘
 *            │ Transacciones
 *            ▼
 *   ┌──────────────────┐
 *   │  Checker         │  ──► Comparación con modelo ESL
 *   └──────────────────┘
 * @endcode
 */

`ifndef AXIS_TXN_MONITOR_SV
`define AXIS_TXN_MONITOR_SV

import transaction_pkg::*;

/**
 * @brief Interfaz AXI-Stream para monitoreo pasivo
 */
interface axis_monitor_if #(
    parameter int DATA_WIDTH = 16
) (
    input logic aclk,
    input logic aresetn
);
    logic [DATA_WIDTH-1:0] tdata;
    logic                  tvalid;
    logic                  tready;
    logic                  tlast;
    
    // Clocking block para el monitor (solo inputs)
    clocking mon_cb @(posedge aclk);
        default input #1step;
        input tdata, tvalid, tready, tlast;
    endclocking
    
    // Modport para el monitor
    modport monitor (clocking mon_cb, input aresetn);
    
endinterface : axis_monitor_if


/**
 * @brief Monitor de transacciones AXI-Stream
 *
 * Clase que captura señales RTL y las convierte a transacciones.
 */
class axis_txn_monitor #(
    parameter int DATA_WIDTH = 16
);
    
    //=========================================================================
    // Propiedades
    //=========================================================================
    
    /** @brief Interfaz virtual al bus */
    virtual axis_monitor_if #(DATA_WIDTH).monitor vif;
    
    /** @brief Mailbox para enviar transacciones capturadas */
    mailbox #(axis_transaction_t) txn_out;
    
    /** @brief Contador de transacciones capturadas */
    int unsigned txn_count;
    
    /** @brief Flag para habilitar logging */
    bit verbose;
    
    /** @brief Nombre del monitor para logging */
    string name;
    
    /** @brief Flag para detener el monitor */
    protected bit stop_flag;
    
    /** @brief Contador de ciclos para timestamp */
    int unsigned cycle_count;
    
    //=========================================================================
    // Constructor
    //=========================================================================
    
    /**
     * @brief Constructor
     *
     * @param vif      Interfaz virtual
     * @param txn_out  Mailbox de salida para transacciones
     * @param name     Nombre para logging
     * @param verbose  Habilitar mensajes de debug
     */
    function new(
        virtual axis_monitor_if #(DATA_WIDTH).monitor vif,
        mailbox #(axis_transaction_t) txn_out,
        string name = "axis_monitor",
        bit verbose = 0
    );
        this.vif = vif;
        this.txn_out = txn_out;
        this.name = name;
        this.verbose = verbose;
        this.txn_count = 0;
        this.stop_flag = 0;
        this.cycle_count = 0;
    endfunction
    
    //=========================================================================
    // Métodos públicos
    //=========================================================================
    
    /**
     * @brief Proceso principal del monitor (task bloqueante)
     *
     * Debe ser llamado como fork desde el testbench.
     * Captura transacciones del bus y las envía al mailbox.
     */
    task run();
        axis_transaction_t txn;
        
        // Esperar reset
        wait(vif.aresetn === 1'b1);
        @(vif.mon_cb);
        
        stop_flag = 0;
        
        while (!stop_flag) begin
            @(vif.mon_cb);
            cycle_count++;
            
            // Detectar handshake
            if (vif.mon_cb.tvalid && vif.mon_cb.tready) begin
                txn.data = vif.mon_cb.tdata;
                txn.last = vif.mon_cb.tlast;
                txn.valid = 1'b1;
                txn.txn_type = vif.mon_cb.tlast ? AXIS_TXN_LAST : AXIS_TXN_DATA;
                txn.timestamp = cycle_count;
                txn.seq_num = txn_count++;
                
                // Enviar transacción al checker
                txn_out.put(txn);
                
                if (verbose)
                    $display("[%0t] %s: Captured %s", 
                             $time, name, axis_txn_to_string(txn));
            end
        end
    endtask
    
    /**
     * @brief Detiene el monitor
     */
    function void stop();
        stop_flag = 1;
    endfunction
    
    /**
     * @brief Resetea el monitor
     */
    function void reset();
        txn_count = 0;
        cycle_count = 0;
        stop_flag = 0;
    endfunction
    
    /**
     * @brief Retorna el número de transacciones capturadas
     */
    function int get_txn_count();
        return txn_count;
    endfunction

endclass : axis_txn_monitor


/**
 * @brief Monitor de trigger (captura eventos de trigger)
 */
class trigger_monitor;
    
    //=========================================================================
    // Propiedades
    //=========================================================================
    
    /** @brief Señal de trigger a monitorear */
    virtual interface trigger_if vif;
    
    /** @brief Mailbox para eventos de trigger */
    mailbox #(trigger_transaction_t) trigger_events;
    
    /** @brief Contador de eventos */
    int unsigned event_count;
    
    /** @brief Flag para logging */
    bit verbose;
    
    string name;
    
    protected bit stop_flag;
    protected int unsigned cycle_count;
    
    //=========================================================================
    // Constructor
    //=========================================================================
    
    function new(
        virtual trigger_if vif,
        mailbox #(trigger_transaction_t) trigger_events,
        string name = "trigger_monitor",
        bit verbose = 0
    );
        this.vif = vif;
        this.trigger_events = trigger_events;
        this.name = name;
        this.verbose = verbose;
        this.event_count = 0;
        this.stop_flag = 0;
    endfunction
    
    //=========================================================================
    // Métodos
    //=========================================================================
    
    task run();
        trigger_transaction_t txn;
        
        wait(vif.aresetn === 1'b1);
        @(posedge vif.aclk);
        
        stop_flag = 0;
        
        while (!stop_flag) begin
            @(posedge vif.aclk);
            cycle_count++;
            
            // Detectar flanco de trigger
            if (vif.trigger_out && !$past(vif.trigger_out)) begin
                txn.sample_index = cycle_count;
                txn.sample_value = vif.current_sample;
                txn.prev_value = vif.prev_sample;
                txn.threshold = vif.threshold;
                txn.mode = vif.mode;
                txn.timestamp = cycle_count;
                
                trigger_events.put(txn);
                event_count++;
                
                if (verbose)
                    $display("[%0t] %s: Trigger event #%0d at sample %0d",
                             $time, name, event_count, cycle_count);
            end
        end
    endtask
    
    function void stop();
        stop_flag = 1;
    endfunction

endclass : trigger_monitor


/**
 * @brief Interfaz para señales de trigger
 */
interface trigger_if (
    input logic aclk,
    input logic aresetn
);
    logic        trigger_out;
    logic [15:0] current_sample;
    logic [15:0] prev_sample;
    logic [15:0] threshold;
    logic [2:0]  mode;
    
    modport monitor (
        input aclk, aresetn,
        input trigger_out, current_sample, prev_sample, threshold, mode
    );
endinterface : trigger_if

`endif // AXIS_TXN_MONITOR_SV
