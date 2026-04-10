/**
 * @file axi4_write_monitor.sv
 * @brief Monitor UVM para transacciones AXI4 Write
 *
 * Observa los canales AW, W y B para reconstruir transacciones
 * completas de escritura. Publica las transacciones capturadas
 * a traves de un analysis port.
 *
 * @note El monitor maneja transacciones out-of-order usando el campo ID
 *       para correlacionar las fases AW, W y B.
 */

class axi4_write_monitor extends uvm_monitor;

    //=========================================================================
    // UVM Factory
    //=========================================================================
    
    `uvm_component_utils(axi4_write_monitor)

    //=========================================================================
    // Ports y Handles
    //=========================================================================
    
    /// Analysis port para transacciones completas
    uvm_analysis_port #(axi4_write_seq_item) ap;
    
    /// Handle a la interface virtual
    virtual axi4_write_if vif;

    //=========================================================================
    // Estructuras Internas
    //=========================================================================
    
    /// Transacciones pendientes indexadas por ID
    axi4_write_seq_item pending_txns[int];
    
    /// Contador de beats por ID
    int beat_count[int];

    //=========================================================================
    // Constructor
    //=========================================================================
    
    function new(string name = "axi4_write_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    //=========================================================================
    // Build Phase
    //=========================================================================
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual axi4_write_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", "Virtual interface not found in config_db")
        end
    endfunction

    //=========================================================================
    // Run Phase
    //=========================================================================
    
    virtual task run_phase(uvm_phase phase);
        fork
            monitor_aw_channel();
            monitor_w_channel();
            monitor_b_channel();
        join
    endtask

    //=========================================================================
    // Monitor AW Channel
    //=========================================================================
    
    /**
     * @brief Captura transacciones del canal de direcciones
     *
     * Cuando detecta AWVALID && AWREADY, crea una nueva transaccion
     * pendiente y la almacena indexada por AWID.
     */
    virtual task monitor_aw_channel();
        axi4_write_seq_item txn;
        int id;
        
        forever begin
            @(vif.monitor_cb);
            
            if (vif.monitor_cb.awvalid && vif.monitor_cb.awready) begin
                txn = axi4_write_seq_item::type_id::create("txn");
                
                txn.id    = vif.monitor_cb.awid;
                txn.addr  = vif.monitor_cb.awaddr;
                txn.len   = vif.monitor_cb.awlen;
                txn.size  = vif.monitor_cb.awsize;
                txn.burst = vif.monitor_cb.awburst;
                txn.start_time = $time;
                
                // Dimensionar arrays
                txn.data = new[txn.len + 1];
                txn.strb = new[txn.len + 1];
                
                id = txn.id;
                pending_txns[id] = txn;
                beat_count[id] = 0;
                
                `uvm_info("AXI4_MON", $sformatf("AW: id=%0d addr=0x%08X len=%0d",
                          id, txn.addr, txn.len), UVM_HIGH)
            end
        end
    endtask

    //=========================================================================
    // Monitor W Channel
    //=========================================================================
    
    /**
     * @brief Captura beats de datos del canal W
     *
     * Acumula los beats en la transaccion pendiente correspondiente.
     * En AXI4, los beats W no llevan ID, se asume orden FIFO respecto a AW.
     */
    virtual task monitor_w_channel();
        int current_id;
        int bc;
        
        forever begin
            @(vif.monitor_cb);
            
            if (vif.monitor_cb.wvalid && vif.monitor_cb.wready) begin
                // Encontrar la transaccion pendiente mas antigua
                // En sistemas simples, solo hay una activa a la vez
                if (pending_txns.size() == 0) begin
                    `uvm_error("AXI4_MON", "W beat received but no pending AW transaction")
                    continue;
                end
                
                // Tomar el primer ID pendiente (FIFO order)
                foreach (pending_txns[id]) begin
                    current_id = id;
                    break;
                end
                
                bc = beat_count[current_id];
                
                if (bc > pending_txns[current_id].len) begin
                    `uvm_error("AXI4_MON", $sformatf("Too many W beats for id=%0d", current_id))
                    continue;
                end
                
                pending_txns[current_id].data[bc] = vif.monitor_cb.wdata;
                pending_txns[current_id].strb[bc] = vif.monitor_cb.wstrb;
                beat_count[current_id] = bc + 1;
                
                `uvm_info("AXI4_MON", $sformatf("W: beat=%0d data=0x%016X%s",
                          bc, vif.monitor_cb.wdata,
                          vif.monitor_cb.wlast ? " LAST" : ""), UVM_HIGH)
                
                // Verificar WLAST
                if (vif.monitor_cb.wlast) begin
                    if (bc != pending_txns[current_id].len) begin
                        `uvm_error("AXI4_MON", $sformatf(
                            "WLAST at beat %0d but expected at %0d",
                            bc, pending_txns[current_id].len))
                    end
                end
            end
        end
    endtask

    //=========================================================================
    // Monitor B Channel
    //=========================================================================
    
    /**
     * @brief Captura respuestas del canal B
     *
     * Cuando recibe BVALID && BREADY, completa la transaccion
     * y la publica a traves del analysis port.
     */
    virtual task monitor_b_channel();
        int id;
        axi4_write_seq_item txn;
        
        forever begin
            @(vif.monitor_cb);
            
            if (vif.monitor_cb.bvalid && vif.monitor_cb.bready) begin
                id = vif.monitor_cb.bid;
                
                if (!pending_txns.exists(id)) begin
                    `uvm_error("AXI4_MON", $sformatf("B response for unknown id=%0d", id))
                    continue;
                end
                
                txn = pending_txns[id];
                txn.resp = vif.monitor_cb.bresp;
                txn.end_time = $time;
                txn.burst_bytes = txn.get_burst_bytes();
                
                `uvm_info("AXI4_MON", $sformatf("B: id=%0d resp=%s [%0t - %0t]",
                          id,
                          txn.resp == 0 ? "OKAY" : "ERROR",
                          txn.start_time, txn.end_time), UVM_MEDIUM)
                
                // Publicar transaccion completa
                ap.write(txn);
                
                // Limpiar estructuras
                pending_txns.delete(id);
                beat_count.delete(id);
            end
        end
    endtask

    //=========================================================================
    // Report Phase
    //=========================================================================
    
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        if (pending_txns.size() > 0) begin
            `uvm_warning("AXI4_MON", $sformatf(
                "%0d incomplete transactions at end of simulation",
                pending_txns.size()))
        end
    endfunction

endclass : axi4_write_monitor
