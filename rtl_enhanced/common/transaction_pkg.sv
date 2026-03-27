/**
 * @file transaction_pkg.sv
 * @brief Package de transacciones para simulación mixta ESL+RTL
 *
 * Define las estructuras de transacciones que permiten comunicación
 * entre el modelo ESL (Python/SystemC) y el testbench RTL.
 * Estas transacciones son el "idioma común" del testbench híbrido.
 *
 * @par Arquitectura:
 * @code
 *   ESL Model ──► Transaction ──► Adapter ──► RTL Signals
 *                     │
 *                     └──► Checker (comparación)
 * @endcode
 */

`ifndef TRANSACTION_PKG_SV
`define TRANSACTION_PKG_SV

package transaction_pkg;

    //=========================================================================
    // Parámetros globales
    //=========================================================================
    
    /** @brief Ancho de datos del sistema */
    localparam int DATA_WIDTH = 16;
    
    /** @brief Ancho de dirección AXI4 */
    localparam int ADDR_WIDTH = 32;
    
    /** @brief Ancho de datos AXI4 */
    localparam int AXI_DATA_WIDTH = 64;

    //=========================================================================
    // Enumeraciones de transacciones
    //=========================================================================
    
    /**
     * @brief Tipo de transacción AXI-Stream
     */
    typedef enum logic [2:0] {
        AXIS_TXN_DATA,      ///< Dato normal
        AXIS_TXN_LAST,      ///< Último dato del paquete (TLAST)
        AXIS_TXN_IDLE,      ///< Sin transacción (gap)
        AXIS_TXN_BACKPRESSURE ///< Simular backpressure
    } axis_txn_type_e;
    
    /**
     * @brief Tipo de transacción AXI4 (memoria)
     */
    typedef enum logic [2:0] {
        AXI4_TXN_WRITE,     ///< Escritura a memoria
        AXI4_TXN_READ,      ///< Lectura de memoria
        AXI4_TXN_RESP       ///< Respuesta
    } axi4_txn_type_e;
    
    /**
     * @brief Resultado de comparación
     */
    typedef enum logic [1:0] {
        CMP_MATCH,          ///< Datos coinciden
        CMP_MISMATCH,       ///< Datos no coinciden
        CMP_TIMEOUT,        ///< Timeout esperando dato
        CMP_PROTOCOL_ERROR  ///< Error de protocolo
    } compare_result_e;

    //=========================================================================
    // Estructuras de transacciones
    //=========================================================================
    
    /**
     * @brief Transacción AXI-Stream genérica
     *
     * Representa una transferencia en el bus AXI-Stream.
     * Usada tanto para entrada como salida del DUT.
     */
    typedef struct packed {
        logic [DATA_WIDTH-1:0] data;      ///< Dato
        logic                  last;      ///< Fin de paquete
        logic                  valid;     ///< Transacción válida
        axis_txn_type_e        txn_type;  ///< Tipo de transacción
        logic [31:0]           timestamp; ///< Ciclo de reloj
        logic [31:0]           seq_num;   ///< Número de secuencia
    } axis_transaction_t;
    
    /**
     * @brief Transacción de trigger
     *
     * Representa un evento de trigger detectado.
     */
    typedef struct packed {
        logic [31:0]           sample_index;  ///< Índice de la muestra
        logic [DATA_WIDTH-1:0] sample_value;  ///< Valor que causó el trigger
        logic [DATA_WIDTH-1:0] prev_value;    ///< Valor anterior
        logic [DATA_WIDTH-1:0] threshold;     ///< Umbral configurado
        logic [2:0]            mode;          ///< Modo de trigger
        logic [31:0]           timestamp;     ///< Ciclo de reloj
    } trigger_transaction_t;
    
    /**
     * @brief Transacción de configuración
     *
     * Representa una escritura a registro de configuración.
     */
    typedef struct packed {
        logic [ADDR_WIDTH-1:0] addr;      ///< Dirección del registro
        logic [31:0]           data;      ///< Valor a escribir
        logic                  is_read;   ///< 1=lectura, 0=escritura
        logic [31:0]           timestamp; ///< Ciclo de reloj
    } config_transaction_t;
    
    /**
     * @brief Transacción AXI4 (memoria)
     *
     * Representa un burst de escritura/lectura a memoria.
     */
    typedef struct packed {
        axi4_txn_type_e        txn_type;  ///< Tipo de transacción
        logic [ADDR_WIDTH-1:0] addr;      ///< Dirección base
        logic [7:0]            len;       ///< Longitud del burst (AWLEN)
        logic [2:0]            size;      ///< Tamaño de transferencia
        logic [AXI_DATA_WIDTH-1:0] data [256]; ///< Datos del burst
        logic [1:0]            resp;      ///< Respuesta (BRESP)
        logic [31:0]           timestamp; ///< Ciclo de reloj
    } axi4_transaction_t;
    
    /**
     * @brief Resultado de verificación
     *
     * Estructura retornada por los checkers.
     */
    typedef struct packed {
        compare_result_e       result;    ///< Resultado de comparación
        logic [31:0]           expected;  ///< Valor esperado
        logic [31:0]           actual;    ///< Valor actual
        logic [31:0]           index;     ///< Índice donde ocurrió
        logic [31:0]           timestamp; ///< Ciclo de reloj
        string                 message;   ///< Mensaje descriptivo
    } verify_result_t;

    //=========================================================================
    // Funciones de utilidad para transacciones
    //=========================================================================
    
    /**
     * @brief Crea una transacción AXI-Stream de datos
     */
    function automatic axis_transaction_t create_axis_data(
        input logic [DATA_WIDTH-1:0] data,
        input logic [31:0] timestamp = 0,
        input logic [31:0] seq_num = 0
    );
        axis_transaction_t txn;
        txn.data = data;
        txn.last = 1'b0;
        txn.valid = 1'b1;
        txn.txn_type = AXIS_TXN_DATA;
        txn.timestamp = timestamp;
        txn.seq_num = seq_num;
        return txn;
    endfunction
    
    /**
     * @brief Crea una transacción AXI-Stream con TLAST
     */
    function automatic axis_transaction_t create_axis_last(
        input logic [DATA_WIDTH-1:0] data,
        input logic [31:0] timestamp = 0,
        input logic [31:0] seq_num = 0
    );
        axis_transaction_t txn;
        txn.data = data;
        txn.last = 1'b1;
        txn.valid = 1'b1;
        txn.txn_type = AXIS_TXN_LAST;
        txn.timestamp = timestamp;
        txn.seq_num = seq_num;
        return txn;
    endfunction
    
    /**
     * @brief Convierte transacción a string para debug
     */
    function automatic string axis_txn_to_string(axis_transaction_t txn);
        return $sformatf("AXIS[%0d]: data=0x%04X, last=%b, type=%s",
                        txn.seq_num, txn.data, txn.last, txn.txn_type.name());
    endfunction
    
    /**
     * @brief Convierte transacción de trigger a string
     */
    function automatic string trigger_txn_to_string(trigger_transaction_t txn);
        return $sformatf("TRIG[@%0d]: value=%0d, prev=%0d, thresh=%0d",
                        txn.sample_index, txn.sample_value, 
                        txn.prev_value, txn.threshold);
    endfunction

endpackage : transaction_pkg

`endif // TRANSACTION_PKG_SV
