/**
 * @file axis_scope.sv
 * @brief Módulo de captura de ventanas de adquisición estilo osciloscopio
 * 
 * @details Captura una ventana de samples centrada alrededor de un evento
 * de trigger externo. La ventana consiste en pre_samples antes del trigger
 * y post_samples desde el trigger (incluyendo el sample del trigger).
 * 
 * @par Análisis de timing del pipeline:
 * 
 * El sistema completo tiene el siguiente pipeline:
 * 
 *   axis_trigger (PIPE_STAGES=2):
 *     - Ciclo N:   sample X entra, se evalúa threshold
 *     - Ciclo N+1: trig0_out = 1, m_axis_tdata = X-1 (dato anterior)
 *     - Ciclo N+2: m_axis_tdata = X (dato del trigger)
 * 
 *   trigger_combiner (registrado):
 *     - Ciclo N+1: combined = 1 (combinacional)
 *     - Ciclo N+2: trigger_out = 1 (registrado)
 * 
 *   axis_scope:
 *     - Ciclo N+1: recibe dato X-1, escribe en buffer[W], W++
 *     - Ciclo N+2: trigger_in = 1, recibe dato X
 *                  escribe buffer[W] = X, captura trigger_ptr
 * 
 * El problema: Cuando trigger_in = 1, el dato X ya fue escrito en buffer[W],
 * pero write_ptr ya avanzó a W+1 (en el flanco del mismo ciclo).
 * 
 * Además, debido al registro del combiner, cuando trigger_in = 1:
 *   - El dato actual (X) es el que SIGUE al trigger real
 *   - El trigger real fue en el ciclo anterior (dato X-1)
 * 
 * Conclusión: trigger_ptr = write_ptr - 1 apunta al sample del trigger real.
 * 
 * Ejemplo con threshold=500, rampa 0,1,2,...:
 *   - Ciclo T:   axis_trigger recibe 500, detecta cruce
 *   - Ciclo T+1: trig0_out=1, m_axis_tdata=500, combiner.combined=1
 *   - Ciclo T+2: trigger_out=1, m_axis_tdata=501
 *                scope ve trigger_in=1, write_ptr apunta a pos de 501
 *                trigger_ptr = write_ptr - 1 = posición de 500 ✓
 */

`default_nettype none

module axis_scope
    import axi_stream_pkg::*;
#(
    parameter int unsigned DATA_WIDTH   = DSP_DATA_WIDTH,
    parameter int unsigned BUFFER_DEPTH = 4096,
    parameter int unsigned NUM_CH       = NUM_CHANNELS
)(
    input  wire                              aclk,
    input  wire                              aresetn,
    input  scope_config_t                    config_i,
    output scope_status_t                    status_o,
    input  wire                              trigger_in,
    input  wire signed [DATA_WIDTH-1:0]      s_axis_tdata,
    input  wire                              s_axis_tvalid,
    output logic                             s_axis_tready,
    output logic signed [DATA_WIDTH-1:0]     m_axis_tdata,
    output logic                             m_axis_tvalid,
    input  wire                              m_axis_tready,
    output logic                             m_axis_tlast
);

    localparam int unsigned ADDR_WIDTH = $clog2(BUFFER_DEPTH);
    
    typedef enum logic [2:0] {
        ST_IDLE      = 3'b000,
        ST_ARMED     = 3'b001,
        ST_TRIGGERED = 3'b010,
        ST_TRANSFER  = 3'b011,
        ST_DONE      = 3'b100
    } scope_state_e;
    
    scope_state_e state, state_next;
    
    logic signed [DATA_WIDTH-1:0] sample_buffer [BUFFER_DEPTH];
    logic [ADDR_WIDTH-1:0] write_ptr;
    logic [ADDR_WIDTH-1:0] read_ptr;
    logic [ADDR_WIDTH-1:0] trigger_ptr;
    
    logic [15:0] post_count;
    logic [15:0] transfer_count;
    logic [15:0] total_samples;
    
    logic input_handshake;
    logic output_handshake;
    logic signed [DATA_WIDTH-1:0] read_data_reg;
    logic wait_for_data;
    logic transfer_active;

    assign input_handshake  = s_axis_tvalid & s_axis_tready;
    assign output_handshake = m_axis_tvalid & m_axis_tready;

    //=========================================================================
    // FSM: Control de estados
    //=========================================================================
    
    /**
     * @brief FSM de control de estados
     * 
     * @note Transición ST_TRIGGERED → ST_TRANSFER:
     * La condición usa `post_count + 2 >= post_samples` porque 2 samples
     * de la ventana "post" se escriben mientras el estado todavía es ARMED:
     *   - Sample N (trigger real): escrito cuando trig0_out=1, state=ARMED
     *   - Sample N+1: escrito cuando trigger_in=1, state=ARMED (antes del flanco)
     * Estos 2 samples no incrementan post_count pero sí son parte de post_samples.
     */
    always_comb begin : proc_next_state
        state_next = state;
        case (state)
            ST_IDLE:      if (config_i.enable && config_i.arm) state_next = ST_ARMED;
            ST_ARMED:     if (trigger_in) state_next = ST_TRIGGERED;
                          else if (!config_i.enable) state_next = ST_IDLE;
            ST_TRIGGERED: if (post_count + 2 >= config_i.post_samples) state_next = ST_TRANSFER;
            ST_TRANSFER:  if (output_handshake && transfer_count == total_samples - 1) state_next = ST_DONE;
            ST_DONE:      if (!config_i.enable) state_next = ST_IDLE;
                          else if (config_i.arm) state_next = ST_ARMED;
            default:      state_next = ST_IDLE;
        endcase
    end
    
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) state <= ST_IDLE;
        else          state <= state_next;
    end

    //=========================================================================
    // Escritura al Buffer Circular
    //=========================================================================
    
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            write_ptr <= '0;
        end
        else if (input_handshake && (state == ST_ARMED || state == ST_TRIGGERED)) begin
            sample_buffer[write_ptr] <= s_axis_tdata;
            write_ptr <= write_ptr + 1'b1;
        end
    end
    
    /**
     * @brief Captura de trigger_ptr con compensación de pipeline
     * 
     * Cuando trigger_in = 1 (del combiner, 1 ciclo después de trig0_out),
     * el sample del trigger REAL ya fue escrito en el ciclo anterior.
     * write_ptr apunta a la posición SIGUIENTE, así que restamos 1.
     */
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            trigger_ptr <= '0;
        else if (state == ST_ARMED && trigger_in)
            trigger_ptr <= write_ptr - 1'b1;  // Compensación por registro del combiner
    end
    
    /**
     * @brief Contador de samples post-trigger
     * 
     * Cuenta los samples recibidos después del trigger para determinar
     * cuándo la ventana de captura está completa.
     */
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            post_count <= '0;
        else if (state == ST_ARMED)
            post_count <= '0;
        else if (state == ST_TRIGGERED && input_handshake)
            post_count <= post_count + 1'b1;
    end

    //=========================================================================
    // Lectura y Transferencia de Datos
    //=========================================================================
    
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            read_ptr        <= '0;
            transfer_count  <= '0;
            total_samples   <= '0;
            transfer_active <= 1'b0;
        end
        else begin
            case (state)
                ST_TRIGGERED: begin
                    if (state_next == ST_TRANSFER) begin
                        read_ptr        <= trigger_ptr - config_i.pre_samples[ADDR_WIDTH-1:0];
                        transfer_count  <= '0;
                        total_samples   <= config_i.pre_samples + config_i.post_samples;
                        transfer_active <= 1'b1;
                    end
                end
                
                ST_TRANSFER: begin
                    if (output_handshake) begin
                        transfer_count <= transfer_count + 1'b1;
                        if (transfer_count < total_samples - 1)
                            read_ptr <= read_ptr + 1'b1;
                        else
                            transfer_active <= 1'b0;
                    end
                end
                
                default: transfer_active <= 1'b0;
            endcase
        end
    end
    
    /**
     * @brief Registro de lectura del buffer
     * 
     * Lectura síncrona con 1 ciclo de latencia. Se actualiza cada ciclo
     * con el contenido de sample_buffer[read_ptr].
     */
    always_ff @(posedge aclk) begin
        read_data_reg <= sample_buffer[read_ptr];
    end
    
    /**
     * @brief Control de ciclo de espera para lectura
     * 
     * Después de cada handshake de salida, se requiere 1 ciclo de espera
     * para que read_data_reg se actualice con el nuevo valor del buffer.
     * Esto resulta en un throughput del 50% (1 dato cada 2 ciclos).
     */
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wait_for_data <= 1'b0;
        end
        else begin
            if (state == ST_TRIGGERED && state_next == ST_TRANSFER)
                wait_for_data <= 1'b1;
            else if (state == ST_TRANSFER) begin
                if (wait_for_data)
                    wait_for_data <= 1'b0;
                else if (output_handshake && transfer_count < total_samples - 1)
                    wait_for_data <= 1'b1;
            end
            else
                wait_for_data <= 1'b0;
        end
    end

    //=========================================================================
    // Señales de Salida
    //=========================================================================
    
    always_comb begin
        s_axis_tready = (state == ST_ARMED || state == ST_TRIGGERED);
        m_axis_tdata  = read_data_reg;
        m_axis_tvalid = (state == ST_TRANSFER) && transfer_active && !wait_for_data;
        m_axis_tlast  = m_axis_tvalid && (transfer_count == total_samples - 1);
    end

    always_comb begin
        status_o.armed        = (state == ST_ARMED);
        status_o.triggered    = (state == ST_TRIGGERED) || (state == ST_TRANSFER) || (state == ST_DONE);
        status_o.done         = (state == ST_DONE);
        status_o.sample_count = {16'b0, transfer_count};
    end

    //=========================================================================
    // Assertions y Debug
    //=========================================================================

`ifndef SYNTHESIS
    assert property (@(posedge aclk) disable iff (!aresetn)
        (state == ST_ARMED && config_i.arm) |-> (config_i.pre_samples <= BUFFER_DEPTH))
        else $warning("[AXIS_SCOPE] pre_samples excede BUFFER_DEPTH");
    
    assert property (@(posedge aclk) disable iff (!aresetn)
        m_axis_tlast |-> (transfer_count == total_samples - 1))
        else $error("[AXIS_SCOPE] TLAST incorrecto");
    
    assert property (@(posedge aclk) disable iff (!aresetn)
        wait_for_data |-> !m_axis_tvalid)
        else $error("[AXIS_SCOPE] tvalid activo durante espera");

    // Debug detallado
    always @(posedge aclk) begin
        if (state == ST_TRANSFER && output_handshake && transfer_count >= total_samples - 10) begin
            $display("[SCOPE @%0t] HANDSHAKE #%0d: rp=%0d data=0x%04X | ts=%0d cond(%0d<%0d)=%b",
                     $time, transfer_count, read_ptr, read_data_reg,
                     total_samples, transfer_count, total_samples-1,
                     (transfer_count < total_samples - 1));
        end
        if (state == ST_TRIGGERED && state_next == ST_TRANSFER) begin
            $display("[SCOPE] TRANSFER START: pre=%0d post=%0d => total_samples=%0d, trigger_ptr=%0d, read_ptr=%0d",
                     config_i.pre_samples, config_i.post_samples,
                     config_i.pre_samples + config_i.post_samples,
                     trigger_ptr, trigger_ptr - config_i.pre_samples);
        end
    end
`endif

endmodule : axis_scope

`default_nettype wire
