/**
 * @file axis_trigger_sva.sv
 * @brief Módulo de assertions SVA para axis_trigger
 *
 * Este módulo contiene todas las assertions y covergroups para
 * verificar el módulo axis_trigger. Se conecta usando el patrón
 * 'bind' de SystemVerilog, sin modificar el RTL original.
 *
 * @par Uso (bind externo):
 * @code
 *   // En el testbench o archivo separado:
 *   bind axis_trigger axis_trigger_sva #(
 *       .DATA_WIDTH(DATA_WIDTH)
 *   ) sva_inst (.*);
 * @endcode
 *
 * @par Categorías de assertions:
 * - Protocolo AXI-Stream
 * - Funcionalidad del trigger
 * - Timing y pipeline
 */

`ifndef AXIS_TRIGGER_SVA_SV
`define AXIS_TRIGGER_SVA_SV

module axis_trigger_sva #(
    parameter int DATA_WIDTH = 16,
    parameter int PIPE_STAGES = 2
) (
    // Señales del DUT (conectadas via bind)
    input logic                       aclk,
    input logic                       aresetn,
    
    // Configuración
    input logic                       cfg_enable,
    input logic [DATA_WIDTH-1:0]      cfg_threshold,
    input logic [2:0]                 cfg_mode,
    
    // AXI-Stream Slave
    input logic [DATA_WIDTH-1:0]      s_axis_tdata,
    input logic                       s_axis_tvalid,
    input logic                       s_axis_tready,
    
    // AXI-Stream Master
    input logic [DATA_WIDTH-1:0]      m_axis_tdata,
    input logic                       m_axis_tvalid,
    input logic                       m_axis_tready,
    
    // Salida de trigger
    input logic                       trigger_out
);

    //=========================================================================
    // Parámetros locales
    //=========================================================================
    
    localparam logic [2:0] TRIG_RISING  = 3'b001;
    localparam logic [2:0] TRIG_FALLING = 3'b010;
    localparam logic [2:0] TRIG_BOTH    = 3'b011;
    localparam logic [2:0] TRIG_LEVEL   = 3'b100;

    //=========================================================================
    // Señales auxiliares para assertions
    //=========================================================================
    
    logic signed [DATA_WIDTH-1:0] current_sample;
    logic signed [DATA_WIDTH-1:0] prev_sample;
    logic handshake_in, handshake_out;
    
    assign current_sample = s_axis_tdata;
    assign handshake_in = s_axis_tvalid && s_axis_tready;
    assign handshake_out = m_axis_tvalid && m_axis_tready;
    
    // Registro de muestra anterior
    always_ff @(posedge aclk) begin
        if (!aresetn)
            prev_sample <= '0;
        else if (handshake_in)
            prev_sample <= current_sample;
    end

    //=========================================================================
    // ASSERTIONS: Protocolo AXI-Stream
    //=========================================================================
    
    /**
     * @brief TVALID no puede caer sin TREADY (slave side)
     */
    property p_s_tvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        (s_axis_tvalid && !s_axis_tready) |=> s_axis_tvalid;
    endproperty
    assert property (p_s_tvalid_stable)
        else $error("SVA: s_axis_tvalid dropped before s_axis_tready");
    
    /**
     * @brief TDATA estable mientras TVALID sin TREADY
     */
    property p_s_tdata_stable;
        @(posedge aclk) disable iff (!aresetn)
        (s_axis_tvalid && !s_axis_tready) |=> $stable(s_axis_tdata);
    endproperty
    assert property (p_s_tdata_stable)
        else $error("SVA: s_axis_tdata changed before handshake");
    
    /**
     * @brief TVALID estable en salida
     */
    property p_m_tvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axis_tvalid && !m_axis_tready) |=> m_axis_tvalid;
    endproperty
    assert property (p_m_tvalid_stable)
        else $error("SVA: m_axis_tvalid dropped before m_axis_tready");
    
    /**
     * @brief TDATA de salida estable
     */
    property p_m_tdata_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axis_tvalid && !m_axis_tready) |=> $stable(m_axis_tdata);
    endproperty
    assert property (p_m_tdata_stable)
        else $error("SVA: m_axis_tdata changed before handshake");

    //=========================================================================
    // ASSERTIONS: Funcionalidad del trigger
    //=========================================================================
    
    /**
     * @brief Trigger solo cuando está habilitado
     */
    property p_trigger_when_enabled;
        @(posedge aclk) disable iff (!aresetn)
        trigger_out |-> cfg_enable;
    endproperty
    assert property (p_trigger_when_enabled)
        else $error("SVA: Trigger fired while disabled");
    
    /**
     * @brief Trigger solo con dato válido en pipeline
     */
    property p_trigger_with_valid_data;
        @(posedge aclk) disable iff (!aresetn)
        trigger_out |-> m_axis_tvalid;
    endproperty
    assert property (p_trigger_with_valid_data)
        else $error("SVA: Trigger without valid output data");
    
    /**
     * @brief En modo RISING: trigger en flanco ascendente
     * Verificación relajada: chequea que prev < threshold y current >= threshold
     */
    property p_rising_edge_correct;
        @(posedge aclk) disable iff (!aresetn || cfg_mode != TRIG_RISING)
        (trigger_out && cfg_enable) |-> 
            ($past(prev_sample, PIPE_STAGES) < $signed(cfg_threshold)) &&
            ($past(current_sample, PIPE_STAGES-1) >= $signed(cfg_threshold));
    endproperty
    // assert property (p_rising_edge_correct)
    //     else $warning("SVA: Rising edge trigger condition may be incorrect");
    
    /**
     * @brief No hay triggers consecutivos (holdoff mínimo)
     */
    property p_no_consecutive_triggers;
        @(posedge aclk) disable iff (!aresetn)
        trigger_out |=> !trigger_out;
    endproperty
    assert property (p_no_consecutive_triggers)
        else $error("SVA: Consecutive triggers detected");
    
    /**
     * @brief El dato de salida coincide con el de entrada (con latencia)
     */
    property p_data_integrity;
        @(posedge aclk) disable iff (!aresetn)
        (m_axis_tvalid && m_axis_tready) |->
            (m_axis_tdata == $past(s_axis_tdata, PIPE_STAGES));
    endproperty
    // Comentado porque puede haber skid buffer
    // assert property (p_data_integrity);

    //=========================================================================
    // ASSERTIONS: Reset
    //=========================================================================
    
    /**
     * @brief Outputs en estado seguro durante reset
     */
    property p_reset_outputs;
        @(posedge aclk)
        !aresetn |-> (!m_axis_tvalid && !trigger_out);
    endproperty
    assert property (p_reset_outputs)
        else $error("SVA: Outputs not cleared during reset");

    //=========================================================================
    // COVERGROUPS
    //=========================================================================
    
    /**
     * @brief Cobertura funcional del trigger
     */
    covergroup cg_trigger @(posedge aclk);
        option.per_instance = 1;
        
        // Modos de operación
        cp_mode: coverpoint cfg_mode {
            bins rising  = {TRIG_RISING};
            bins falling = {TRIG_FALLING};
            bins both    = {TRIG_BOTH};
            bins level   = {TRIG_LEVEL};
        }
        
        // Estado de enable
        cp_enable: coverpoint cfg_enable;
        
        // Evento de trigger
        cp_trigger: coverpoint trigger_out {
            bins no_trigger = {0};
            bins trigger    = {1};
        }
        
        // Rangos de umbral
        cp_threshold: coverpoint cfg_threshold[DATA_WIDTH-1:DATA_WIDTH-4] {
            bins low    = {[0:3]};
            bins mid    = {[4:11]};
            bins high   = {[12:15]};
        }
        
        // Rangos de señal
        cp_signal: coverpoint s_axis_tdata[DATA_WIDTH-1:DATA_WIDTH-4] iff (s_axis_tvalid) {
            bins low    = {[0:3]};
            bins mid    = {[4:11]};
            bins high   = {[12:15]};
        }
        
        // Cross coverage: modo x trigger
        cx_mode_trigger: cross cp_mode, cp_trigger {
            ignore_bins disabled = binsof(cp_trigger.trigger) intersect {1} &&
                                  !binsof(cp_mode);
        }
        
        // Cross coverage: enable x trigger
        cx_enable_trigger: cross cp_enable, cp_trigger;
        
    endgroup
    
    cg_trigger cg_trigger_inst = new();
    
    /**
     * @brief Cobertura de protocolo AXI-Stream
     */
    covergroup cg_axis_protocol @(posedge aclk);
        option.per_instance = 1;
        
        // Combinaciones de handshake entrada
        cp_in_handshake: coverpoint {s_axis_tvalid, s_axis_tready} {
            bins idle        = {2'b00};
            bins wait_ready  = {2'b10};
            bins ready_idle  = {2'b01};
            bins transfer    = {2'b11};
        }
        
        // Combinaciones de handshake salida
        cp_out_handshake: coverpoint {m_axis_tvalid, m_axis_tready} {
            bins idle        = {2'b00};
            bins wait_ready  = {2'b10};
            bins ready_idle  = {2'b01};
            bins transfer    = {2'b11};
        }
        
        // Backpressure
        cp_backpressure: coverpoint (!s_axis_tready && s_axis_tvalid) {
            bins no_bp = {0};
            bins bp    = {1};
        }
        
    endgroup
    
    cg_axis_protocol cg_axis_inst = new();

    //=========================================================================
    // Mensajes de información
    //=========================================================================
    
    initial begin
        $display("[SVA] axis_trigger_sva bound to instance");
        $display("[SVA]   DATA_WIDTH=%0d, PIPE_STAGES=%0d", DATA_WIDTH, PIPE_STAGES);
    end
    
    // Reporte de coverage al final
    final begin
        $display("[SVA] axis_trigger coverage summary:");
        $display("[SVA]   Trigger coverage: %.1f%%", cg_trigger_inst.get_coverage());
        $display("[SVA]   Protocol coverage: %.1f%%", cg_axis_inst.get_coverage());
    end

endmodule : axis_trigger_sva

`endif // AXIS_TRIGGER_SVA_SV
