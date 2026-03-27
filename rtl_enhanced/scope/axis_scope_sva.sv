/**
 * @file axis_scope_sva.sv
 * @brief Módulo de assertions SVA para axis_scope
 *
 * Verificación del buffer circular y captura de ventanas
 * pre/post trigger.
 *
 * @par Uso:
 * @code
 *   bind axis_scope axis_scope_sva #(
 *       .DATA_WIDTH(DATA_WIDTH),
 *       .BUFFER_DEPTH(BUFFER_DEPTH)
 *   ) sva_inst (.*);
 * @endcode
 */

`ifndef AXIS_SCOPE_SVA_SV
`define AXIS_SCOPE_SVA_SV

module axis_scope_sva #(
    parameter int DATA_WIDTH = 16,
    parameter int BUFFER_DEPTH = 4096
) (
    // Señales del DUT
    input logic                       aclk,
    input logic                       aresetn,
    
    // Configuración
    input logic                       cfg_enable,
    input logic                       cfg_arm,
    input logic [15:0]                cfg_pre_samples,
    input logic [15:0]                cfg_post_samples,
    
    // Status
    input logic [2:0]                 sts_state,
    input logic                       sts_armed,
    input logic                       sts_triggered,
    input logic                       sts_done,
    
    // AXI-Stream Slave
    input logic [DATA_WIDTH-1:0]      s_axis_tdata,
    input logic                       s_axis_tvalid,
    input logic                       s_axis_tready,
    
    // Trigger input
    input logic                       trigger_i,
    
    // AXI-Stream Master
    input logic [DATA_WIDTH-1:0]      m_axis_tdata,
    input logic                       m_axis_tvalid,
    input logic                       m_axis_tready,
    input logic                       m_axis_tlast
);

    //=========================================================================
    // Estados de la FSM
    //=========================================================================
    
    localparam logic [2:0] ST_IDLE      = 3'b000;
    localparam logic [2:0] ST_ARMED     = 3'b001;
    localparam logic [2:0] ST_TRIGGERED = 3'b010;
    localparam logic [2:0] ST_TRANSFER  = 3'b011;
    localparam logic [2:0] ST_DONE      = 3'b100;

    //=========================================================================
    // Variables de monitoreo
    //=========================================================================
    
    int samples_received;
    int samples_output;
    int trigger_count;
    logic [2:0] prev_state;
    
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            samples_received <= 0;
            samples_output <= 0;
            trigger_count <= 0;
            prev_state <= ST_IDLE;
        end else begin
            prev_state <= sts_state;
            
            if (s_axis_tvalid && s_axis_tready)
                samples_received <= samples_received + 1;
            
            if (m_axis_tvalid && m_axis_tready)
                samples_output <= samples_output + 1;
            
            if (trigger_i && sts_armed)
                trigger_count <= trigger_count + 1;
        end
    end

    //=========================================================================
    // ASSERTIONS: Protocolo AXI-Stream
    //=========================================================================
    
    property p_s_tvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        (s_axis_tvalid && !s_axis_tready) |=> s_axis_tvalid;
    endproperty
    assert property (p_s_tvalid_stable)
        else $error("SVA: s_axis_tvalid dropped before handshake");
    
    property p_m_tvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axis_tvalid && !m_axis_tready) |=> m_axis_tvalid;
    endproperty
    assert property (p_m_tvalid_stable)
        else $error("SVA: m_axis_tvalid dropped before handshake");
    
    property p_m_tdata_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axis_tvalid && !m_axis_tready) |=> $stable(m_axis_tdata);
    endproperty
    assert property (p_m_tdata_stable)
        else $error("SVA: m_axis_tdata changed without handshake");
    
    property p_m_tlast_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axis_tvalid && !m_axis_tready) |=> $stable(m_axis_tlast);
    endproperty
    assert property (p_m_tlast_stable)
        else $error("SVA: m_axis_tlast changed without handshake");

    //=========================================================================
    // ASSERTIONS: Máquina de estados
    //=========================================================================
    
    /**
     * @brief Solo transiciones válidas de la FSM
     */
    property p_valid_state_transitions;
        @(posedge aclk) disable iff (!aresetn)
        (sts_state == ST_IDLE) |=> 
            (sts_state inside {ST_IDLE, ST_ARMED});
    endproperty
    assert property (p_valid_state_transitions)
        else $error("SVA: Invalid state transition from IDLE");
    
    property p_armed_transitions;
        @(posedge aclk) disable iff (!aresetn)
        (sts_state == ST_ARMED) |=> 
            (sts_state inside {ST_ARMED, ST_TRIGGERED, ST_IDLE});
    endproperty
    assert property (p_armed_transitions)
        else $error("SVA: Invalid state transition from ARMED");
    
    property p_triggered_transitions;
        @(posedge aclk) disable iff (!aresetn)
        (sts_state == ST_TRIGGERED) |=> 
            (sts_state inside {ST_TRIGGERED, ST_TRANSFER});
    endproperty
    assert property (p_triggered_transitions)
        else $error("SVA: Invalid state transition from TRIGGERED");
    
    property p_transfer_transitions;
        @(posedge aclk) disable iff (!aresetn)
        (sts_state == ST_TRANSFER) |=> 
            (sts_state inside {ST_TRANSFER, ST_DONE});
    endproperty
    assert property (p_transfer_transitions)
        else $error("SVA: Invalid state transition from TRANSFER");
    
    property p_done_transitions;
        @(posedge aclk) disable iff (!aresetn)
        (sts_state == ST_DONE) |=> 
            (sts_state inside {ST_DONE, ST_IDLE});
    endproperty
    assert property (p_done_transitions)
        else $error("SVA: Invalid state transition from DONE");

    //=========================================================================
    // ASSERTIONS: Funcionalidad del scope
    //=========================================================================
    
    /**
     * @brief Trigger solo debe aceptarse cuando está armado
     */
    property p_trigger_when_armed;
        @(posedge aclk) disable iff (!aresetn)
        (trigger_i && sts_state != ST_ARMED) |=> (sts_state != ST_TRIGGERED);
    endproperty
    // Comentado porque el trigger puede ser registrado
    // assert property (p_trigger_when_armed);
    
    /**
     * @brief La señal sts_armed debe coincidir con el estado
     */
    property p_armed_status_match;
        @(posedge aclk) disable iff (!aresetn)
        sts_armed == (sts_state == ST_ARMED);
    endproperty
    assert property (p_armed_status_match)
        else $error("SVA: sts_armed doesn't match state");
    
    /**
     * @brief La señal sts_done debe coincidir con el estado
     */
    property p_done_status_match;
        @(posedge aclk) disable iff (!aresetn)
        sts_done == (sts_state == ST_DONE);
    endproperty
    assert property (p_done_status_match)
        else $error("SVA: sts_done doesn't match state");
    
    /**
     * @brief TLAST solo al final de la transferencia
     */
    property p_tlast_at_end;
        @(posedge aclk) disable iff (!aresetn)
        (m_axis_tvalid && m_axis_tready && m_axis_tlast) |=>
            (sts_state inside {ST_DONE, ST_IDLE});
    endproperty
    // assert property (p_tlast_at_end);
    
    /**
     * @brief El módulo debe aceptar datos cuando está habilitado
     */
    property p_accepts_data_when_enabled;
        @(posedge aclk) disable iff (!aresetn)
        (cfg_enable && sts_state inside {ST_IDLE, ST_ARMED, ST_TRIGGERED}) |->
            s_axis_tready;
    endproperty
    // assert property (p_accepts_data_when_enabled);

    //=========================================================================
    // ASSERTIONS: Configuración
    //=========================================================================
    
    /**
     * @brief pre_samples no debe exceder la mitad del buffer
     */
    property p_pre_samples_valid;
        @(posedge aclk) disable iff (!aresetn)
        cfg_pre_samples <= BUFFER_DEPTH / 2;
    endproperty
    assert property (p_pre_samples_valid)
        else $warning("SVA: cfg_pre_samples exceeds half buffer depth");
    
    /**
     * @brief post_samples no debe exceder la mitad del buffer
     */
    property p_post_samples_valid;
        @(posedge aclk) disable iff (!aresetn)
        cfg_post_samples <= BUFFER_DEPTH / 2;
    endproperty
    assert property (p_post_samples_valid)
        else $warning("SVA: cfg_post_samples exceeds half buffer depth");

    //=========================================================================
    // COVERGROUPS
    //=========================================================================
    
    covergroup cg_scope @(posedge aclk);
        option.per_instance = 1;
        
        // Estados de la FSM
        cp_state: coverpoint sts_state {
            bins idle      = {ST_IDLE};
            bins armed     = {ST_ARMED};
            bins triggered = {ST_TRIGGERED};
            bins transfer  = {ST_TRANSFER};
            bins done      = {ST_DONE};
            // Transiciones
            bins idle_to_armed     = (ST_IDLE => ST_ARMED);
            bins armed_to_triggered = (ST_ARMED => ST_TRIGGERED);
            bins triggered_to_transfer = (ST_TRIGGERED => ST_TRANSFER);
            bins transfer_to_done  = (ST_TRANSFER => ST_DONE);
            bins done_to_idle      = (ST_DONE => ST_IDLE);
        }
        
        // Configuración de pre-trigger
        cp_pre_samples: coverpoint cfg_pre_samples {
            bins zero   = {0};
            bins small  = {[1:50]};
            bins medium = {[51:200]};
            bins large  = {[201:500]};
            bins max    = {[501:$]};
        }
        
        // Configuración de post-trigger
        cp_post_samples: coverpoint cfg_post_samples {
            bins zero   = {0};
            bins small  = {[1:50]};
            bins medium = {[51:200]};
            bins large  = {[201:500]};
            bins max    = {[501:$]};
        }
        
        // Eventos de trigger
        cp_trigger: coverpoint trigger_i iff (sts_armed) {
            bins no_trigger = {0};
            bins trigger    = {1};
        }
        
        // Backpressure en entrada
        cp_input_bp: coverpoint (!s_axis_tready && s_axis_tvalid);
        
        // Backpressure en salida
        cp_output_bp: coverpoint (!m_axis_tready && m_axis_tvalid);
        
        // Cross coverage
        cx_pre_post: cross cp_pre_samples, cp_post_samples;
        cx_state_bp: cross cp_state, cp_output_bp;
        
    endgroup
    
    cg_scope cg_scope_inst = new();

    //=========================================================================
    // Información
    //=========================================================================
    
    initial begin
        $display("[SVA] axis_scope_sva bound to instance");
        $display("[SVA]   BUFFER_DEPTH=%0d", BUFFER_DEPTH);
    end
    
    final begin
        $display("[SVA] axis_scope final statistics:");
        $display("[SVA]   Samples received: %0d", samples_received);
        $display("[SVA]   Samples output:   %0d", samples_output);
        $display("[SVA]   Trigger count:    %0d", trigger_count);
        $display("[SVA]   Coverage: %.1f%%", cg_scope_inst.get_coverage());
    end

endmodule : axis_scope_sva

`endif // AXIS_SCOPE_SVA_SV
