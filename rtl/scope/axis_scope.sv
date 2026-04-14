/**
 * @file axis_scope.sv
 * @brief Módulo de captura de ventanas de adquisición estilo osciloscopio
 * 
 * Este módulo implementa la funcionalidad de un osciloscopio digital,
 * capturando una ventana de datos alrededor de un evento de trigger.
 * Utiliza un buffer circular para almacenar muestras de pre-trigger
 * y continúa capturando después del evento hasta completar la ventana.
 * 
 * @par Diagrama de bloques:
 * @verbatim
 *                         ┌───────────────────────────────────────┐
 *      s_axis_tdata ──────┤                                       ├── m_axis_tdata
 *     s_axis_tvalid ──────┤                                       ├── m_axis_tvalid
 *     s_axis_tready ◀─────┤             AXIS_SCOPE                ├── m_axis_tready
 *                         │                                       │
 *       trigger_in ───────┤   ┌──────────────┐                    ├── m_axis_tlast
 *                         │   │   CIRCULAR   │                    │
 *          config ────────┤   │    BUFFER    │                    │
 *                         │   │  (PRE_TRIG)  │                    │
 *                         │   └──────────────┘                    │
 *          status ◀───────┤         │                             │
 *                         │         ▼                             │
 *                         │   ┌──────────────┐                    │
 *                         │   │   CAPTURE    │                    │
 *                         │   │     FSM      │                    │
 *                         │   └──────────────┘                    │
 *                         └───────────────────────────────────────┘
 * @endverbatim
 * 
 * @par Estados de operación:
 * - **IDLE**: Módulo inactivo, esperando configuración
 * - **ARMED**: Buffer circular activo, esperando trigger
 * - **TRIGGERED**: Capturando muestras post-trigger
 * - **TRANSFER**: Transfiriendo datos capturados al siguiente módulo
 * - **DONE**: Captura completa, esperando lectura del status
 * 
 * @par Consideraciones de diseño:
 * - El buffer circular permite capturar N muestras previas al trigger
 * - La profundidad del buffer limita el tamaño máximo de pre-trigger
 * - Durante TRANSFER, se envían primero las muestras de pre-trigger
 *   seguidas de las muestras post-trigger
 * 
 * @warning El tamaño del buffer está limitado por los recursos de BRAM
 *          disponibles en la FPGA.
 */

`default_nettype none

module axis_scope
    import axi_stream_pkg::*;
#(
    /** @brief Ancho del bus de datos */
    parameter int unsigned DATA_WIDTH = DSP_DATA_WIDTH,
    
    /** @brief Profundidad del buffer circular (potencia de 2) */
    parameter int unsigned BUFFER_DEPTH = 4096,
    
    /** @brief Número de canales de entrada */
    parameter int unsigned NUM_CH = NUM_CHANNELS
)(
    //=========================================================================
    // Señales de reloj y reset
    //=========================================================================
    
    /** @brief Reloj del sistema */
    input  wire                              aclk,
    
    /** @brief Reset asíncrono activo bajo */
    input  wire                              aresetn,
    
    //=========================================================================
    // Interfaz de configuración y estado
    //=========================================================================
    
    /** @brief Configuración del módulo */
    input  scope_config_t                    config_i,
    
    /** @brief Estado actual del módulo */
    output scope_status_t                    status_o,
    
    //=========================================================================
    // Señal de trigger
    //=========================================================================
    
    /** @brief Entrada de trigger (desde el detector de eventos) */
    input  wire                              trigger_in,
    
    //=========================================================================
    // Interfaz AXI-Stream Slave (entrada de datos)
    //=========================================================================
    
    /** @brief Datos de entrada (muestras) */
    input  wire signed [DATA_WIDTH-1:0]      s_axis_tdata,
    
    /** @brief Datos válidos */
    input  wire                              s_axis_tvalid,
    
    /** @brief Listo para recibir */
    output logic                             s_axis_tready,
    
    //=========================================================================
    // Interfaz AXI-Stream Master (salida de datos capturados)
    //=========================================================================
    
    /** @brief Datos de salida */
    output logic signed [DATA_WIDTH-1:0]     m_axis_tdata,
    
    /** @brief Datos válidos */
    output logic                             m_axis_tvalid,
    
    /** @brief Listo para recibir (desde RAM Writer) */
    input  wire                              m_axis_tready,
    
    /** @brief Indica último dato de la ventana capturada */
    output logic                             m_axis_tlast
);

    //=========================================================================
    // Parámetros locales
    //=========================================================================
    
    /** @brief Bits necesarios para direccionar el buffer */
    localparam int unsigned ADDR_WIDTH = $clog2(BUFFER_DEPTH);
    
    //=========================================================================
    // Estados de la FSM
    //=========================================================================
    
    /**
     * @brief Enumeración de estados del módulo Scope
     */
    typedef enum logic [2:0] {
        ST_IDLE      = 3'b000,  ///< Inactivo
        ST_ARMED     = 3'b001,  ///< Armado, esperando trigger
        ST_TRIGGERED = 3'b010,  ///< Capturando post-trigger
        ST_TRANSFER  = 3'b011,  ///< Transfiriendo datos
        ST_DONE      = 3'b100   ///< Captura completa
    } scope_state_e;
    
    //=========================================================================
    // Declaración de señales internas
    //=========================================================================
    
    /** @brief Estado actual de la FSM */
    scope_state_e state, state_next;
    
    /** @brief Buffer circular para almacenamiento de muestras */
    logic signed [DATA_WIDTH-1:0] sample_buffer [BUFFER_DEPTH];
    
    /** @brief Puntero de escritura del buffer circular */
    logic [ADDR_WIDTH-1:0] write_ptr;
    
    /** @brief Puntero de lectura para transferencia */
    logic [ADDR_WIDTH-1:0] read_ptr;
    
    /** @brief Posición del trigger en el buffer */
    logic [ADDR_WIDTH-1:0] trigger_ptr;
    
    /** @brief Contador de muestras post-trigger capturadas */
    logic [15:0] post_count;
    
    /** @brief Contador de muestras transferidas */
    logic [15:0] transfer_count;
    
    /** @brief Total de muestras a transferir */
    logic [15:0] total_samples;
    
    /** @brief Handshake de entrada */
    logic input_handshake;
    
    /** @brief Handshake de salida */
    logic output_handshake;
    
    /** @brief Registro de datos leídos del buffer */
    logic signed [DATA_WIDTH-1:0] read_data;
    
    /** @brief Indica que read_data tiene un valor válido (maneja latencia de lectura) */
    logic read_valid;

    //=========================================================================
    // Lógica de handshake
    //=========================================================================
    
    assign input_handshake  = s_axis_tvalid & s_axis_tready;
    assign output_handshake = m_axis_tvalid & m_axis_tready;

    //=========================================================================
    // Máquina de estados - Lógica de transición
    //=========================================================================
    
    /**
     * @brief Lógica combinacional de próximo estado
     * 
     * Define las transiciones de la FSM basadas en el estado actual
     * y las señales de entrada/configuración.
     */
    always_comb begin : proc_next_state
        state_next = state;
        
        case (state)
            ST_IDLE: begin
                // Transición a ARMED cuando se habilita y arma
                if (config_i.enable && config_i.arm) begin
                    state_next = ST_ARMED;
                end
            end
            
            ST_ARMED: begin
                // Transición a TRIGGERED cuando llega el evento
                if (trigger_in) begin
                    state_next = ST_TRIGGERED;
                end
                // Volver a IDLE si se desactiva
                else if (!config_i.enable) begin
                    state_next = ST_IDLE;
                end
            end
            
            ST_TRIGGERED: begin
                // Transición a TRANSFER cuando se completa post-trigger
                if (post_count >= config_i.post_samples) begin
                    state_next = ST_TRANSFER;
                end
            end
            
            ST_TRANSFER: begin
                // Transición a DONE cuando se transfieren todos los datos
                if (output_handshake && m_axis_tlast) begin
                    state_next = ST_DONE;
                end
            end
            
            ST_DONE: begin
                // Volver a IDLE cuando se reconoce el estado
                // (típicamente cuando software lee el status)
                if (!config_i.enable) begin
                    state_next = ST_IDLE;
                end
                // O re-armar directamente para siguiente captura
                else if (config_i.arm) begin
                    state_next = ST_ARMED;
                end
            end
            
            default: state_next = ST_IDLE;
        endcase
    end
    
    /**
     * @brief Registro de estado
     */
    always_ff @(posedge aclk or negedge aresetn) begin : proc_state_reg
        if (!aresetn) begin
            state <= ST_IDLE;
        end
        else begin
            state <= state_next;
        end
    end

    //=========================================================================
    // Lógica del buffer circular
    //=========================================================================
    
    /**
     * @brief Proceso de escritura al buffer circular
     * 
     * Escribe muestras continuamente mientras está ARMED o TRIGGERED.
     * El puntero de escritura se envuelve automáticamente.
     */
    always_ff @(posedge aclk or negedge aresetn) begin : proc_buffer_write
        if (!aresetn) begin
            write_ptr <= '0;
        end
        else if (input_handshake) begin
            if (state == ST_ARMED || state == ST_TRIGGERED) begin
                sample_buffer[write_ptr] <= s_axis_tdata;
                write_ptr <= write_ptr + 1'b1;  // Auto-wrap por overflow
            end
        end
    end
    
    /**
     * @brief Captura de la posición del trigger
     * 
     * Registra la posición del puntero de escritura cuando ocurre
     * el trigger, para poder calcular dónde inicia el pre-trigger.
     */
    always_ff @(posedge aclk or negedge aresetn) begin : proc_trigger_capture
        if (!aresetn) begin
            trigger_ptr <= '0;
        end
        else if (state == ST_ARMED && trigger_in) begin
            trigger_ptr <= write_ptr;
        end
    end
    
    /**
     * @brief Contador de muestras post-trigger
     */
    always_ff @(posedge aclk or negedge aresetn) begin : proc_post_counter
        if (!aresetn) begin
            post_count <= '0;
        end
        else if (state == ST_ARMED) begin
            post_count <= '0;
        end
        else if (state == ST_TRIGGERED && input_handshake) begin
            post_count <= post_count + 1'b1;
        end
    end

    //=========================================================================
    // Lógica de lectura y transferencia
    //=========================================================================
    
    /**
     * @brief Cálculo del puntero de inicio de lectura
     * 
     * El inicio de lectura es: trigger_ptr - pre_samples
     * Esto apunta al inicio de la ventana de pre-trigger.
     */
    always_ff @(posedge aclk or negedge aresetn) begin : proc_read_ptr
        if (!aresetn) begin
            read_ptr       <= '0;
            transfer_count <= '0;
            total_samples  <= '0;
        end
        else begin
            case (state)
                ST_TRIGGERED: begin
                    if (state_next == ST_TRANSFER) begin
                        // Inicializar puntero de lectura
                        read_ptr <= trigger_ptr - config_i.pre_samples[ADDR_WIDTH-1:0];
                        transfer_count <= '0;
                        total_samples <= config_i.pre_samples + config_i.post_samples;
                    end
                end
                
                ST_TRANSFER: begin
                    if (output_handshake) begin
                        read_ptr <= read_ptr + 1'b1;
                        transfer_count <= transfer_count + 1'b1;
                    end
                end
                
                default: begin
                    // Mantener valores
                end
            endcase
        end
    end
    
    /**
     * @brief Lectura del buffer
     */
    always_ff @(posedge aclk) begin : proc_buffer_read
        read_data <= sample_buffer[read_ptr];
    end
    
    /**
     * @brief Control de validez de lectura
     * 
     * La lectura del buffer tiene 1 ciclo de latencia (read_data es un registro).
     * Esta señal se activa 1 ciclo después de entrar a ST_TRANSFER,
     * asegurando que read_data tenga un valor válido antes de activar tvalid.
     */
    always_ff @(posedge aclk or negedge aresetn) begin : proc_read_valid
        if (!aresetn) begin
            read_valid <= 1'b0;
        end
        else begin
            read_valid <= (state == ST_TRANSFER);
        end
    end

    //=========================================================================
    // Control de flujo AXI-Stream
    //=========================================================================
    
    /**
     * @brief Control de TREADY de entrada
     * 
     * Acepta datos cuando está ARMED o TRIGGERED.
     */
    always_comb begin : proc_tready
        case (state)
            ST_ARMED, ST_TRIGGERED: s_axis_tready = 1'b1;
            default:                s_axis_tready = 1'b0;
        endcase
    end
    
    /**
     * @brief Generación de señales de salida
     * 
     * tvalid solo se activa cuando read_valid=1, lo que garantiza
     * que read_data tiene un valor válido del buffer (1 ciclo después
     * de entrar a ST_TRANSFER).
     */
    always_comb begin : proc_output
        m_axis_tdata  = read_data;
        m_axis_tvalid = (state == ST_TRANSFER) && read_valid;
        m_axis_tlast  = (state == ST_TRANSFER) && read_valid &&
                        (transfer_count == total_samples - 1);
    end

    //=========================================================================
    // Generación de señales de estado
    //=========================================================================
    
    /**
     * @brief Asignación del estado de salida
     */
    always_comb begin : proc_status
        status_o.armed        = (state == ST_ARMED);
        status_o.triggered    = (state == ST_TRIGGERED) || 
                                (state == ST_TRANSFER) || 
                                (state == ST_DONE);
        status_o.done         = (state == ST_DONE);
        status_o.sample_count = {16'b0, transfer_count};
    end

    //=========================================================================
    // Assertions de verificación
    //=========================================================================
    
`ifndef SYNTHESIS
    /**
     * @brief Assertion: No overflow durante captura
     * 
     * Verifica que pre_samples no exceda el tamaño del buffer.
     */
    property p_no_pretrig_overflow;
        @(posedge aclk) disable iff (!aresetn)
        (state == ST_ARMED && config_i.arm) |-> 
        (config_i.pre_samples <= BUFFER_DEPTH);
    endproperty
    
    assert property (p_no_pretrig_overflow)
        else $warning("[AXIS_SCOPE] pre_samples excede BUFFER_DEPTH");
    
    /**
     * @brief Assertion: TLAST solo con última muestra
     */
    property p_tlast_correct;
        @(posedge aclk) disable iff (!aresetn)
        m_axis_tlast |-> (transfer_count == total_samples - 1);
    endproperty
    
    assert property (p_tlast_correct)
        else $error("[AXIS_SCOPE] TLAST incorrecto");
    
    /**
     * @brief Cover: Captura completa exitosa
     */
    cover property (@(posedge aclk) disable iff (!aresetn)
        (state == ST_TRANSFER) ##[1:$] (state == ST_DONE));
    
    /**
     * @brief Cover: Re-arm después de captura
     */
    cover property (@(posedge aclk) disable iff (!aresetn)
        (state == ST_DONE) ##[1:5] (state == ST_ARMED));
`endif

endmodule : axis_scope

`default_nettype wire
