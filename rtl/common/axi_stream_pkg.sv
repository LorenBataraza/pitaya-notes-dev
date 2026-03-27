/**
 * @file axi_stream_pkg.sv
 * @brief Package con definiciones y tipos para interfaces AXI-Stream
 * 
 * Este package define las estructuras de datos, parámetros y funciones
 * auxiliares utilizadas en todos los módulos que implementan interfaces
 * AXI-Stream según la especificación ARM AMBA 4.
 * 
 * @par Especificación de referencia:
 * ARM IHI 0051A - AMBA 4 AXI4-Stream Protocol Specification
 * 
 * @par Señales AXI-Stream utilizadas:
 * | Señal  | Dirección | Descripción                              |
 * |--------|-----------|------------------------------------------|
 * | TVALID | M -> S    | Indica datos válidos en el bus           |
 * | TREADY | S -> M    | Indica que el slave puede recibir datos  |
 * | TDATA  | M -> S    | Payload de datos                         |
 * | TLAST  | M -> S    | Indica fin de paquete/frame              |
 * | TKEEP  | M -> S    | Indica bytes válidos (opcional)          |
 * 
 * @note Este package asume operación síncrona con un único dominio de reloj.
 */

package axi_stream_pkg;

    //=========================================================================
    // Parámetros globales del sistema
    //=========================================================================
    
    /** @brief Frecuencia del reloj del sistema en Hz */
    parameter int unsigned SYS_CLK_FREQ_HZ = 125_000_000;
    
    /** @brief Ancho de palabra del ADC en bits */
    parameter int unsigned ADC_DATA_WIDTH = 14;
    
    /** @brief Ancho de palabra después del procesamiento DSP */
    parameter int unsigned DSP_DATA_WIDTH = 16;
    
    /** @brief Ancho del bus AXI4 para acceso a memoria */
    parameter int unsigned AXI_DATA_WIDTH = 64;
    
    /** @brief Ancho de dirección AXI4 */
    parameter int unsigned AXI_ADDR_WIDTH = 32;
    
    /** @brief Número de canales de adquisición */
    parameter int unsigned NUM_CHANNELS = 2;

    //=========================================================================
    // Tipos de datos para AXI-Stream
    //=========================================================================
    
    /**
     * @brief Estructura para señales AXI-Stream del lado Master
     * 
     * Esta estructura agrupa todas las señales que genera un master
     * AXI-Stream. Se utiliza para simplificar la conexión entre módulos.
     * 
     * @tparam DATA_WIDTH Ancho del bus de datos en bits
     */
    typedef struct packed {
        logic                       tvalid;  ///< Datos válidos disponibles
        logic [DSP_DATA_WIDTH-1:0]  tdata;   ///< Datos de la muestra
        logic                       tlast;   ///< Último dato del paquete
    } axis_master_t;
    
    /**
     * @brief Estructura para señales AXI-Stream del lado Slave
     * 
     * Contiene la única señal que genera el slave: la indicación
     * de que está listo para recibir datos.
     */
    typedef struct packed {
        logic tready;  ///< Slave listo para recibir
    } axis_slave_t;
    
    /**
     * @brief Tipo para representar una muestra de datos con metadatos
     * 
     * Incluye el valor de la muestra junto con información adicional
     * sobre su origen y validez.
     */
    typedef struct packed {
        logic [DSP_DATA_WIDTH-1:0] sample;      ///< Valor de la muestra
        logic [$clog2(NUM_CHANNELS)-1:0] ch_id; ///< ID del canal origen
        logic triggered;                         ///< Indica si causó trigger
    } sample_metadata_t;

    //=========================================================================
    // Tipos para configuración del Trigger
    //=========================================================================
    
    /**
     * @brief Enumeración de modos de detección del trigger
     */
    typedef enum logic [1:0] {
        TRIG_RISING  = 2'b00,  ///< Flanco ascendente
        TRIG_FALLING = 2'b01,  ///< Flanco descendente
        TRIG_BOTH    = 2'b10,  ///< Ambos flancos
        TRIG_LEVEL   = 2'b11   ///< Por nivel
    } trigger_mode_e;
    
    /**
     * @brief Estructura de configuración del trigger
     * 
     * Contiene todos los parámetros necesarios para configurar
     * el comportamiento del detector de eventos.
     */
    typedef struct packed {
        logic                      enable;     ///< Habilita el trigger
        trigger_mode_e             mode;       ///< Modo de detección
        logic signed [15:0]        threshold;  ///< Umbral de disparo
        logic [NUM_CHANNELS-1:0]   ch_mask;    ///< Máscara de canales habilitados
    } trigger_config_t;

    //=========================================================================
    // Tipos para configuración del Scope
    //=========================================================================
    
    /**
     * @brief Estructura de configuración del módulo Scope
     */
    typedef struct packed {
        logic        enable;        ///< Habilita la captura
        logic        arm;           ///< Arma el trigger (espera evento)
        logic [15:0] pre_samples;   ///< Muestras antes del trigger
        logic [15:0] post_samples;  ///< Muestras después del trigger
    } scope_config_t;
    
    /**
     * @brief Estructura de estado del módulo Scope
     */
    typedef struct packed {
        logic        armed;         ///< Indica si está armado
        logic        triggered;     ///< Indica si se detectó trigger
        logic        done;          ///< Indica captura completa
        logic [31:0] sample_count;  ///< Contador de muestras capturadas
    } scope_status_t;

    //=========================================================================
    // Tipos para el RAM Writer
    //=========================================================================
    
    /**
     * @brief Estados de la máquina de estados del RAM Writer
     */
    typedef enum logic [2:0] {
        WR_IDLE     = 3'b000,  ///< Esperando datos
        WR_CALC     = 3'b001,  ///< Calculando dirección de burst
        WR_ADDR     = 3'b010,  ///< Enviando dirección AXI
        WR_DATA     = 3'b011,  ///< Transfiriendo datos
        WR_RESP     = 3'b100,  ///< Esperando respuesta
        WR_ERROR    = 3'b101   ///< Estado de error
    } ram_writer_state_e;
    
    /**
     * @brief Configuración del RAM Writer
     */
    typedef struct packed {
        logic        enable;       ///< Habilita escrituras
        logic [31:0] base_addr;    ///< Dirección base en DDR
        logic [31:0] buffer_size;  ///< Tamaño del buffer circular
    } ram_writer_config_t;
    
    /**
     * @brief Estado del RAM Writer
     */
    typedef struct packed {
        ram_writer_state_e state;       ///< Estado actual de la FSM
        logic [31:0]       write_ptr;   ///< Puntero de escritura actual
        logic [31:0]       bytes_written; ///< Total de bytes escritos
        logic              overflow;    ///< Indica overflow del buffer
    } ram_writer_status_t;

    //=========================================================================
    // Tipos para el Pulse Height Analyzer
    //=========================================================================
    
    /**
     * @brief Estructura de salida del PHA
     * 
     * Contiene la información extraída de cada pulso detectado.
     */
    typedef struct packed {
        logic [DSP_DATA_WIDTH-1:0] peak_value;   ///< Valor máximo del pulso
        logic [15:0]               peak_time;    ///< Tiempo del pico (en muestras)
        logic [15:0]               pulse_width;  ///< Ancho del pulso
        logic                      valid;        ///< Datos válidos
    } pha_output_t;

    //=========================================================================
    // Funciones auxiliares
    //=========================================================================
    
    /**
     * @brief Calcula el número de bits necesarios para representar un valor
     * 
     * @param value Valor máximo a representar
     * @return Número de bits necesarios (ceil(log2(value)))
     */
    function automatic int unsigned clog2_safe(input int unsigned value);
        if (value <= 1) return 1;
        else return $clog2(value);
    endfunction
    
    /**
     * @brief Determina si una transición cruza el umbral
     * 
     * @param prev_sample Muestra anterior
     * @param curr_sample Muestra actual  
     * @param threshold   Valor de umbral
     * @param mode        Modo de detección
     * @return 1 si hay cruce de umbral según el modo
     */
    function automatic logic threshold_crossed(
        input logic signed [DSP_DATA_WIDTH-1:0] prev_sample,
        input logic signed [DSP_DATA_WIDTH-1:0] curr_sample,
        input logic signed [DSP_DATA_WIDTH-1:0] threshold,
        input trigger_mode_e mode
    );
        logic rising_edge, falling_edge;
        
        rising_edge  = (prev_sample < threshold) && (curr_sample >= threshold);
        falling_edge = (prev_sample >= threshold) && (curr_sample < threshold);
        
        case (mode)
            TRIG_RISING:  return rising_edge;
            TRIG_FALLING: return falling_edge;
            TRIG_BOTH:    return rising_edge | falling_edge;
            TRIG_LEVEL:   return (curr_sample >= threshold);
            default:      return 1'b0;
        endcase
    endfunction
    
    /**
     * @brief Calcula la longitud de burst AXI4 válida
     * 
     * Dado un número de bytes a transferir, calcula la longitud
     * de burst que no excede los límites de AXI4.
     * 
     * @param bytes_remaining Bytes pendientes de transferir
     * @param max_burst       Longitud máxima de burst (típicamente 256)
     * @return Longitud de burst a utilizar (1-256)
     */
    function automatic logic [7:0] calc_burst_len(
        input logic [31:0] bytes_remaining,
        input logic [7:0]  max_burst
    );
        logic [31:0] beats_needed;
        beats_needed = (bytes_remaining + (AXI_DATA_WIDTH/8) - 1) / (AXI_DATA_WIDTH/8);
        
        if (beats_needed >= max_burst)
            return max_burst - 1;  // AXI AWLEN es longitud - 1
        else
            return beats_needed[7:0] - 1;
    endfunction

endpackage : axi_stream_pkg
