/**
 * @file axi4_write_if.sv
 * @brief Interface AXI4 Write-Only
 *
 * Define las senales del canal de escritura AXI4:
 *   - AW (Address Write): direccion y parametros del burst
 *   - W  (Write Data): datos y strobes
 *   - B  (Write Response): respuesta del slave
 *
 * @note Esta interface solo implementa el write path. Para lectura
 *       se necesitaria agregar los canales AR y R.
 */

`timescale 1ns/1ps

interface axi4_write_if #(
    parameter int AXI_DATA_W = 64,
    parameter int AXI_ADDR_W = 32,
    parameter int AXI_ID_W   = 4
) (
    input logic aclk,
    input logic aresetn
);

    //=========================================================================
    // AW Channel (Address Write)
    //=========================================================================
    
    logic [AXI_ID_W-1:0]   awid;
    logic [AXI_ADDR_W-1:0] awaddr;
    logic [7:0]            awlen;      ///< Burst length - 1 (0=1 beat, 255=256 beats)
    logic [2:0]            awsize;     ///< Bytes per beat = 2^awsize
    logic [1:0]            awburst;    ///< 00=FIXED, 01=INCR, 10=WRAP
    logic                  awvalid;
    logic                  awready;

    //=========================================================================
    // W Channel (Write Data)
    //=========================================================================
    
    logic [AXI_DATA_W-1:0]     wdata;
    logic [(AXI_DATA_W/8)-1:0] wstrb;   ///< Byte strobes
    logic                      wlast;   ///< Last beat of burst
    logic                      wvalid;
    logic                      wready;

    //=========================================================================
    // B Channel (Write Response)
    //=========================================================================
    
    logic [AXI_ID_W-1:0] bid;
    logic [1:0]          bresp;    ///< 00=OKAY, 01=EXOKAY, 10=SLVERR, 11=DECERR
    logic                bvalid;
    logic                bready;

    //=========================================================================
    // Clocking Blocks
    //=========================================================================
    
    /**
     * @brief Clocking block para el master (DUT = RAM Writer)
     */
    clocking master_cb @(posedge aclk);
        default input #1step output #1;
        
        // AW - master drives, slave responds
        output awid, awaddr, awlen, awsize, awburst, awvalid;
        input  awready;
        
        // W - master drives, slave responds
        output wdata, wstrb, wlast, wvalid;
        input  wready;
        
        // B - slave drives, master responds
        input  bid, bresp, bvalid;
        output bready;
    endclocking
    
    /**
     * @brief Clocking block para el slave (Memory Model)
     */
    clocking slave_cb @(posedge aclk);
        default input #1step output #1;
        
        // AW - slave receives
        input  awid, awaddr, awlen, awsize, awburst, awvalid;
        output awready;
        
        // W - slave receives
        input  wdata, wstrb, wlast, wvalid;
        output wready;
        
        // B - slave sends
        output bid, bresp, bvalid;
        input  bready;
    endclocking
    
    /**
     * @brief Clocking block para el monitor (observa sin modificar)
     */
    clocking monitor_cb @(posedge aclk);
        default input #1step;
        
        input awid, awaddr, awlen, awsize, awburst, awvalid, awready;
        input wdata, wstrb, wlast, wvalid, wready;
        input bid, bresp, bvalid, bready;
    endclocking

    //=========================================================================
    // Modports
    //=========================================================================
    
    modport master (
        clocking master_cb,
        input aclk, aresetn
    );
    
    modport slave (
        clocking slave_cb,
        input aclk, aresetn
    );
    
    modport monitor (
        clocking monitor_cb,
        input aclk, aresetn
    );

    //=========================================================================
    // Assertions de Protocolo AXI4
    //=========================================================================
    
    // AWVALID debe mantenerse hasta AWREADY
    property aw_stable;
        @(posedge aclk) disable iff (!aresetn)
        awvalid && !awready |=> $stable(awaddr) && $stable(awlen) && 
                                 $stable(awsize) && $stable(awburst);
    endproperty
    assert property (aw_stable) else
        $error("[AXI4] AW channel signals changed before AWREADY");
    
    // WVALID debe mantenerse hasta WREADY
    property w_stable;
        @(posedge aclk) disable iff (!aresetn)
        wvalid && !wready |=> $stable(wdata) && $stable(wstrb) && $stable(wlast);
    endproperty
    assert property (w_stable) else
        $error("[AXI4] W channel signals changed before WREADY");
    
    // BVALID debe mantenerse hasta BREADY
    property b_stable;
        @(posedge aclk) disable iff (!aresetn)
        bvalid && !bready |=> $stable(bresp) && $stable(bid);
    endproperty
    assert property (b_stable) else
        $error("[AXI4] B channel signals changed before BREADY");
    
    // Burst no debe cruzar frontera de 4KB
    property no_4kb_cross;
        @(posedge aclk) disable iff (!aresetn)
        awvalid && awready |->
            ((awaddr[11:0] + ((awlen + 1) << awsize)) <= 13'h1000) ||
            (awaddr[11:0] == 0);
    endproperty
    assert property (no_4kb_cross) else
        $error("[AXI4] Burst crosses 4KB boundary: addr=0x%08X, len=%0d, size=%0d",
               awaddr, awlen, awsize);

endinterface : axi4_write_if
