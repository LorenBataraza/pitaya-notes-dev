/**
 * @file axi4_write_seq_item.sv
 * @brief Sequence item para transacciones AXI4 Write
 *
 * Representa una transaccion completa de escritura AXI4:
 *   - Fase de direccion (AW)
 *   - Fase de datos (W) con multiples beats
 *   - Fase de respuesta (B)
 *
 * @note Usa constantes numericas en lugar de localparam para
 *       compatibilidad con QuestaSim 10.7c
 */

class axi4_write_seq_item extends uvm_sequence_item;

    //=========================================================================
    // Campos de la transaccion
    // Anchos: DATA=64, ADDR=32, ID=4
    //=========================================================================
    
    /// @name Address Channel (AW)
    /// @{
    rand bit [3:0]  id;
    rand bit [31:0] addr;
    rand bit [7:0]  len;       ///< Numero de beats - 1
    rand bit [2:0]  size;      ///< Bytes por beat = 2^size
    rand bit [1:0]  burst;     ///< 01=INCR (default)
    /// @}
    
    /// @name Write Data Channel (W)
    /// @{
    rand bit [63:0] data[];    ///< Array de datos (len+1 elementos)
    rand bit [7:0]  strb[];    ///< Array de strobes (8 bits para 64-bit data)
    /// @}
    
    /// @name Write Response Channel (B)
    /// @{
    bit [1:0] resp;    ///< Respuesta del slave (set por driver/monitor)
    /// @}
    
    /// @name Metadata
    /// @{
    time start_time;
    time end_time;
    int  burst_bytes;   ///< Total de bytes en el burst
    /// @}

    //=========================================================================
    // UVM Factory
    //=========================================================================
    
    `uvm_object_utils_begin(axi4_write_seq_item)
        `uvm_field_int(id,    UVM_ALL_ON)
        `uvm_field_int(addr,  UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(len,   UVM_ALL_ON)
        `uvm_field_int(size,  UVM_ALL_ON)
        `uvm_field_int(burst, UVM_ALL_ON)
        `uvm_field_array_int(data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_array_int(strb, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(resp,  UVM_ALL_ON)
    `uvm_object_utils_end

    //=========================================================================
    // Constraints
    //=========================================================================
    
    /// Burst type es siempre INCR para este sistema
    constraint c_burst_type {
        burst == 2'b01;
    }
    
    /// Size es 3 (8 bytes) para bus de 64 bits
    constraint c_size {
        size == 3'b011;
    }
    
    /// Direccion alineada al tamano del beat (8 bytes)
    constraint c_addr_aligned {
        addr[2:0] == 3'b000;
    }
    
    /// Burst no cruza frontera de 4KB
    constraint c_no_4kb_cross {
        ((addr[11:0] + ((len + 1) << size)) <= 13'h1000) ||
        (addr[11:0] == 0);
    }
    
    /// Len limitado para evitar simulaciones muy largas
    constraint c_len_reasonable {
        len <= 63;
    }
    
    /// Arrays dimensionados segun len
    constraint c_array_size {
        data.size() == len + 1;
        strb.size() == len + 1;
    }
    
    /// Strobes tipicamente todos activos
    constraint c_strb_default {
        foreach (strb[i]) {
            strb[i] == 8'hFF;
        }
    }

    //=========================================================================
    // Constructor
    //=========================================================================
    
    function new(string name = "axi4_write_seq_item");
        super.new(name);
    endfunction

    //=========================================================================
    // Metodos
    //=========================================================================
    
    /**
     * @brief Calcula el numero total de bytes en el burst
     * @return Numero de bytes
     */
    function int get_burst_bytes();
        return (len + 1) * (1 << size);
    endfunction
    
    /**
     * @brief Retorna la direccion final del burst
     * @return Direccion del ultimo byte + 1
     */
    function bit [31:0] get_end_addr();
        return addr + get_burst_bytes();
    endfunction
    
    /**
     * @brief Verifica si el burst cruza frontera de 4KB
     * @return 1 si cruza, 0 si no
     */
    function bit crosses_4kb();
        bit [31:0] start_page;
        bit [31:0] end_page;
        bit [31:0] end_addr_val;
        
        start_page = addr >> 12;
        end_addr_val = get_end_addr() - 1;
        end_page = end_addr_val >> 12;
        
        return (start_page != end_page);
    endfunction
    
    /**
     * @brief Convierte la transaccion a string legible
     * @return String con resumen de la transaccion
     */
    virtual function string convert2string();
        string s;
        s = $sformatf("AXI4_WR: id=%0d addr=0x%08X len=%0d size=%0d burst=%0d",
                      id, addr, len, size, burst);
        s = {s, $sformatf(" [%0d bytes]", get_burst_bytes())};
        if (resp != 0)
            s = {s, $sformatf(" resp=%s", resp == 2'b00 ? "OKAY" :
                                          resp == 2'b01 ? "EXOKAY" :
                                          resp == 2'b10 ? "SLVERR" : "DECERR")};
        return s;
    endfunction
    
    /**
     * @brief Imprime los datos del burst (para debug)
     */
    function void print_data();
        int i;
        `uvm_info("AXI4_WR", convert2string(), UVM_MEDIUM)
        for (i = 0; i < data.size(); i = i + 1) begin
            `uvm_info("AXI4_WR", $sformatf("  [%0d] data=0x%016X strb=0x%02X%s",
                      i, data[i], strb[i], (i == len) ? " (LAST)" : ""), UVM_HIGH)
        end
    endfunction

endclass : axi4_write_seq_item
