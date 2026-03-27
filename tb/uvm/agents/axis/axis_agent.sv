/**
 * @file axis_agent.sv
 * @brief Agent AXI-Stream completo para UVM
 *
 * Encapsula el driver, monitor y sequencer para una interface AXI-Stream.
 * Puede configurarse como activo (con driver) o pasivo (solo monitor).
 */

/**
 * @brief Configuración del agent
 */
class axis_agent_config extends uvm_object;

    `uvm_object_utils(axis_agent_config)
    
    /// Modo activo (1) o pasivo (0)
    bit is_active = UVM_ACTIVE;
    
    /// Probabilidad de TREADY para slave (0-100)
    int ready_probability = 100;
    
    /// Habilitar checks de protocolo
    bit enable_checks = 1;
    
    /// Habilitar coverage
    bit enable_coverage = 1;
    
    function new(string name = "axis_agent_config");
        super.new(name);
    endfunction
    
endclass : axis_agent_config

/**
 * @brief Agent AXI-Stream
 */
class axis_agent extends uvm_agent;

    //=========================================================================
    // Factory Registration
    //=========================================================================
    
    `uvm_component_utils(axis_agent)
    
    //=========================================================================
    // Componentes
    //=========================================================================
    
    /// Driver (solo en modo activo)
    axis_driver driver;
    
    /// Monitor (siempre presente)
    axis_monitor monitor;
    
    /// Sequencer (solo en modo activo)
    uvm_sequencer #(axis_seq_item) sequencer;
    
    //=========================================================================
    // Configuración
    //=========================================================================
    
    axis_agent_config cfg;
    
    //=========================================================================
    // Puertos de análisis (forwarded desde monitor)
    //=========================================================================
    
    uvm_analysis_port #(axis_seq_item) ap;
    
    //=========================================================================
    // Métodos
    //=========================================================================
    
    function new(string name = "axis_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    /**
     * @brief Build phase - crear componentes según configuración
     */
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Obtener configuración
        if (!uvm_config_db#(axis_agent_config)::get(this, "", "cfg", cfg)) begin
            `uvm_info("AXIS_AGENT", "Usando configuración por defecto", UVM_MEDIUM)
            cfg = axis_agent_config::type_id::create("cfg");
        end
        
        // Crear monitor (siempre)
        monitor = axis_monitor::type_id::create("monitor", this);
        
        // Crear driver y sequencer solo en modo activo
        if (cfg.is_active == UVM_ACTIVE) begin
            driver    = axis_driver::type_id::create("driver", this);
            sequencer = uvm_sequencer#(axis_seq_item)::type_id::create("sequencer", this);
        end
    endfunction
    
    /**
     * @brief Connect phase - conectar componentes
     */
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Conectar driver a sequencer
        if (cfg.is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
        
        // Forward analysis port del monitor
        ap = monitor.ap;
    endfunction
    
endclass : axis_agent

/**
 * @brief Agent para interface slave (solo TREADY)
 */
class axis_slave_agent extends uvm_agent;

    `uvm_component_utils(axis_slave_agent)
    
    axis_slave_driver driver;
    axis_monitor monitor;
    
    int ready_probability = 100;
    
    function new(string name = "axis_slave_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver  = axis_slave_driver::type_id::create("driver", this);
        monitor = axis_monitor::type_id::create("monitor", this);
        driver.ready_probability = ready_probability;
    endfunction
    
endclass : axis_slave_agent
