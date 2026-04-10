/**
 * @file axi4_write_agent.sv
 * @brief Agent UVM para AXI4 Write
 *
 * Integra monitor y memory model para verificar escrituras AXI4.
 * Este agent es pasivo (solo observa), el DUT actua como master.
 *
 * Componentes:
 *   - Monitor: captura transacciones AW, W, B
 *   - Memory:  simula el slave y almacena datos
 *
 * El agent expone:
 *   - Analysis port con transacciones capturadas
 *   - Acceso a la memoria para lectura por el scoreboard
 */

class axi4_write_agent extends uvm_agent;

    //=========================================================================
    // UVM Factory
    //=========================================================================
    
    `uvm_component_utils(axi4_write_agent)

    //=========================================================================
    // Componentes
    //=========================================================================
    
    axi4_write_monitor  monitor;
    axi4_write_memory   memory;

    //=========================================================================
    // Analysis Port
    //=========================================================================
    
    uvm_analysis_port #(axi4_write_seq_item) ap;

    //=========================================================================
    // Configuracion
    //=========================================================================
    
    /// Backpressure en AW (0-100%)
    int aw_backpressure = 0;
    
    /// Backpressure en W (0-100%)
    int w_backpressure = 0;
    
    /// Latencia minima de respuesta
    int b_latency_min = 1;
    
    /// Latencia maxima de respuesta
    int b_latency_max = 5;

    //=========================================================================
    // Constructor
    //=========================================================================
    
    function new(string name = "axi4_write_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //=========================================================================
    // Build Phase
    //=========================================================================
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        monitor = axi4_write_monitor::type_id::create("monitor", this);
        memory  = axi4_write_memory::type_id::create("memory", this);
        
        ap = new("ap", this);
    endfunction

    //=========================================================================
    // Connect Phase
    //=========================================================================
    
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Conectar analysis port del monitor al del agent
        monitor.ap.connect(ap);
        
        // Configurar memory model
        memory.aw_backpressure_pct = aw_backpressure;
        memory.w_backpressure_pct  = w_backpressure;
        memory.b_min_latency       = b_latency_min;
        memory.b_max_latency       = b_latency_max;
    endfunction

    //=========================================================================
    // Metodos de Acceso a Memoria
    //=========================================================================
    
    /**
     * @brief Lee un byte de la memoria
     */
    function bit [7:0] read_byte(int unsigned addr);
        return memory.read_byte(addr);
    endfunction
    
    /**
     * @brief Lee una palabra de 16 bits
     */
    function bit [15:0] read_word16(int unsigned addr);
        return memory.read_word16(addr);
    endfunction
    
    /**
     * @brief Lee un rango de memoria
     */
    function void read_range16(int unsigned base_addr, int count, output bit [15:0] data[]);
        memory.read_range16(base_addr, count, data);
    endfunction
    
    /**
     * @brief Limpia la memoria
     */
    function void clear_memory();
        memory.clear();
    endfunction
    
    /**
     * @brief Retorna bytes escritos
     */
    function int get_bytes_written();
        return memory.total_bytes_written;
    endfunction

endclass : axi4_write_agent
