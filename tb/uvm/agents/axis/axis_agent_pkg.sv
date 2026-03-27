/**
 * @file axis_agent_pkg.sv
 * @brief Package del agent AXI-Stream para UVM
 *
 * Agrupa todos los componentes del agent AXI-Stream en un package
 * para facilitar la importación.
 */

package axis_agent_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    //=========================================================================
    // Includes
    //=========================================================================
    
    `include "axis_seq_item.sv"
    `include "axis_driver.sv"
    `include "axis_monitor.sv"
    `include "axis_agent.sv"
    `include "axis_sequences.sv"

endpackage : axis_agent_pkg
