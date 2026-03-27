/**
 * @file trigger_env.sv
 * @brief Environment UVM para verificación del módulo trigger
 *
 * Agrupa todos los componentes necesarios para verificar el trigger:
 * agents, scoreboard, coverage collectors.
 */

/**
 * @brief Configuración del environment
 */
class trigger_env_config extends uvm_object;

    `uvm_object_utils(trigger_env_config)
    
    /// Interface de entrada (AXI-Stream slave del DUT)
    virtual axis_if input_vif;
    
    /// Interface de salida (AXI-Stream master del DUT)
    virtual axis_if output_vif;
    
    /// Habilitar scoreboard
    bit enable_scoreboard = 1;
    
    /// Habilitar coverage
    bit enable_coverage = 1;
    
    /// Directorio de vectores
    string vectors_dir = "../sim/vectors";
    
    /// Nombre del test actual
    string test_name = "trigger_rising_ramp";
    
    function new(string name = "trigger_env_config");
        super.new(name);
    endfunction
    
endclass : trigger_env_config

/**
 * @brief Environment del trigger
 */
class trigger_env extends uvm_env;

    //=========================================================================
    // Factory Registration
    //=========================================================================
    
    `uvm_component_utils(trigger_env)
    
    //=========================================================================
    // Componentes
    //=========================================================================
    
    /// Agent de entrada (master)
    axis_agent input_agent;
    
    /// Agent de salida (slave/monitor)
    axis_slave_agent output_agent;
    
    /// Scoreboard
    trigger_scoreboard scoreboard;
    
    //=========================================================================
    // Configuración
    //=========================================================================
    
    trigger_env_config cfg;
    
    //=========================================================================
    // Métodos
    //=========================================================================
    
    function new(string name = "trigger_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    /**
     * @brief Build phase - crear componentes
     */
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Obtener configuración
        if (!uvm_config_db#(trigger_env_config)::get(this, "", "cfg", cfg)) begin
            `uvm_fatal("TRIGGER_ENV", "No se encontró configuración")
        end
        
        // Configurar agent de entrada
        axis_agent_config in_cfg = axis_agent_config::type_id::create("in_cfg");
        in_cfg.is_active = UVM_ACTIVE;
        uvm_config_db#(axis_agent_config)::set(this, "input_agent", "cfg", in_cfg);
        uvm_config_db#(virtual axis_if)::set(this, "input_agent*", "vif", cfg.input_vif);
        
        // Configurar agent de salida (pasivo/slave)
        uvm_config_db#(virtual axis_if)::set(this, "output_agent*", "vif", cfg.output_vif);
        
        // Crear agents
        input_agent  = axis_agent::type_id::create("input_agent", this);
        output_agent = axis_slave_agent::type_id::create("output_agent", this);
        
        // Crear scoreboard si está habilitado
        if (cfg.enable_scoreboard) begin
            scoreboard = trigger_scoreboard::type_id::create("scoreboard", this);
        end
    endfunction
    
    /**
     * @brief Connect phase - conectar componentes
     */
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Conectar monitors al scoreboard
        if (cfg.enable_scoreboard && scoreboard != null) begin
            input_agent.ap.connect(scoreboard.input_export);
            output_agent.monitor.ap.connect(scoreboard.output_export);
        end
    endfunction
    
    /**
     * @brief Carga vectores de test
     */
    function void load_test_vectors();
        string exp_file;
        
        if (scoreboard != null) begin
            exp_file = {cfg.vectors_dir, "/", cfg.test_name, "_expected.hex"};
            if (!scoreboard.load_expected(exp_file)) begin
                `uvm_error("TRIGGER_ENV", $sformatf("Error cargando: %s", exp_file))
            end
        end
    endfunction
    
endclass : trigger_env
