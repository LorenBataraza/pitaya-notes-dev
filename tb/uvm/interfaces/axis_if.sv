/**
 * @file axis_if.sv
 * @brief Interface AXI-Stream para conexión con UVM
 *
 * Define la interface física AXI-Stream que conecta el DUT con los
 * componentes UVM (driver, monitor). Incluye clocking blocks para
 * manejar el timing correctamente.
 */

interface axis_if #(
    parameter int DATA_WIDTH = 16
)(
    input logic aclk,
    input logic aresetn
);

    //=========================================================================
    // Señales AXI-Stream
    //=========================================================================
    
    logic [DATA_WIDTH-1:0] tdata;
    logic                  tvalid;
    logic                  tready;
    logic                  tlast;
    
    //=========================================================================
    // Clocking Blocks
    //=========================================================================
    
    /**
     * @brief Clocking block para el driver (master)
     *
     * El driver maneja tdata, tvalid, tlast y muestrea tready.
     */
    clocking drv_cb @(posedge aclk);
        default input #1step output #1ns;
        output tdata;
        output tvalid;
        output tlast;
        input  tready;
    endclocking
    
    /**
     * @brief Clocking block para el monitor
     *
     * El monitor solo observa, no maneja ninguna señal.
     */
    clocking mon_cb @(posedge aclk);
        default input #1step;
        input tdata;
        input tvalid;
        input tready;
        input tlast;
    endclocking
    
    /**
     * @brief Clocking block para slave (responder)
     *
     * El slave maneja tready y muestrea el resto.
     */
    clocking slv_cb @(posedge aclk);
        default input #1step output #1ns;
        input  tdata;
        input  tvalid;
        input  tlast;
        output tready;
    endclocking
    
    //=========================================================================
    // Modports
    //=========================================================================
    
    /// Modport para el driver (inicia transacciones)
    modport master (
        clocking drv_cb,
        input aclk, aresetn
    );
    
    /// Modport para el slave (recibe transacciones)
    modport slave (
        clocking slv_cb,
        input aclk, aresetn
    );
    
    /// Modport para el monitor (solo observa)
    modport monitor (
        clocking mon_cb,
        input aclk, aresetn
    );
    
    //=========================================================================
    // Assertions de protocolo
    //=========================================================================
    
    // Estabilidad de señales durante handshake
    property p_tdata_stable;
        @(posedge aclk) disable iff (!aresetn)
        (tvalid && !tready) |=> $stable(tdata);
    endproperty
    
    property p_tvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        (tvalid && !tready) |=> tvalid;
    endproperty
    
    property p_tlast_stable;
        @(posedge aclk) disable iff (!aresetn)
        (tvalid && !tready) |=> $stable(tlast);
    endproperty
    
    // tvalid no debe ser X después de reset
    property p_tvalid_not_x;
        @(posedge aclk)
        aresetn |-> !$isunknown(tvalid);
    endproperty
    
    assert property (p_tdata_stable)
        else $error("AXI-Stream: TDATA changed while TVALID high and TREADY low");
    
    assert property (p_tvalid_stable)
        else $error("AXI-Stream: TVALID deasserted without handshake");
    
    assert property (p_tlast_stable)
        else $error("AXI-Stream: TLAST changed while TVALID high and TREADY low");
    
    assert property (p_tvalid_not_x)
        else $error("AXI-Stream: TVALID is X after reset");
    
    //=========================================================================
    // Coverage
    //=========================================================================
    
    covergroup cg_axis_protocol @(posedge aclk);
        option.per_instance = 1;
        
        /// Cobertura de handshake
        cp_handshake: coverpoint {tvalid, tready} {
            bins idle          = {2'b00};
            bins valid_wait    = {2'b10};
            bins ready_wait    = {2'b01};
            bins transfer      = {2'b11};
        }
        
        /// Cobertura de tlast
        cp_tlast: coverpoint tlast iff (tvalid && tready) {
            bins no_last = {1'b0};
            bins last    = {1'b1};
        }
        
        /// Transiciones de handshake
        cp_transitions: coverpoint {tvalid, tready} {
            bins idle_to_valid   = (2'b00 => 2'b10);
            bins valid_to_xfer   = (2'b10 => 2'b11);
            bins xfer_to_idle    = (2'b11 => 2'b00);
            bins xfer_to_valid   = (2'b11 => 2'b10);
            bins back_to_back    = (2'b11 => 2'b11);
        }
    endgroup
    
    cg_axis_protocol cg_axis = new();
    
endinterface : axis_if
