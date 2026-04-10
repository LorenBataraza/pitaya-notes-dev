/**
 * @file axi4_write_simple_if.sv
 * @brief Interface AXI4 Write-Only Simplificada
 *
 * Version minimalista sin clocking blocks para testbenches
 * de integracion donde no se necesita UVM completo.
 * Evita conflictos de "multiply driven" con simuladores antiguos.
 */

`timescale 1ns/1ps

interface axi4_write_simple_if #(
    parameter int AXI_DATA_W = 64,
    parameter int AXI_ADDR_W = 32,
    parameter int AXI_ID_W   = 4
)(
    input logic aclk,
    input logic aresetn
);

    //=========================================================================
    // AW Channel (Address Write)
    //=========================================================================
    
    logic [AXI_ID_W-1:0]   awid;
    logic [AXI_ADDR_W-1:0] awaddr;
    logic [7:0]            awlen;
    logic [2:0]            awsize;
    logic [1:0]            awburst;
    logic                  awvalid;
    logic                  awready;

    //=========================================================================
    // W Channel (Write Data)
    //=========================================================================
    
    logic [AXI_DATA_W-1:0]   wdata;
    logic [AXI_DATA_W/8-1:0] wstrb;
    logic                    wlast;
    logic                    wvalid;
    logic                    wready;

    //=========================================================================
    // B Channel (Write Response)
    //=========================================================================
    
    logic [AXI_ID_W-1:0] bid;
    logic [1:0]          bresp;
    logic                bvalid;
    logic                bready;

    //=========================================================================
    // Modports
    //=========================================================================
    
    /// Modport para el master (DUT - RAM Writer)
    modport master (
        output awid, awaddr, awlen, awsize, awburst, awvalid,
        input  awready,
        output wdata, wstrb, wlast, wvalid,
        input  wready,
        input  bid, bresp, bvalid,
        output bready
    );
    
    /// Modport para el slave (testbench - memoria simulada)
    modport slave (
        input  awid, awaddr, awlen, awsize, awburst, awvalid,
        output awready,
        input  wdata, wstrb, wlast, wvalid,
        output wready,
        output bid, bresp, bvalid,
        input  bready
    );

endinterface : axi4_write_simple_if
