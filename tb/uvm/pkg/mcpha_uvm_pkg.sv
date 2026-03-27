/**
 * @file mcpha_uvm_pkg.sv
 * @brief Package principal UVM para verificación MCPHA
 *
 * Importa todos los componentes UVM necesarios para verificación.
 */

package mcpha_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    // Import del package del sistema
    import axi_stream_pkg::*;
    
    //=========================================================================
    // Macros para analysis_imp
    //=========================================================================
    
    `uvm_analysis_imp_decl(_input)
    `uvm_analysis_imp_decl(_output)
    `uvm_analysis_imp_decl(_trigger)
    
    //=========================================================================
    // Includes de componentes
    //=========================================================================
    
    // Agent AXI-Stream
    `include "agents/axis/axis_seq_item.sv"
    `include "agents/axis/axis_driver.sv"
    `include "agents/axis/axis_monitor.sv"
    `include "agents/axis/axis_agent.sv"
    `include "agents/axis/axis_sequences.sv"
    
    // Environment y scoreboard
    `include "env/trigger_scoreboard.sv"
    `include "env/trigger_env.sv"
    
    // Tests
    `include "tests/trigger_tests.sv"

endpackage : mcpha_uvm_pkg
