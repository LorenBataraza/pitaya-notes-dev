/**
 * @file axis_trigger.sv
 * @brief Detector de eventos configurable con interfaz AXI-Stream
 * 
 * Este módulo implementa un detector de eventos (trigger) que analiza
 * un flujo de muestras AXI-Stream y genera una señal de disparo cuando
 * se detecta un cruce de umbral según el modo configurado.
 * 
 * @par Diagrama de bloques:
 * @verbatim
 *                    ┌─────────────────────────────────────┐
 *     s_axis_tdata ──┤                                     ├── m_axis_tdata
 *    s_axis_tvalid ──┤          AXIS_TRIGGER               ├── m_axis_tvalid
 *    s_axis_tready ◀─┤                                     ├── m_axis_tready
 *                    │                                     │
 *           config ──┤    ┌─────────┐    ┌──────────┐     ├── trigger_out
 *                    │    │ SAMPLE  │───▶│ DETECTOR │─────│
 *                    │    │ DELAY   │    │  LOGIC   │     │
 *                    │    └─────────┘    └──────────┘     │
 *                    └─────────────────────────────────────┘
 * @endverbatim
 * 
 * @par Modos de operación:
 * - **TRIG_RISING**: Dispara cuando la señal cruza el umbral de abajo hacia arriba
 * - **TRIG_FALLING**: Dispara cuando la señal cruza el umbral de arriba hacia abajo
 * - **TRIG_BOTH**: Dispara en cualquier cruce de umbral
 * - **TRIG_LEVEL**: Dispara mientras la señal está por encima del umbral
 * 
 * @par Latencia:
 * El módulo introduce una latencia de 2 ciclos de reloj entre la entrada
 * y la salida para permitir la detección de flancos.
 * 
 * @par Ejemplo de uso en un sistema:
 * @code{.sv}
 * axis_trigger #(
 *     .DATA_WIDTH(16)
 * ) u_trigger (
 *     .aclk(clk_125mhz),
 *     .aresetn(sys_resetn),
 *     .config_i(trigger_cfg),
 *     .s_axis_tdata(adc_data),
 *     .s_axis_tvalid(adc_valid),
 *     .s_axis_tready(adc_ready),
 *     .m_axis_tdata(trig_data),
 *     .m_axis_tvalid(trig_valid),
 *     .m_axis_tready(trig_ready),
 *     .trigger_out(trigger_pulse)
 * );
 * @endcode
 */

`default_nettype none

module axis_trigger
    import axi_stream_pkg::*;
#(
    /** @brief Ancho del bus de datos de entrada/salida */
    parameter int unsigned DATA_WIDTH = DSP_DATA_WIDTH,
    
    /** @brief Número de etapas de pipeline para timing */
    parameter int unsigned PIPE_STAGES = 2
)(
    //=========================================================================
    // Señales de reloj y reset
    //=========================================================================
    
    /** @brief Reloj del sistema (flanco positivo) */
    input  wire                      aclk,
    
    /** @brief Reset asíncrono activo bajo */
    input  wire                      aresetn,
    
    //=========================================================================
    // Interfaz de configuración
    //=========================================================================
    
    /** @brief Estructura de configuración del trigger */
    input  trigger_config_t          config_i,
    
    //=========================================================================
    // Interfaz AXI-Stream Slave (entrada de datos)
    //=========================================================================
    
    /** @brief Datos de entrada (muestras del ADC/DSP) */
    input  wire signed [DATA_WIDTH-1:0] s_axis_tdata,
    
    /** @brief Indica datos válidos en la entrada */
    input  wire                         s_axis_tvalid,
    
    /** @brief Indica que este módulo puede recibir datos */
    output logic                        s_axis_tready,
    
    //=========================================================================
    // Interfaz AXI-Stream Master (salida de datos)
    //=========================================================================
    
    /** @brief Datos de salida (pass-through con delay) */
    output logic signed [DATA_WIDTH-1:0] m_axis_tdata,
    
    /** @brief Indica datos válidos en la salida */
    output logic                         m_axis_tvalid,
    
    /** @brief Indica que el siguiente módulo puede recibir */
    input  wire                          m_axis_tready,
    
    //=========================================================================
    // Señal de trigger
    //=========================================================================
    
    /** @brief Pulso de trigger (1 ciclo de duración) */
    output logic                         trigger_out
);

    //=========================================================================
    // Declaración de señales internas
    //=========================================================================
    
    /** @brief Pipeline de muestras para detección de flancos */
    logic signed [DATA_WIDTH-1:0] sample_pipe [PIPE_STAGES];
    
    /** @brief Pipeline de validez de datos */
    logic                         valid_pipe [PIPE_STAGES];
    
    /** @brief Muestra anterior para comparación */
    logic signed [DATA_WIDTH-1:0] prev_sample;
    
    /** @brief Muestra actual para comparación */
    logic signed [DATA_WIDTH-1:0] curr_sample;
    
    /** @brief Indica cruce de umbral detectado */
    logic                         threshold_event;
    
    /** @brief Registro del trigger para evitar retriggering */
    logic                         trigger_armed;
    
    /** @brief Indica que el handshake AXI está completo */
    logic                         axis_handshake;

    //=========================================================================
    // Lógica de control de flujo AXI-Stream
    //=========================================================================
    
    /**
     * @brief Handshake AXI-Stream
     * 
     * Una transferencia válida ocurre cuando tanto TVALID como TREADY
     * están activos simultáneamente.
     */
    assign axis_handshake = s_axis_tvalid & s_axis_tready;
    
    /**
     * @brief Control de TREADY
     * 
     * Este módulo acepta datos cuando:
     * - Está habilitado, O
     * - El downstream puede recibir datos
     * 
     * Esto implementa back-pressure transparente.
     */
    assign s_axis_tready = m_axis_tready | ~m_axis_tvalid;

    //=========================================================================
    // Pipeline de datos
    //=========================================================================
    
    /**
     * @brief Proceso de pipeline de muestras
     * 
     * Implementa una línea de retardo para las muestras, necesaria
     * para la detección de flancos (se requiere comparar muestra
     * actual con la anterior).
     */
    always_ff @(posedge aclk or negedge aresetn) begin : proc_sample_pipeline
        if (!aresetn) begin
            for (int i = 0; i < PIPE_STAGES; i++) begin
                sample_pipe[i] <= '0;
                valid_pipe[i]  <= 1'b0;
            end
        end
        else if (axis_handshake) begin
            // Primera etapa: entrada directa
            sample_pipe[0] <= s_axis_tdata;
            valid_pipe[0]  <= s_axis_tvalid;
            
            // Etapas subsecuentes: shift register
            for (int i = 1; i < PIPE_STAGES; i++) begin
                sample_pipe[i] <= sample_pipe[i-1];
                valid_pipe[i]  <= valid_pipe[i-1];
            end
        end
    end
    
    /**
     * @brief Asignación de muestras para comparación
     */
    assign prev_sample = sample_pipe[PIPE_STAGES-1];
    assign curr_sample = sample_pipe[PIPE_STAGES-2];

    //=========================================================================
    // Lógica de detección de trigger
    //=========================================================================
    
    /**
     * @brief Proceso de detección de eventos
     * 
     * Compara la muestra actual con la anterior para detectar
     * cruces de umbral según el modo configurado.
     * 
     * @note La detección utiliza aritmética con signo para manejar
     *       correctamente señales bipolares.
     */
    always_comb begin : proc_threshold_detection
        logic rising_edge;
        logic falling_edge;
        
        // Detección de flancos con respecto al umbral
        rising_edge  = (prev_sample < config_i.threshold) && 
                       (curr_sample >= config_i.threshold);
        falling_edge = (prev_sample >= config_i.threshold) && 
                       (curr_sample < config_i.threshold);
        
        // Selección según modo configurado
        case (config_i.mode)
            TRIG_RISING:  threshold_event = rising_edge;
            TRIG_FALLING: threshold_event = falling_edge;
            TRIG_BOTH:    threshold_event = rising_edge | falling_edge;
            TRIG_LEVEL:   threshold_event = (curr_sample >= config_i.threshold);
            default:      threshold_event = 1'b0;
        endcase
    end
    
    /**
     * @brief Proceso de generación del pulso de trigger
     * 
     * Genera un pulso de un ciclo cuando se detecta un evento
     * y el trigger está habilitado y armado.
     * 
     * @note El mecanismo de "armado" previene múltiples triggers
     *       para un mismo evento (retriggering).
     */
    always_ff @(posedge aclk or negedge aresetn) begin : proc_trigger_output
        if (!aresetn) begin
            trigger_out   <= 1'b0;
            trigger_armed <= 1'b0;
        end
        else begin
            // Valor por defecto: sin trigger
            trigger_out <= 1'b0;
            
            if (!config_i.enable) begin
                // Trigger deshabilitado: mantener armado
                trigger_armed <= 1'b1;
            end
            else if (valid_pipe[PIPE_STAGES-2] && trigger_armed) begin
                if (threshold_event) begin
                    trigger_out   <= 1'b1;
                    trigger_armed <= 1'b0;  // Desarmar hasta que baje del umbral
                end
            end
            else if (!threshold_event) begin
                // Re-armar cuando la señal sale de la zona de trigger
                trigger_armed <= 1'b1;
            end
        end
    end

    //=========================================================================
    // Salida AXI-Stream (pass-through con delay)
    //=========================================================================
    
    /**
     * @brief Asignación de señales de salida
     * 
     * Los datos se pasan directamente con un delay igual al número
     * de etapas de pipeline.
     */
    assign m_axis_tdata  = sample_pipe[PIPE_STAGES-1];
    assign m_axis_tvalid = valid_pipe[PIPE_STAGES-1] & config_i.enable;

    //=========================================================================
    // Assertions para verificación
    //=========================================================================
    
`ifndef SYNTHESIS
    /**
     * @brief Assertion: Trigger solo con datos válidos
     */
    property p_trigger_requires_valid;
        @(posedge aclk) disable iff (!aresetn)
        trigger_out |-> valid_pipe[PIPE_STAGES-2];
    endproperty
    
    assert property (p_trigger_requires_valid)
        else $error("[AXIS_TRIGGER] Trigger generado sin datos válidos");
    
    /**
     * @brief Assertion: TVALID estable hasta handshake
     */
    property p_tvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axis_tvalid && !m_axis_tready) |=> m_axis_tvalid;
    endproperty
    
    assert property (p_tvalid_stable)
        else $error("[AXIS_TRIGGER] TVALID cayó sin handshake");
    
    /**
     * @brief Cover: Detección de flanco ascendente
     */
    cover property (@(posedge aclk) disable iff (!aresetn)
        config_i.mode == TRIG_RISING && trigger_out);
    
    /**
     * @brief Cover: Detección de flanco descendente
     */
    cover property (@(posedge aclk) disable iff (!aresetn)
        config_i.mode == TRIG_FALLING && trigger_out);
`endif

endmodule : axis_trigger

`default_nettype wire
