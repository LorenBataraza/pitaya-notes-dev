/**
 * @file trigger_tests.sv
 * @brief Tests UVM para el módulo trigger
 *
 * Define tests que usan el environment y sequences para verificar
 * el comportamiento del trigger.
 */

/**
 * @brief Test base con funcionalidad común
 */
class trigger_base_test extends uvm_test;

    `uvm_component_utils(trigger_base_test)
    
    //=========================================================================
    // Componentes
    //=========================================================================
    
    trigger_env env;
    trigger_env_config env_cfg;
    
    //=========================================================================
    // Configuración
    //=========================================================================
    
    /// Nombre del test de vectores a usar
    string test_name = "trigger_rising_ramp";
    
    /// Directorio de vectores
    string vectors_dir = "../sim/vectors";
    
    /// Timeout del test
    time test_timeout = 10ms;
    
    //=========================================================================
    // Métodos
    //=========================================================================
    
    function new(string name = "trigger_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    /**
     * @brief Build phase - crear environment
     */
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Crear configuración
        env_cfg = trigger_env_config::type_id::create("env_cfg");
        
        // Obtener interfaces del top module
        if (!uvm_config_db#(virtual axis_if)::get(this, "", "input_vif", env_cfg.input_vif)) begin
            `uvm_fatal("TEST", "No se encontró input_vif")
        end
        
        if (!uvm_config_db#(virtual axis_if)::get(this, "", "output_vif", env_cfg.output_vif)) begin
            `uvm_fatal("TEST", "No se encontró output_vif")
        end
        
        // Configurar test
        configure_test();
        
        env_cfg.test_name   = test_name;
        env_cfg.vectors_dir = vectors_dir;
        
        // Pasar configuración al environment
        uvm_config_db#(trigger_env_config)::set(this, "env", "cfg", env_cfg);
        
        // Crear environment
        env = trigger_env::type_id::create("env", this);
    endfunction
    
    /**
     * @brief Hook para configuración específica del test
     */
    virtual function void configure_test();
        // Override en tests derivados
    endfunction
    
    /**
     * @brief End of elaboration - cargar vectores
     */
    virtual function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        env.load_test_vectors();
    endfunction
    
    /**
     * @brief Run phase - ejecutar secuencias
     */
    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this, "Starting test");
        
        // Timeout
        fork
            begin
                #(test_timeout);
                `uvm_fatal("TEST", "Test timeout!")
            end
        join_none
        
        // Ejecutar secuencia del test
        run_test_sequence();
        
        // Esperar un poco para que se procesen los últimos items
        #1us;
        
        phase.drop_objection(this, "Test completed");
    endtask
    
    /**
     * @brief Ejecuta la secuencia del test (override en derivados)
     */
    virtual task run_test_sequence();
        axis_file_sequence seq;
        string stim_file;
        
        seq = axis_file_sequence::type_id::create("file_seq");
        stim_file = {vectors_dir, "/", test_name, "_stimulus.hex"};
        
        if (!seq.load_file(stim_file)) begin
            `uvm_fatal("TEST", $sformatf("Error cargando: %s", stim_file))
        end
        
        seq.start(env.input_agent.sequencer);
    endtask
    
endclass : trigger_base_test

/**
 * @brief Test con rampa ascendente
 */
class trigger_rising_ramp_test extends trigger_base_test;

    `uvm_component_utils(trigger_rising_ramp_test)
    
    function new(string name = "trigger_rising_ramp_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void configure_test();
        test_name = "trigger_rising_ramp";
    endfunction
    
endclass : trigger_rising_ramp_test

/**
 * @brief Test con rampa descendente
 */
class trigger_falling_ramp_test extends trigger_base_test;

    `uvm_component_utils(trigger_falling_ramp_test)
    
    function new(string name = "trigger_falling_ramp_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void configure_test();
        test_name = "trigger_falling_ramp";
    endfunction
    
endclass : trigger_falling_ramp_test

/**
 * @brief Test con senoidal (ambos flancos)
 */
class trigger_both_sine_test extends trigger_base_test;

    `uvm_component_utils(trigger_both_sine_test)
    
    function new(string name = "trigger_both_sine_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void configure_test();
        test_name = "trigger_both_sine";
    endfunction
    
endclass : trigger_both_sine_test

/**
 * @brief Test con pulsos
 */
class trigger_pulse_test extends trigger_base_test;

    `uvm_component_utils(trigger_pulse_test)
    
    function new(string name = "trigger_pulse_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void configure_test();
        test_name = "trigger_rising_pulse";
    endfunction
    
endclass : trigger_pulse_test

/**
 * @brief Test aleatorio con generación propia (no usa archivos)
 */
class trigger_random_test extends trigger_base_test;

    `uvm_component_utils(trigger_random_test)
    
    int num_samples = 500;
    
    function new(string name = "trigger_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void configure_test();
        // No usa archivos de vectores
        env_cfg.enable_scoreboard = 0;  // Deshabilitamos el scoreboard basado en archivos
    endfunction
    
    virtual task run_test_sequence();
        axis_packet_sequence seq;
        int data[$];
        
        // Generar datos aleatorios
        for (int i = 0; i < num_samples; i++) begin
            data.push_back($urandom_range(0, 1023));
        end
        
        seq = axis_packet_sequence::type_id::create("random_seq");
        seq.set_data(data);
        
        seq.start(env.input_agent.sequencer);
    endtask
    
endclass : trigger_random_test

/**
 * @brief Test de stress con backpressure
 */
class trigger_backpressure_test extends trigger_base_test;

    `uvm_component_utils(trigger_backpressure_test)
    
    function new(string name = "trigger_backpressure_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction
    
    virtual function void configure_test();
        test_name = "trigger_rising_ramp";
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Reducir probabilidad de TREADY para generar backpressure
        env.output_agent.ready_probability = 70;
    endfunction
    
endclass : trigger_backpressure_test
