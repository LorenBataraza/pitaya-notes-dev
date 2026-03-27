/**
 * @file axis_driver.sv
 * @brief Driver AXI-Stream para UVM
 *
 * Convierte sequence items en señales físicas en la interface AXI-Stream.
 * Maneja el protocolo de handshake (TVALID/TREADY) correctamente.
 */

class axis_driver extends uvm_driver #(axis_seq_item);

    //=========================================================================
    // Factory Registration
    //=========================================================================
    
    `uvm_component_utils(axis_driver)
    
    //=========================================================================
    // Interface virtual
    //=========================================================================
    
    virtual axis_if vif;
    
    //=========================================================================
    // Configuración
    //=========================================================================
    
    /// Nombre del driver para logging
    string driver_name = "AXIS_DRV";
    
    //=========================================================================
    // Métodos
    //=========================================================================
    
    /**
     * @brief Constructor
     */
    function new(string name = "axis_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    /**
     * @brief Build phase - obtener interface del config_db
     */
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal(driver_name, "No se encontró interface virtual en config_db")
        end
    endfunction
    
    /**
     * @brief Run phase - loop principal del driver
     */
    virtual task run_phase(uvm_phase phase);
        // Estado inicial
        vif.drv_cb.tdata  <= '0;
        vif.drv_cb.tvalid <= 1'b0;
        vif.drv_cb.tlast  <= 1'b0;
        
        // Esperar reset
        @(posedge vif.aresetn);
        @(vif.drv_cb);
        
        `uvm_info(driver_name, "Driver iniciado después de reset", UVM_MEDIUM)
        
        // Loop principal
        forever begin
            axis_seq_item item;
            
            // Obtener item del sequencer
            seq_item_port.get_next_item(item);
            
            // Aplicar delay si está configurado
            if (item.delay > 0) begin
                repeat(item.delay) @(vif.drv_cb);
            end
            
            // Enviar el item
            drive_item(item);
            
            // Notificar al sequencer que terminamos
            seq_item_port.item_done();
        end
    endtask
    
    /**
     * @brief Envía un item por la interface
     */
    virtual task drive_item(axis_seq_item item);
        // Poner datos en el bus
        vif.drv_cb.tdata  <= item.data;
        vif.drv_cb.tvalid <= 1'b1;
        vif.drv_cb.tlast  <= item.tlast;
        
        // Esperar handshake (TVALID && TREADY)
        @(vif.drv_cb);
        while (!vif.drv_cb.tready) begin
            @(vif.drv_cb);
        end
        
        `uvm_info(driver_name, $sformatf("Enviado: %s", item.convert2string()), UVM_HIGH)
        
        // Desassertar valid para el siguiente ciclo
        // (a menos que haya back-to-back transfers)
        vif.drv_cb.tvalid <= 1'b0;
        vif.drv_cb.tlast  <= 1'b0;
    endtask
    
endclass : axis_driver

/**
 * @brief Driver esclavo que solo maneja TREADY
 */
class axis_slave_driver extends uvm_driver #(axis_seq_item);

    `uvm_component_utils(axis_slave_driver)
    
    virtual axis_if vif;
    
    /// Probabilidad de TREADY alto (0-100)
    int ready_probability = 100;
    
    function new(string name = "axis_slave_driver", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("AXIS_SLV", "No se encontró interface virtual")
        end
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        vif.slv_cb.tready <= 1'b1;
        
        @(posedge vif.aresetn);
        
        forever begin
            @(vif.slv_cb);
            
            // Generar TREADY basado en probabilidad
            if (ready_probability < 100) begin
                vif.slv_cb.tready <= ($urandom_range(0, 99) < ready_probability);
            end else begin
                vif.slv_cb.tready <= 1'b1;
            end
        end
    endtask
    
endclass : axis_slave_driver
