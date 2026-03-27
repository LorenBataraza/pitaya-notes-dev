/**
 * @file dpi_bridge.sv
 * @brief Bridge DPI-C para conexión SystemC ↔ SystemVerilog
 *
 * Este módulo implementa la interfaz DPI (Direct Programming Interface)
 * que permite la comunicación entre código C/C++ (SystemC) y SystemVerilog.
 * Es el puente clave para co-simulación TLM+RTL.
 *
 * @par Arquitectura:
 * @code
 *   ┌─────────────────────────────────────────────────────────────┐
 *   │  Testbench TLM (SystemC)                                    │
 *   │         │                                                   │
 *   │         ▼                                                   │
 *   │  ┌─────────────────┐     ┌─────────────────┐               │
 *   │  │   DPI Bridge    │────►│ UVM Driver (SV) │               │
 *   │  │  (C ↔ SV)       │     │ (genera señales)│               │
 *   │  └─────────────────┘     └────────┬────────┘               │
 *   │         ▲                         │                         │
 *   │         │                ┌────────▼────────┐               │
 *   │         │                │  RTL (Verilog)  │               │
 *   │         │                └─────────────────┘               │
 *   │         │                         │                         │
 *   │  ┌──────┴────────┐       ┌────────▼────────┐               │
 *   │  │  DPI Bridge   │◄──────│ UVM Monitor (SV)│               │
 *   │  │  (SV → C)     │       │ (captura señales)│              │
 *   │  └───────────────┘       └─────────────────┘               │
 *   └─────────────────────────────────────────────────────────────┘
 * @endcode
 *
 * @par Funciones DPI exportadas (C → SV):
 * - dpi_send_axis_transaction: Envía transacción AXI-Stream al DUT
 * - dpi_configure_dut: Escribe registro de configuración
 * - dpi_read_status: Lee registro de status
 * - dpi_advance_clock: Avanza N ciclos de reloj
 *
 * @par Funciones DPI importadas (SV → C):
 * - dpi_notify_axis_response: Notifica transacción capturada
 * - dpi_notify_trigger_event: Notifica evento de trigger
 * - dpi_notify_error: Notifica error/assertion
 */

`ifndef DPI_BRIDGE_SV
`define DPI_BRIDGE_SV

//=============================================================================
// Funciones DPI Import (llamadas desde C hacia SV)
//=============================================================================

/**
 * @brief Envía una transacción AXI-Stream al driver
 *
 * @param data  Dato de 16 bits
 * @param last  Flag TLAST (1=fin de paquete)
 * @return 0=éxito, -1=error
 */
import "DPI-C" function int dpi_send_axis_transaction(
    input int data,
    input int last
);

/**
 * @brief Envía múltiples datos en un burst
 *
 * @param data_array  Array de datos
 * @param length      Número de elementos
 * @param mark_last   Marcar último con TLAST
 * @return 0=éxito, -1=error
 */
import "DPI-C" function int dpi_send_axis_burst(
    input int data_array[],
    input int length,
    input int mark_last
);

/**
 * @brief Escribe un registro de configuración
 *
 * @param addr  Dirección del registro
 * @param data  Valor a escribir
 * @return 0=éxito, -1=error
 */
import "DPI-C" function int dpi_write_config(
    input int addr,
    input int data
);

/**
 * @brief Lee un registro de status
 *
 * @param addr  Dirección del registro
 * @return Valor leído o -1 si error
 */
import "DPI-C" function int dpi_read_status(
    input int addr
);

/**
 * @brief Avanza la simulación N ciclos de reloj
 *
 * @param cycles  Número de ciclos
 */
import "DPI-C" function void dpi_advance_clock(
    input int cycles
);

/**
 * @brief Espera a que una condición se cumpla
 *
 * @param condition_id  ID de la condición (definido por el testbench)
 * @param timeout       Timeout en ciclos
 * @return 1=condición cumplida, 0=timeout
 */
import "DPI-C" function int dpi_wait_condition(
    input int condition_id,
    input int timeout
);


//=============================================================================
// Funciones DPI Export (llamadas desde SV hacia C)
//=============================================================================

/**
 * @brief Notifica al lado C que se capturó una transacción
 *
 * @param data      Dato capturado
 * @param last      Flag TLAST
 * @param timestamp Ciclo de reloj
 */
export "DPI-C" function void dpi_notify_axis_response(
    input int data,
    input int last,
    input int timestamp
);

/**
 * @brief Notifica al lado C un evento de trigger
 *
 * @param sample_index  Índice de la muestra
 * @param sample_value  Valor de la muestra
 * @param threshold     Umbral configurado
 */
export "DPI-C" function void dpi_notify_trigger_event(
    input int sample_index,
    input int sample_value,
    input int threshold
);

/**
 * @brief Notifica al lado C un error o violación de assertion
 *
 * @param error_code  Código de error
 * @param message     Mensaje descriptivo (max 256 chars)
 */
export "DPI-C" function void dpi_notify_error(
    input int error_code,
    input string message
);

/**
 * @brief Notifica al lado C que la simulación terminó
 *
 * @param pass       1=pasó, 0=falló
 * @param num_errors Número de errores
 */
export "DPI-C" function void dpi_notify_sim_done(
    input int pass,
    input int num_errors
);


//=============================================================================
// Módulo bridge que conecta las funciones DPI con el testbench
//=============================================================================

module dpi_bridge #(
    parameter int DATA_WIDTH = 16
) (
    input  logic                    aclk,
    input  logic                    aresetn,
    
    // Interfaz hacia el driver
    output logic [DATA_WIDTH-1:0]   drv_data,
    output logic                    drv_valid,
    output logic                    drv_last,
    input  logic                    drv_ready,
    
    // Interfaz desde el monitor
    input  logic [DATA_WIDTH-1:0]   mon_data,
    input  logic                    mon_valid,
    input  logic                    mon_last,
    
    // Interfaz de trigger
    input  logic                    trigger_event,
    input  logic [DATA_WIDTH-1:0]   trigger_sample,
    input  logic [DATA_WIDTH-1:0]   trigger_threshold,
    input  logic [31:0]             sample_index,
    
    // Control
    output logic                    sim_done,
    output int                      error_count
);

    //=========================================================================
    // Variables internas
    //=========================================================================
    
    int cycle_count;
    int pending_cycles;
    bit transaction_pending;
    logic [DATA_WIDTH-1:0] pending_data;
    logic pending_last;
    
    //=========================================================================
    // Contador de ciclos
    //=========================================================================
    
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end
    
    //=========================================================================
    // Implementación de funciones DPI export
    //=========================================================================
    
    function void dpi_notify_axis_response(int data, int last, int timestamp);
        // Esta función es llamada por el monitor cuando captura una transacción
        // Aquí se puede agregar código para notificar a SystemC
        $display("[DPI] AXIS Response: data=0x%04X, last=%0d, @%0d",
                 data, last, timestamp);
    endfunction
    
    function void dpi_notify_trigger_event(int sample_index, int sample_value, int threshold);
        $display("[DPI] Trigger Event: index=%0d, value=%0d, thresh=%0d",
                 sample_index, sample_value, threshold);
    endfunction
    
    function void dpi_notify_error(int error_code, string message);
        $error("[DPI] Error %0d: %s", error_code, message);
        error_count++;
    endfunction
    
    function void dpi_notify_sim_done(int pass, int num_errors);
        sim_done = 1;
        $display("[DPI] Simulation done: %s (%0d errors)",
                 pass ? "PASS" : "FAIL", num_errors);
    endfunction
    
    //=========================================================================
    // Monitor de salida: captura y notifica
    //=========================================================================
    
    always_ff @(posedge aclk) begin
        if (aresetn && mon_valid) begin
            dpi_notify_axis_response(mon_data, mon_last, cycle_count);
        end
    end
    
    //=========================================================================
    // Monitor de trigger
    //=========================================================================
    
    always_ff @(posedge aclk) begin
        if (aresetn && trigger_event) begin
            dpi_notify_trigger_event(sample_index, trigger_sample, trigger_threshold);
        end
    end

endmodule : dpi_bridge

`endif // DPI_BRIDGE_SV
