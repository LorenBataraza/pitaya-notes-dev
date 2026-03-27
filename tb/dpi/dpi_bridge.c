/**
 * @file dpi_bridge.c
 * @brief Implementación C del bridge DPI
 *
 * Implementa las funciones exportadas desde SystemVerilog y
 * proporciona infraestructura para callbacks hacia SystemC o Python.
 *
 * @par Compilación:
 * @code
 *   gcc -c -fPIC dpi_bridge.c -I$QUESTA_HOME/include
 *   gcc -shared -o dpi_bridge.so dpi_bridge.o
 * @endcode
 */

#include "dpi_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

//=============================================================================
// Variables globales
//=============================================================================

static axis_callback_t g_axis_callback = NULL;
static trigger_callback_t g_trigger_callback = NULL;
static int g_transaction_count = 0;
static int g_error_count = 0;
static int g_simulation_done = 0;

/** @brief Buffer para almacenar transacciones recibidas */
#define MAX_TRANSACTIONS 100000
static axis_transaction_t g_transaction_buffer[MAX_TRANSACTIONS];

/** @brief Buffer para eventos de trigger */
#define MAX_TRIGGER_EVENTS 10000
static trigger_event_t g_trigger_buffer[MAX_TRIGGER_EVENTS];
static int g_trigger_count = 0;

//=============================================================================
// Funciones exportadas (llamadas desde SystemVerilog)
//=============================================================================

void dpi_notify_axis_response(int data, int last, int timestamp)
{
    axis_transaction_t txn;
    
    txn.data = data;
    txn.last = last;
    txn.timestamp = timestamp;
    txn.seq_num = g_transaction_count;
    
    /* Almacenar en buffer */
    if (g_transaction_count < MAX_TRANSACTIONS) {
        g_transaction_buffer[g_transaction_count] = txn;
    }
    g_transaction_count++;
    
    /* Llamar callback si está registrado */
    if (g_axis_callback != NULL) {
        g_axis_callback(&txn);
    }
    
    #ifdef DPI_DEBUG
    printf("[DPI-C] AXIS Response: data=0x%04X, last=%d, @%d\n",
           data & 0xFFFF, last, timestamp);
    #endif
}

void dpi_notify_trigger_event(int sample_index, int sample_value, int threshold)
{
    trigger_event_t event;
    
    event.sample_index = sample_index;
    event.sample_value = sample_value;
    event.threshold = threshold;
    
    /* Almacenar en buffer */
    if (g_trigger_count < MAX_TRIGGER_EVENTS) {
        g_trigger_buffer[g_trigger_count] = event;
    }
    g_trigger_count++;
    
    /* Llamar callback si está registrado */
    if (g_trigger_callback != NULL) {
        g_trigger_callback(&event);
    }
    
    #ifdef DPI_DEBUG
    printf("[DPI-C] Trigger: index=%d, value=%d, threshold=%d\n",
           sample_index, sample_value, threshold);
    #endif
}

void dpi_notify_error(int error_code, const char* message)
{
    g_error_count++;
    fprintf(stderr, "[DPI-C] ERROR %d: %s\n", error_code, message);
}

void dpi_notify_sim_done(int pass, int num_errors)
{
    g_simulation_done = 1;
    printf("[DPI-C] Simulation complete: %s (%d errors)\n",
           pass ? "PASS" : "FAIL", num_errors);
}

//=============================================================================
// Funciones de inicialización y control
//=============================================================================

int dpi_bridge_init(axis_callback_t axis_cb, trigger_callback_t trig_cb)
{
    g_axis_callback = axis_cb;
    g_trigger_callback = trig_cb;
    g_transaction_count = 0;
    g_trigger_count = 0;
    g_error_count = 0;
    g_simulation_done = 0;
    
    printf("[DPI-C] Bridge initialized\n");
    return 0;
}

void dpi_bridge_cleanup(void)
{
    g_axis_callback = NULL;
    g_trigger_callback = NULL;
    printf("[DPI-C] Bridge cleanup complete\n");
}

int dpi_get_transaction_count(void)
{
    return g_transaction_count;
}

int dpi_get_error_count(void)
{
    return g_error_count;
}

//=============================================================================
// Funciones auxiliares para acceso a buffers
//=============================================================================

/**
 * @brief Obtiene una transacción del buffer por índice
 */
int dpi_get_transaction(int index, axis_transaction_t* txn)
{
    if (index < 0 || index >= g_transaction_count || index >= MAX_TRANSACTIONS) {
        return -1;
    }
    
    *txn = g_transaction_buffer[index];
    return 0;
}

/**
 * @brief Obtiene un evento de trigger por índice
 */
int dpi_get_trigger_event(int index, trigger_event_t* event)
{
    if (index < 0 || index >= g_trigger_count || index >= MAX_TRIGGER_EVENTS) {
        return -1;
    }
    
    *event = g_trigger_buffer[index];
    return 0;
}

/**
 * @brief Retorna el número de eventos de trigger
 */
int dpi_get_trigger_count(void)
{
    return g_trigger_count;
}

/**
 * @brief Verifica si la simulación terminó
 */
int dpi_is_simulation_done(void)
{
    return g_simulation_done;
}

/**
 * @brief Compara transacciones con array de esperados
 *
 * @param expected  Array de datos esperados
 * @param count     Número de elementos
 * @return Número de mismatches
 */
int dpi_compare_transactions(const int* expected, int count)
{
    int mismatches = 0;
    int i;
    
    for (i = 0; i < count && i < g_transaction_count; i++) {
        if (g_transaction_buffer[i].data != expected[i]) {
            mismatches++;
            #ifdef DPI_DEBUG
            printf("[DPI-C] Mismatch at %d: expected=0x%04X, actual=0x%04X\n",
                   i, expected[i] & 0xFFFF, g_transaction_buffer[i].data & 0xFFFF);
            #endif
        }
    }
    
    /* Verificar si faltan transacciones */
    if (count > g_transaction_count) {
        mismatches += (count - g_transaction_count);
    }
    
    return mismatches;
}
