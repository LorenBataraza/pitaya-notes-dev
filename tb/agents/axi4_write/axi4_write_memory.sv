/**
 * @file axi4_write_memory.sv
 * @brief Modelo de memoria AXI4 Write Slave
 *
 * Simula un slave AXI4 que acepta escrituras y almacena
 * los datos en un array asociativo. Soporta:
 *   - Backpressure configurable en AW, W y B
 *   - Latencia de respuesta configurable
 *   - Verificacion de protocolo
 *
 * El contenido de la memoria puede ser leido por el scoreboard
 * para comparar con los valores esperados.
 */

class axi4_write_memory extends uvm_component;

    //=========================================================================
    // UVM Factory
    //=========================================================================
    
    `uvm_component_utils(axi4_write_memory)

    //=========================================================================
    // Parametros de Configuracion
    //=========================================================================
    
    /// Probabilidad de bajar AWREADY (0-100)
    int aw_backpressure_pct = 0;
    
    /// Probabilidad de bajar WREADY (0-100)
    int w_backpressure_pct = 0;
    
    /// Latencia minima de respuesta B (ciclos)
    int b_min_latency = 1;
    
    /// Latencia maxima de respuesta B (ciclos)
    int b_max_latency = 5;

    //=========================================================================
    // Handles
    //=========================================================================
    
    /// Handle a la interface virtual
    virtual axi4_write_if vif;
    
    /// Memoria: address -> byte
    protected bit [7:0] mem[int unsigned];
    
    /// Cola de respuestas B pendientes (IDs y latencias)
    protected int b_queue_id[$];
    protected int b_queue_lat[$];

    //=========================================================================
    // Variables de transaccion AW pendiente
    //=========================================================================
    
    protected bit  pend_valid;
    protected int  pend_id;
    protected int unsigned pend_addr;
    protected int  pend_len;
    protected int  pend_size;
    protected int  pend_beat_count;

    //=========================================================================
    // Estadisticas
    //=========================================================================
    
    int total_aw_txns;
    int total_w_beats;
    int total_b_resps;
    int total_bytes_written;

    //=========================================================================
    // Constructor
    //=========================================================================
    
    function new(string name = "axi4_write_memory", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    //=========================================================================
    // Build Phase
    //=========================================================================
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        if (!uvm_config_db#(virtual axi4_write_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NO_VIF", "Virtual interface not found")
        end
    endfunction

    //=========================================================================
    // Run Phase
    //=========================================================================
    
    virtual task run_phase(uvm_phase phase);
        // Inicializar senales
        vif.slave_cb.awready <= 1;
        vif.slave_cb.wready  <= 1;
        vif.slave_cb.bvalid  <= 0;
        vif.slave_cb.bresp   <= 0;
        vif.slave_cb.bid     <= 0;
        
        pend_valid = 0;
        
        fork
            handle_aw_channel();
            handle_w_channel();
            handle_b_channel();
            apply_backpressure();
        join
    endtask

    //=========================================================================
    // AW Channel Handler
    //=========================================================================
    
    virtual task handle_aw_channel();
        forever begin
            @(vif.slave_cb);
            
            if (vif.slave_cb.awvalid && vif.slave_cb.awready) begin
                if (pend_valid) begin
                    `uvm_error("AXI4_MEM", "New AW while previous not complete")
                end
                
                pend_valid = 1;
                pend_id    = vif.slave_cb.awid;
                pend_addr  = vif.slave_cb.awaddr;
                pend_len   = vif.slave_cb.awlen;
                pend_size  = vif.slave_cb.awsize;
                pend_beat_count = 0;
                
                total_aw_txns = total_aw_txns + 1;
                
                `uvm_info("AXI4_MEM", $sformatf("AW: addr=0x%08X len=%0d",
                          pend_addr, pend_len), UVM_HIGH)
            end
        end
    endtask

    //=========================================================================
    // W Channel Handler
    //=========================================================================
    
    virtual task handle_w_channel();
        int unsigned byte_addr;
        int bytes_per_beat;
        int latency;
        int i;
        
        forever begin
            @(vif.slave_cb);
            
            if (vif.slave_cb.wvalid && vif.slave_cb.wready) begin
                if (!pend_valid) begin
                    `uvm_error("AXI4_MEM", "W beat without pending AW")
                    continue;
                end
                
                bytes_per_beat = 1 << pend_size;
                byte_addr = pend_addr + (pend_beat_count * bytes_per_beat);
                
                // Escribir bytes segun strobe
                for (i = 0; i < bytes_per_beat; i = i + 1) begin
                    if (vif.slave_cb.wstrb[i]) begin
                        mem[byte_addr + i] = vif.slave_cb.wdata[i*8 +: 8];
                        total_bytes_written = total_bytes_written + 1;
                    end
                end
                
                total_w_beats = total_w_beats + 1;
                pend_beat_count = pend_beat_count + 1;
                
                `uvm_info("AXI4_MEM", $sformatf("W: beat=%0d addr=0x%08X data=0x%016X%s",
                          pend_beat_count - 1, byte_addr,
                          vif.slave_cb.wdata,
                          vif.slave_cb.wlast ? " LAST" : ""), UVM_HIGH)
                
                // Verificar WLAST
                if (vif.slave_cb.wlast) begin
                    if (pend_beat_count != pend_len + 1) begin
                        `uvm_error("AXI4_MEM", $sformatf(
                            "WLAST at beat %0d, expected %0d",
                            pend_beat_count, pend_len + 1))
                    end
                    
                    // Encolar respuesta B con latencia aleatoria
                    latency = $urandom_range(b_max_latency, b_min_latency);
                    b_queue_id.push_back(pend_id);
                    b_queue_lat.push_back(latency);
                    
                    pend_valid = 0;
                end
            end
        end
    endtask

    //=========================================================================
    // B Channel Handler
    //=========================================================================
    
    virtual task handle_b_channel();
        int resp_id;
        int resp_lat;
        
        forever begin
            // Esperar que haya respuestas pendientes
            wait(b_queue_id.size() > 0);
            
            resp_id  = b_queue_id.pop_front();
            resp_lat = b_queue_lat.pop_front();
            
            // Esperar latencia configurada
            repeat(resp_lat) @(vif.slave_cb);
            
            // Enviar respuesta
            vif.slave_cb.bid    <= resp_id;
            vif.slave_cb.bresp  <= 2'b00;  // OKAY
            vif.slave_cb.bvalid <= 1;
            
            // Esperar BREADY
            do begin
                @(vif.slave_cb);
            end while (!vif.slave_cb.bready);
            
            vif.slave_cb.bvalid <= 0;
            total_b_resps = total_b_resps + 1;
            
            `uvm_info("AXI4_MEM", $sformatf("B: id=%0d OKAY", resp_id), UVM_HIGH)
        end
    endtask

    //=========================================================================
    // Backpressure
    //=========================================================================
    
    virtual task apply_backpressure();
        forever begin
            @(vif.slave_cb);
            
            // AW backpressure
            if (aw_backpressure_pct > 0) begin
                if ($urandom_range(100) < aw_backpressure_pct)
                    vif.slave_cb.awready <= 0;
                else
                    vif.slave_cb.awready <= 1;
            end
            
            // W backpressure
            if (w_backpressure_pct > 0) begin
                if ($urandom_range(100) < w_backpressure_pct)
                    vif.slave_cb.wready <= 0;
                else
                    vif.slave_cb.wready <= 1;
            end
        end
    endtask

    //=========================================================================
    // Metodos de Acceso a Memoria
    //=========================================================================
    
    /**
     * @brief Lee un byte de la memoria
     * @param addr Direccion
     * @return Byte leido (0 si no existe)
     */
    virtual function bit [7:0] read_byte(int unsigned addr);
        if (mem.exists(addr))
            return mem[addr];
        else
            return 8'h00;
    endfunction
    
    /**
     * @brief Lee una palabra de 16 bits (little endian)
     * @param addr Direccion base
     * @return Palabra de 16 bits
     */
    virtual function bit [15:0] read_word16(int unsigned addr);
        return {read_byte(addr+1), read_byte(addr)};
    endfunction
    
    /**
     * @brief Lee una palabra de 64 bits (little endian)
     * @param addr Direccion base
     * @return Palabra de 64 bits
     */
    virtual function bit [63:0] read_word64(int unsigned addr);
        bit [63:0] result;
        int i;
        for (i = 0; i < 8; i = i + 1) begin
            result[i*8 +: 8] = read_byte(addr + i);
        end
        return result;
    endfunction
    
    /**
     * @brief Lee un rango de memoria como array de 16 bits
     * @param base_addr Direccion inicial
     * @param count     Numero de words
     * @param data      Array de salida
     */
    virtual function void read_range16(
        int unsigned base_addr,
        int count,
        output bit [15:0] data[]
    );
        int i;
        data = new[count];
        for (i = 0; i < count; i = i + 1) begin
            data[i] = read_word16(base_addr + i*2);
        end
    endfunction
    
    /**
     * @brief Limpia toda la memoria
     */
    virtual function void clear();
        mem.delete();
        total_bytes_written = 0;
    endfunction
    
    /**
     * @brief Retorna el numero de direcciones escritas
     * @return Numero de bytes unicos escritos
     */
    virtual function int get_written_count();
        return mem.size();
    endfunction

    //=========================================================================
    // Report Phase
    //=========================================================================
    
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        
        `uvm_info("AXI4_MEM", $sformatf(
            "Memory Stats: AW=%0d W=%0d B=%0d bytes=%0d",
            total_aw_txns, total_w_beats, total_b_resps, total_bytes_written),
            UVM_LOW)
    endfunction

endclass : axi4_write_memory
