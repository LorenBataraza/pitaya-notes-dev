/**
 * @file axis_txn_driver.sv
 * @brief Adaptador de transacciones a señales AXI-Stream
 *
 * Convierte transacciones de alto nivel (del modelo ESL) a señales
 * RTL del protocolo AXI-Stream. Este es el "Driver" del testbench híbrido.
 *
 * @par Arquitectura del Testbench Híbrido:
 * @code
 *   ┌──────────────────┐
 *   │  Cola de         │  ◄── Transacciones del modelo ESL
 *   │  Transacciones   │
 *   └────────┬─────────┘
 *            │
 *            ▼
 *   ┌──────────────────┐
 *   │  axis_txn_driver │  ◄── ESTE MÓDULO
 *   │  (Adaptador)     │
 *   └────────┬─────────┘
 *            │
 *            ▼
 *   ┌──────────────────┐
 *   │  Señales RTL     │  ──► tdata, tvalid, tready, tlast
 *   └──────────────────┘
 * @endcode
 *
 * @par Uso:
 * @code
 *   axis_txn_driver driver;
 *   driver = new(aclk, aresetn);
 *   
 *   // Desde el testbench
 *   driver.send(create_axis_data(16'h1234));
 *   driver.send(create_axis_last(16'h5678));
 * @endcode
 */

`ifndef AXIS_TXN_DRIVER_SV
`define AXIS_TXN_DRIVER_SV

import transaction_pkg::*;
import axi_stream_pkg::*;

/**
 * @brief Interfaz AXI-Stream para conexión con DUT
 */
interface axis_master_if #(
    parameter int DATA_WIDTH = 16
) (
    input logic aclk,
    input logic aresetn
);
    logic [DATA_WIDTH-1:0] tdata;
    logic                  tvalid;
    logic                  tready;
    logic                  tlast;
    
    // Clocking block para el driver
    clocking drv_cb @(posedge aclk);
        default input #1step output #1;
        output tdata, tvalid, tlast;
        input  tready;
    endclocking
    
    // Modport para el driver
    modport driver (clocking drv_cb, input aresetn);
    
    // Modport para el DUT
    modport slave (
        input  tdata, tvalid, tlast,
        output tready
    );
    
endinterface : axis_master_if


/**
 * @brief Driver de transacciones AXI-Stream
 *
 * Clase que maneja la conversión de transacciones a señales RTL.
 */
class axis_txn_driver #(
    parameter int DATA_WIDTH = 16
);
    
    //=========================================================================
    // Propiedades
    //=========================================================================
    
    /** @brief Interfaz virtual al bus */
    virtual axis_master_if #(DATA_WIDTH).driver vif;
    
    /** @brief Cola de transacciones pendientes */
    mailbox #(axis_transaction_t) txn_queue;
    
    /** @brief Contador de transacciones enviadas */
    int unsigned txn_count;
    
    /** @brief Flag para habilitar logging */
    bit verbose;
    
    /** @brief Nombre del driver para logging */
    string name;
    
    //=========================================================================
    // Constructor
    //=========================================================================
    
    /**
     * @brief Constructor
     *
     * @param vif      Interfaz virtual
     * @param name     Nombre para logging
     * @param verbose  Habilitar mensajes de debug
     */
    function new(
        virtual axis_master_if #(DATA_WIDTH).driver vif,
        string name = "axis_driver",
        bit verbose = 0
    );
        this.vif = vif;
        this.name = name;
        this.verbose = verbose;
        this.txn_queue = new();
        this.txn_count = 0;
    endfunction
    
    //=========================================================================
    // Métodos públicos
    //=========================================================================
    
    /**
     * @brief Envía una transacción (non-blocking)
     *
     * Agrega la transacción a la cola para ser procesada.
     *
     * @param txn Transacción a enviar
     */
    function void send(axis_transaction_t txn);
        txn.seq_num = txn_count++;
        txn_queue.put(txn);
        
        if (verbose)
            $display("[%0t] %s: Queued %s", $time, name, axis_txn_to_string(txn));
    endfunction
    
    /**
     * @brief Envía múltiples transacciones desde un array
     *
     * @param data_array Array de datos a enviar
     * @param mark_last  Marcar última transacción con TLAST
     */
    function void send_array(
        logic [DATA_WIDTH-1:0] data_array[],
        bit mark_last = 1
    );
        for (int i = 0; i < data_array.size(); i++) begin
            axis_transaction_t txn;
            
            if (mark_last && i == data_array.size() - 1)
                txn = create_axis_last(data_array[i]);
            else
                txn = create_axis_data(data_array[i]);
            
            send(txn);
        end
    endfunction
    
    /**
     * @brief Proceso principal del driver (task bloqueante)
     *
     * Debe ser llamado como fork desde el testbench.
     * Procesa transacciones de la cola y las convierte a señales.
     */
    task run();
        axis_transaction_t txn;
        
        // Estado inicial
        vif.drv_cb.tdata  <= '0;
        vif.drv_cb.tvalid <= 1'b0;
        vif.drv_cb.tlast  <= 1'b0;
        
        // Esperar reset
        wait(vif.aresetn === 1'b1);
        @(vif.drv_cb);
        
        forever begin
            // Obtener próxima transacción
            txn_queue.get(txn);
            
            // Procesar según tipo
            case (txn.txn_type)
                AXIS_TXN_DATA, AXIS_TXN_LAST: begin
                    drive_data(txn);
                end
                
                AXIS_TXN_IDLE: begin
                    drive_idle(txn);
                end
                
                AXIS_TXN_BACKPRESSURE: begin
                    // No hacer nada, dejar que el receptor maneje
                    @(vif.drv_cb);
                end
            endcase
        end
    endtask
    
    /**
     * @brief Espera a que la cola esté vacía
     *
     * @param timeout_cycles Timeout en ciclos de reloj
     * @return 1 si se vació, 0 si timeout
     */
    task automatic wait_empty(int timeout_cycles = 10000);
        int count = 0;
        
        while (txn_queue.num() > 0 && count < timeout_cycles) begin
            @(vif.drv_cb);
            count++;
        end
        
        // Esperar unos ciclos extra para que se complete la última transacción
        repeat(10) @(vif.drv_cb);
    endtask
    
    /**
     * @brief Resetea el driver
     */
    task reset();
        vif.drv_cb.tdata  <= '0;
        vif.drv_cb.tvalid <= 1'b0;
        vif.drv_cb.tlast  <= 1'b0;
        
        // Vaciar cola
        while (txn_queue.try_get(axis_transaction_t'(0)));
        
        txn_count = 0;
    endtask
    
    //=========================================================================
    // Métodos privados
    //=========================================================================
    
    /**
     * @brief Envía un dato por el bus
     */
    protected task drive_data(axis_transaction_t txn);
        // Poner datos en el bus
        vif.drv_cb.tdata  <= txn.data;
        vif.drv_cb.tvalid <= 1'b1;
        vif.drv_cb.tlast  <= txn.last;
        
        // Esperar handshake
        do begin
            @(vif.drv_cb);
        end while (vif.drv_cb.tready !== 1'b1);
        
        if (verbose)
            $display("[%0t] %s: Sent %s", $time, name, axis_txn_to_string(txn));
        
        // Limpiar después del handshake
        vif.drv_cb.tvalid <= 1'b0;
        vif.drv_cb.tlast  <= 1'b0;
    endtask
    
    /**
     * @brief Genera ciclos idle
     */
    protected task drive_idle(axis_transaction_t txn);
        vif.drv_cb.tvalid <= 1'b0;
        vif.drv_cb.tlast  <= 1'b0;
        
        // Usar seq_num como número de ciclos idle
        repeat(txn.seq_num) @(vif.drv_cb);
    endtask

endclass : axis_txn_driver

`endif // AXIS_TXN_DRIVER_SV
