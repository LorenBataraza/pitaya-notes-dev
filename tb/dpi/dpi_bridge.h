/**
 * @file dpi_bridge.h
 * @brief Header C para interfaz DPI con SystemVerilog
 *
 * Define las funciones de interfaz entre código C/C++ (incluyendo SystemC)
 * y el testbench SystemVerilog.
 *
 * @par Compilación:
 * @code
 *   gcc -c -fPIC dpi_bridge.c -I$QUESTA_HOME/include
 *   gcc -shared -o dpi_bridge.so dpi_bridge.o
 * @endcode
 *
 * @par Uso con QuestaSim:
 * @code
 *   vsim -sv_lib dpi_bridge tb_top
 * @endcode
 */

#ifndef DPI_BRIDGE_H
#define DPI_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

//=============================================================================
// Tipos de datos
//=============================================================================

/**
 * @brief Transacción AXI-Stream
 */
typedef struct {
    int32_t data;       ///< Dato (16 bits útiles)
    int32_t last;       ///< Flag TLAST
    int32_t timestamp;  ///< Ciclo de reloj
    int32_t seq_num;    ///< Número de secuencia
} axis_transaction_t;

/**
 * @brief Evento de trigger
 */
typedef struct {
    int32_t sample_index;
    int32_t sample_value;
    int32_t threshold;
} trigger_event_t;

/**
 * @brief Callback para transacciones recibidas
 */
typedef void (*axis_callback_t)(const axis_transaction_t* txn);

/**
 * @brief Callback para eventos de trigger
 */
typedef void (*trigger_callback_t)(const trigger_event_t* event);

//=============================================================================
// Funciones exportadas (SV → C)
// Estas son llamadas por SystemVerilog para notificar eventos
//=============================================================================

/**
 * @brief Notificación de transacción AXI-Stream capturada
 *
 * Llamada por el monitor SV cuando captura una transacción.
 */
void dpi_notify_axis_response(int data, int last, int timestamp);

/**
 * @brief Notificación de evento de trigger
 */
void dpi_notify_trigger_event(int sample_index, int sample_value, int threshold);

/**
 * @brief Notificación de error
 */
void dpi_notify_error(int error_code, const char* message);

/**
 * @brief Notificación de fin de simulación
 */
void dpi_notify_sim_done(int pass, int num_errors);

//=============================================================================
// Funciones importadas (C → SV)
// Estas son implementadas en SystemVerilog y llamadas desde C
//=============================================================================

/**
 * @brief Envía una transacción AXI-Stream al DUT
 */
extern int dpi_send_axis_transaction(int data, int last);

/**
 * @brief Envía un burst de datos
 */
extern int dpi_send_axis_burst(const int* data_array, int length, int mark_last);

/**
 * @brief Escribe registro de configuración
 */
extern int dpi_write_config(int addr, int data);

/**
 * @brief Lee registro de status
 */
extern int dpi_read_status(int addr);

/**
 * @brief Avanza la simulación N ciclos
 */
extern void dpi_advance_clock(int cycles);

/**
 * @brief Espera condición con timeout
 */
extern int dpi_wait_condition(int condition_id, int timeout);

//=============================================================================
// Funciones de inicialización y control
//=============================================================================

/**
 * @brief Inicializa el bridge DPI
 *
 * @param axis_cb   Callback para transacciones AXI-Stream
 * @param trig_cb   Callback para eventos de trigger
 * @return 0=éxito, -1=error
 */
int dpi_bridge_init(axis_callback_t axis_cb, trigger_callback_t trig_cb);

/**
 * @brief Libera recursos del bridge
 */
void dpi_bridge_cleanup(void);

/**
 * @brief Retorna el número de transacciones recibidas
 */
int dpi_get_transaction_count(void);

/**
 * @brief Retorna el número de errores detectados
 */
int dpi_get_error_count(void);

#ifdef __cplusplus
}
#endif

#endif // DPI_BRIDGE_H
