/**
 * @file axi4_write_pkg.sv
 * @brief Package UVM para el agent AXI4 Write
 *
 * Agrupa todos los componentes necesarios para verificar
 * transacciones AXI4 de escritura.
 *
 * @par Uso:
 * @code
 *   import axi4_write_pkg::*;
 *   
 *   // Instanciar interface
 *   axi4_write_if axi_if(clk, rst_n);
 *   
 *   // Conectar DUT
 *   assign axi_if.awaddr = dut.m_axi_awaddr;
 *   // ...
 *   
 *   // Configurar en test
 *   uvm_config_db#(virtual axi4_write_if)::set(null, "*", "vif", axi_if);
 * @endcode
 */

package axi4_write_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    //=========================================================================
    // Tipos y Constantes
    //=========================================================================
    
    /// Respuestas AXI4
    typedef enum bit [1:0] {
        AXI_RESP_OKAY   = 2'b00,
        AXI_RESP_EXOKAY = 2'b01,
        AXI_RESP_SLVERR = 2'b10,
        AXI_RESP_DECERR = 2'b11
    } axi_resp_e;
    
    /// Tipos de burst
    typedef enum bit [1:0] {
        AXI_BURST_FIXED = 2'b00,
        AXI_BURST_INCR  = 2'b01,
        AXI_BURST_WRAP  = 2'b10
    } axi_burst_e;

    //=========================================================================
    // Includes
    //=========================================================================
    
    `include "axi4_write_seq_item.sv"
    `include "axi4_write_monitor.sv"
    `include "axi4_write_memory.sv"
    `include "axi4_write_agent.sv"

endpackage : axi4_write_pkg
