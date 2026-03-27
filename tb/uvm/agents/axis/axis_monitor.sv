/**
 * @file axis_monitor.sv
 * @brief Monitor AXI-Stream para UVM
 *
 * Observa las transacciones en la interface AXI-Stream y las envía
 * a los análisis components (scoreboard, coverage) via analysis ports.
 */

class axis_monitor extends uvm_monitor;

    //=========================================================================
    // Factory Registration
    //=========================================================================
    
    `uvm_component_utils(axis_monitor)
    
    //=========================================================================
    // Interface y puertos
    //=========================================================================
    
    /// Interface virtual
    virtual axis_if vif;
    
    /// Puerto de análisis para transacciones observadas
    uvm_analysis_port #(axis_seq_item) ap;
    
    //=========================================================================
    // Configuración
    //=========================================================================
    
    /// Nombre para logging
    string monitor_name = "AXIS_MON";
    
    /// Habilitar logging verbose
    bit verbose = 0;
    
    //=========================================================================
    // Estadísticas
    //=========================================================================
    
    int unsigned transactions_observed;
    int unsigned packets_observed;
    
    //=========================================================================
    // Métodos
    //=========================================================================
    
    /**
     * @brief Constructor
     */
    function new(string name = "axis_monitor", uvm_component parent = null);
        super.new(name, parent);
        transactions_observed = 0;
        packets_observed = 0;
    endfunction
    
    /**
     * @brief Build phase - crear analysis port y obtener interface
     */
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        ap = new("ap", this);
        
        if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal(monitor_name, "No se encontró interface virtual")
        end
    endfunction
    
    /**
     * @brief Run phase - observar transacciones
     */
    virtual task run_phase(uvm_phase phase);
        int beat_index = 0;
        int packet_id = 0;
        
        @(posedge vif.aresetn);
        
        `uvm_info(monitor_name, "Monitor iniciado", UVM_MEDIUM)
        
        forever begin
            axis_seq_item item;
            
            @(vif.mon_cb);
            
            // Detectar handshake
            if (vif.mon_cb.tvalid && vif.mon_cb.tready) begin
                // Crear y poblar item
                item = axis_seq_item::type_id::create("observed_item");
                item.data       = vif.mon_cb.tdata;
                item.tlast      = vif.mon_cb.tlast;
                item.delay      = 0;
                item.packet_id  = packet_id;
                item.beat_index = beat_index;
                item.timestamp  = $time;
                
                // Enviar al analysis port
                ap.write(item);
                
                transactions_observed++;
                beat_index++;
                
                if (verbose) begin
                    `uvm_info(monitor_name, 
                        $sformatf("Observado: %s", item.convert2string()), UVM_HIGH)
                end
                
                // Detectar fin de paquete
                if (vif.mon_cb.tlast) begin
                    packets_observed++;
                    packet_id++;
                    beat_index = 0;
                    
                    `uvm_info(monitor_name, 
                        $sformatf("Fin de paquete %0d", packet_id-1), UVM_MEDIUM)
                end
            end
        end
    endtask
    
    /**
     * @brief Report phase - imprimir estadísticas
     */
    virtual function void report_phase(uvm_phase phase);
        `uvm_info(monitor_name, $sformatf(
            "Estadísticas: %0d transacciones, %0d paquetes",
            transactions_observed, packets_observed), UVM_LOW)
    endfunction
    
endclass : axis_monitor

/**
 * @brief Monitor específico para salida de trigger
 *
 * Además de las transacciones AXI-Stream, observa la señal trigger_out.
 */
class trigger_monitor extends axis_monitor;

    `uvm_component_utils(trigger_monitor)
    
    /// Señal de trigger a observar
    virtual function void set_trigger_signal(ref logic trigger_out);
        // Nota: En la práctica, esto se hace via interface
    endfunction
    
    /// Puerto adicional para eventos de trigger
    uvm_analysis_port #(trigger_seq_item) trigger_ap;
    
    /// Contadores
    int unsigned triggers_observed;
    
    function new(string name = "trigger_monitor", uvm_component parent = null);
        super.new(name, parent);
        triggers_observed = 0;
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        trigger_ap = new("trigger_ap", this);
    endfunction
    
endclass : trigger_monitor
