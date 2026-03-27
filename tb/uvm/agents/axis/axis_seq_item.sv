/**
 * @file axis_seq_item.sv
 * @brief Sequence item (transacción) AXI-Stream para UVM
 *
 * Define la transacción básica que viaja por el testbench UVM.
 * Incluye campos para datos, control, y constraints para generación
 * aleatoria válida.
 */

class axis_seq_item extends uvm_sequence_item;

    //=========================================================================
    // Campos de la transacción
    //=========================================================================
    
    /// Datos del beat
    rand logic [15:0] data;
    
    /// Indica fin de paquete
    rand logic tlast;
    
    /// Delay antes de enviar (en ciclos de reloj)
    rand int unsigned delay;
    
    /// ID del paquete (para trazabilidad)
    int unsigned packet_id;
    
    /// Índice dentro del paquete
    int unsigned beat_index;
    
    /// Timestamp de creación
    time timestamp;
    
    //=========================================================================
    // UVM Factory Registration
    //=========================================================================
    
    `uvm_object_utils_begin(axis_seq_item)
        `uvm_field_int(data,       UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(tlast,      UVM_ALL_ON)
        `uvm_field_int(delay,      UVM_ALL_ON)
        `uvm_field_int(packet_id,  UVM_ALL_ON)
        `uvm_field_int(beat_index, UVM_ALL_ON)
        `uvm_field_int(timestamp,  UVM_ALL_ON | UVM_TIME)
    `uvm_object_utils_end
    
    //=========================================================================
    // Constraints
    //=========================================================================
    
    /// Delay razonable para simulación
    constraint c_delay {
        delay inside {[0:10]};
        delay dist {0 := 70, [1:3] := 20, [4:10] := 10};
    }
    
    /// tlast típicamente es 0, ocasionalmente 1
    constraint c_tlast {
        tlast dist {0 := 90, 1 := 10};
    }
    
    //=========================================================================
    // Métodos
    //=========================================================================
    
    /**
     * @brief Constructor
     */
    function new(string name = "axis_seq_item");
        super.new(name);
        timestamp = $time;
    endfunction
    
    /**
     * @brief Convierte la transacción a string para debug
     */
    virtual function string convert2string();
        return $sformatf("AXIS[pkt=%0d, beat=%0d, data=0x%04X, last=%b, delay=%0d]",
                        packet_id, beat_index, data, tlast, delay);
    endfunction
    
    /**
     * @brief Copia desde otra transacción
     */
    virtual function void do_copy(uvm_object rhs);
        axis_seq_item rhs_item;
        super.do_copy(rhs);
        
        if (!$cast(rhs_item, rhs)) begin
            `uvm_fatal("AXIS_ITEM", "Cast failed in do_copy")
        end
        
        this.data       = rhs_item.data;
        this.tlast      = rhs_item.tlast;
        this.delay      = rhs_item.delay;
        this.packet_id  = rhs_item.packet_id;
        this.beat_index = rhs_item.beat_index;
        this.timestamp  = rhs_item.timestamp;
    endfunction
    
    /**
     * @brief Compara con otra transacción
     */
    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        axis_seq_item rhs_item;
        
        if (!$cast(rhs_item, rhs)) begin
            return 0;
        end
        
        return (super.do_compare(rhs, comparer) &&
                this.data  == rhs_item.data &&
                this.tlast == rhs_item.tlast);
    endfunction
    
endclass : axis_seq_item

/**
 * @brief Transacción específica para trigger con información adicional
 */
class trigger_seq_item extends axis_seq_item;

    //=========================================================================
    // Campos adicionales para trigger
    //=========================================================================
    
    /// Indica si se espera un trigger en esta muestra
    logic expected_trigger;
    
    /// Valor del umbral configurado
    logic [15:0] threshold;
    
    /// Modo de trigger
    int mode;
    
    //=========================================================================
    // UVM Factory Registration
    //=========================================================================
    
    `uvm_object_utils_begin(trigger_seq_item)
        `uvm_field_int(data,             UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(tlast,            UVM_ALL_ON)
        `uvm_field_int(delay,            UVM_ALL_ON)
        `uvm_field_int(expected_trigger, UVM_ALL_ON)
        `uvm_field_int(threshold,        UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(mode,             UVM_ALL_ON)
    `uvm_object_utils_end
    
    //=========================================================================
    // Métodos
    //=========================================================================
    
    function new(string name = "trigger_seq_item");
        super.new(name);
        expected_trigger = 0;
    endfunction
    
    virtual function string convert2string();
        string base_str = super.convert2string();
        return $sformatf("%s, exp_trig=%b", base_str, expected_trigger);
    endfunction
    
endclass : trigger_seq_item
