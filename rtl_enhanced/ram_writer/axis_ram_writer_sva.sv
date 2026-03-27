/**
 * @file axis_ram_writer_sva.sv
 * @brief Módulo de assertions SVA para axis_ram_writer
 *
 * Assertions específicas para detectar el bug conocido donde
 * el buffer no escribe toda la salida deseada.
 *
 * @par Hipótesis de bug verificadas:
 * - H1: TLAST no dispara flush del FIFO
 * - H2: Último burst incompleto no se escribe
 * - H3: Límite de 4KB causa pérdida de datos
 * - H4: Backpressure AXI4 causa deadlock
 *
 * @par Uso:
 * @code
 *   bind axis_ram_writer axis_ram_writer_sva sva_inst (.*);
 * @endcode
 */

`ifndef AXIS_RAM_WRITER_SVA_SV
`define AXIS_RAM_WRITER_SVA_SV

module axis_ram_writer_sva #(
    parameter int AXIS_DATA_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int FIFO_DEPTH = 512
) (
    // Señales del DUT
    input logic                       aclk,
    input logic                       aresetn,
    
    // Configuración
    input logic                       cfg_enable,
    input logic [AXI_ADDR_WIDTH-1:0]  cfg_base_addr,
    input logic [AXI_ADDR_WIDTH-1:0]  cfg_buffer_size,
    
    // Status
    input logic                       sts_busy,
    input logic                       sts_error,
    input logic [31:0]                sts_bytes_written,
    
    // AXI-Stream Slave
    input logic [AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input logic                       s_axis_tvalid,
    input logic                       s_axis_tready,
    input logic                       s_axis_tlast,
    
    // AXI4 Master - Write Address Channel
    input logic [AXI_ADDR_WIDTH-1:0]  m_axi_awaddr,
    input logic [7:0]                 m_axi_awlen,
    input logic [2:0]                 m_axi_awsize,
    input logic [1:0]                 m_axi_awburst,
    input logic                       m_axi_awvalid,
    input logic                       m_axi_awready,
    
    // AXI4 Master - Write Data Channel
    input logic [AXI_DATA_WIDTH-1:0]  m_axi_wdata,
    input logic [AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
    input logic                       m_axi_wlast,
    input logic                       m_axi_wvalid,
    input logic                       m_axi_wready,
    
    // AXI4 Master - Write Response Channel
    input logic [1:0]                 m_axi_bresp,
    input logic                       m_axi_bvalid,
    input logic                       m_axi_bready
);

    //=========================================================================
    // Variables de monitoreo para debugging
    //=========================================================================
    
    // Contadores
    int axis_beat_count;        // Beats recibidos por AXI-Stream
    int axi_beat_count;         // Beats enviados por AXI4
    int axi_txn_count;          // Transacciones AXI4 completas
    int tlast_count;            // Número de TLAST recibidos
    int pending_data;           // Datos en FIFO esperando escribirse
    
    // Para verificación de TLAST
    logic tlast_seen;
    int beats_after_tlast;
    
    // Para verificación de 4KB
    logic [AXI_ADDR_WIDTH-1:0] burst_end_addr;
    
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            axis_beat_count <= 0;
            axi_beat_count <= 0;
            axi_txn_count <= 0;
            tlast_count <= 0;
            tlast_seen <= 0;
            beats_after_tlast <= 0;
        end else begin
            // Contar beats AXI-Stream
            if (s_axis_tvalid && s_axis_tready) begin
                axis_beat_count <= axis_beat_count + 1;
                pending_data <= pending_data + 1;
                
                if (s_axis_tlast) begin
                    tlast_count <= tlast_count + 1;
                    tlast_seen <= 1;
                end
            end
            
            // Contar beats AXI4
            if (m_axi_wvalid && m_axi_wready) begin
                axi_beat_count <= axi_beat_count + 1;
                pending_data <= pending_data - 1;
                
                if (tlast_seen)
                    beats_after_tlast <= beats_after_tlast + 1;
                
                if (m_axi_wlast)
                    axi_txn_count <= axi_txn_count + 1;
            end
        end
    end

    //=========================================================================
    // ASSERTIONS: Protocolo AXI4 (críticas)
    //=========================================================================
    
    /**
     * @brief AWVALID no puede caer sin AWREADY
     */
    property p_awvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axi_awvalid && !m_axi_awready) |=> m_axi_awvalid;
    endproperty
    assert property (p_awvalid_stable)
        else $error("SVA: AWVALID dropped before AWREADY");
    
    /**
     * @brief AWADDR estable mientras AWVALID sin AWREADY
     */
    property p_awaddr_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axi_awvalid && !m_axi_awready) |=> $stable(m_axi_awaddr);
    endproperty
    assert property (p_awaddr_stable)
        else $error("SVA: AWADDR changed without handshake");
    
    /**
     * @brief AWLEN estable
     */
    property p_awlen_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axi_awvalid && !m_axi_awready) |=> $stable(m_axi_awlen);
    endproperty
    assert property (p_awlen_stable)
        else $error("SVA: AWLEN changed without handshake");
    
    /**
     * @brief WVALID no puede caer sin WREADY
     */
    property p_wvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axi_wvalid && !m_axi_wready) |=> m_axi_wvalid;
    endproperty
    assert property (p_wvalid_stable)
        else $error("SVA: WVALID dropped before WREADY");
    
    /**
     * @brief WDATA estable
     */
    property p_wdata_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axi_wvalid && !m_axi_wready) |=> $stable(m_axi_wdata);
    endproperty
    assert property (p_wdata_stable)
        else $error("SVA: WDATA changed without handshake");
    
    /**
     * @brief WLAST estable
     */
    property p_wlast_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axi_wvalid && !m_axi_wready) |=> $stable(m_axi_wlast);
    endproperty
    assert property (p_wlast_stable)
        else $error("SVA: WLAST changed without handshake");

    //=========================================================================
    // ASSERTIONS: Límite de 4KB (H3)
    //=========================================================================
    
    // Calcular dirección final del burst
    assign burst_end_addr = m_axi_awaddr + ((m_axi_awlen + 1) << m_axi_awsize);
    
    /**
     * @brief El burst no debe cruzar el límite de 4KB
     */
    property p_4kb_boundary;
        @(posedge aclk) disable iff (!aresetn)
        (m_axi_awvalid && m_axi_awready) |->
            (m_axi_awaddr[11:0] + ((m_axi_awlen + 1) << m_axi_awsize) <= 13'h1000);
    endproperty
    assert property (p_4kb_boundary)
        else $error("SVA: AXI4 burst crosses 4KB boundary! addr=0x%08X, len=%0d",
                    m_axi_awaddr, m_axi_awlen);

    //=========================================================================
    // ASSERTIONS: Flush después de TLAST (H1)
    //=========================================================================
    
    /**
     * @brief Después de TLAST, todos los datos pendientes deben escribirse
     *
     * Esta es una verificación de comportamiento: después de recibir TLAST,
     * el módulo debe vaciar su FIFO eventualmente.
     */
    property p_tlast_causes_flush;
        @(posedge aclk) disable iff (!aresetn)
        (s_axis_tvalid && s_axis_tready && s_axis_tlast) |->
            ##[1:1000] (pending_data == 0 || sts_error);
    endproperty
    assert property (p_tlast_causes_flush)
        else $warning("SVA: H1 - Data not flushed after TLAST (pending=%0d)", pending_data);

    //=========================================================================
    // ASSERTIONS: Último burst incompleto (H2)
    //=========================================================================
    
    /**
     * @brief El número de beats WLAST debe coincidir con el número de transacciones
     */
    sequence s_aw_handshake;
        m_axi_awvalid && m_axi_awready;
    endsequence
    
    sequence s_wlast_handshake;
        m_axi_wvalid && m_axi_wready && m_axi_wlast;
    endsequence
    
    // Contador de transacciones pendientes (AW sin WLAST correspondiente)
    int aw_pending;
    
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            aw_pending <= 0;
        else begin
            if ((m_axi_awvalid && m_axi_awready) && !(m_axi_wvalid && m_axi_wready && m_axi_wlast))
                aw_pending <= aw_pending + 1;
            else if (!(m_axi_awvalid && m_axi_awready) && (m_axi_wvalid && m_axi_wready && m_axi_wlast))
                aw_pending <= aw_pending - 1;
        end
    end
    
    /**
     * @brief AW pending nunca debe ser negativo
     */
    property p_aw_pending_positive;
        @(posedge aclk) disable iff (!aresetn)
        aw_pending >= 0;
    endproperty
    assert property (p_aw_pending_positive)
        else $error("SVA: More WLAST than AW transactions");

    //=========================================================================
    // ASSERTIONS: Backpressure y deadlock (H4)
    //=========================================================================
    
    /**
     * @brief No debe haber deadlock: si hay datos pendientes, debe haber progreso
     */
    property p_no_deadlock;
        @(posedge aclk) disable iff (!aresetn || !cfg_enable)
        (pending_data > 0 && !sts_error) |->
            ##[1:1000] (m_axi_wvalid || pending_data == 0);
    endproperty
    assert property (p_no_deadlock)
        else $error("SVA: H4 - Potential deadlock, no write activity with pending data");
    
    /**
     * @brief El módulo debe aceptar datos cuando no está lleno
     */
    property p_tready_when_not_full;
        @(posedge aclk) disable iff (!aresetn || !cfg_enable)
        (pending_data < FIFO_DEPTH - 10) |-> s_axis_tready;
    endproperty
    // Comentado porque el DUT puede tener otras razones para no estar ready
    // assert property (p_tready_when_not_full);

    //=========================================================================
    // ASSERTIONS: Integridad de bytes escritos
    //=========================================================================
    
    /**
     * @brief sts_bytes_written debe incrementar correctamente
     */
    property p_bytes_written_increments;
        @(posedge aclk) disable iff (!aresetn)
        (m_axi_wvalid && m_axi_wready) |=>
            (sts_bytes_written > $past(sts_bytes_written)) || sts_error;
    endproperty
    // assert property (p_bytes_written_increments);
    
    //=========================================================================
    // COVERGROUPS
    //=========================================================================
    
    covergroup cg_ram_writer @(posedge aclk);
        option.per_instance = 1;
        
        // Longitud de burst
        cp_burst_len: coverpoint m_axi_awlen iff (m_axi_awvalid && m_axi_awready) {
            bins single    = {0};
            bins small     = {[1:15]};
            bins medium    = {[16:63]};
            bins large     = {[64:127]};
            bins very_large = {[128:254]};
            bins max       = {255};
        }
        
        // TLAST recibido
        cp_tlast: coverpoint s_axis_tlast iff (s_axis_tvalid && s_axis_tready) {
            bins no_tlast = {0};
            bins tlast    = {1};
        }
        
        // Respuesta de escritura
        cp_bresp: coverpoint m_axi_bresp iff (m_axi_bvalid) {
            bins okay   = {2'b00};
            bins exokay = {2'b01};
            bins slverr = {2'b10};
            bins decerr = {2'b11};
        }
        
        // Estado del sistema
        cp_busy: coverpoint sts_busy;
        cp_error: coverpoint sts_error;
        
        // Backpressure en entrada
        cp_input_bp: coverpoint (!s_axis_tready && s_axis_tvalid);
        
        // Backpressure en salida (AW)
        cp_aw_bp: coverpoint (!m_axi_awready && m_axi_awvalid);
        
        // Backpressure en salida (W)
        cp_w_bp: coverpoint (!m_axi_wready && m_axi_wvalid);
        
        // Cross coverage
        cx_tlast_bp: cross cp_tlast, cp_input_bp;
        cx_burst_bp: cross cp_burst_len, cp_w_bp;
        
    endgroup
    
    cg_ram_writer cg_rw_inst = new();
    
    /**
     * @brief Coverage de escenarios de bug
     */
    covergroup cg_bug_scenarios @(posedge aclk);
        option.per_instance = 1;
        
        // H1: TLAST con datos pendientes
        cp_h1: coverpoint (s_axis_tlast && s_axis_tvalid && pending_data > 0) {
            bins scenario = {1};
        }
        
        // H2: Burst parcial (menos de 256)
        cp_h2: coverpoint m_axi_awlen iff (m_axi_awvalid && m_axi_awready) {
            bins partial = {[1:254]};
            bins full    = {255};
        }
        
        // H3: Cerca del límite de 4KB
        cp_h3: coverpoint m_axi_awaddr[11:0] iff (m_axi_awvalid && m_axi_awready) {
            bins safe      = {[0:12'hE00]};
            bins near_4kb  = {[12'hE01:12'hFFF]};
        }
        
        // H4: Backpressure concurrente
        cp_h4: coverpoint ({!s_axis_tready, !m_axi_wready, !m_axi_awready}) {
            bins no_bp     = {3'b000};
            bins input_bp  = {3'b100};
            bins w_bp      = {3'b010};
            bins aw_bp     = {3'b001};
            bins multi_bp  = {[3'b011:3'b111]};
        }
        
    endgroup
    
    cg_bug_scenarios cg_bugs_inst = new();

    //=========================================================================
    // Información y diagnóstico
    //=========================================================================
    
    initial begin
        $display("[SVA] axis_ram_writer_sva bound to instance");
        $display("[SVA]   Monitoring for known bugs (H1-H4)");
    end
    
    // Reporte periódico de estado
    always @(posedge aclk) begin
        if (aresetn && (axis_beat_count % 1000 == 0) && axis_beat_count > 0) begin
            $display("[SVA-MON] @%0t: AXIS=%0d, AXI4=%0d, pending=%0d, txns=%0d",
                     $time, axis_beat_count, axi_beat_count, pending_data, axi_txn_count);
        end
    end
    
    // Reporte final
    final begin
        $display("[SVA] axis_ram_writer final statistics:");
        $display("[SVA]   AXIS beats received: %0d", axis_beat_count);
        $display("[SVA]   AXI4 beats sent:     %0d", axi_beat_count);
        $display("[SVA]   AXI4 transactions:   %0d", axi_txn_count);
        $display("[SVA]   TLAST received:      %0d", tlast_count);
        $display("[SVA]   Data pending:        %0d", pending_data);
        if (pending_data > 0)
            $warning("[SVA] H1/H2 BUG CONFIRMED: %0d beats not written!", pending_data);
        $display("[SVA] Coverage:");
        $display("[SVA]   RAM Writer: %.1f%%", cg_rw_inst.get_coverage());
        $display("[SVA]   Bug scenarios: %.1f%%", cg_bugs_inst.get_coverage());
    end

endmodule : axis_ram_writer_sva

`endif // AXIS_RAM_WRITER_SVA_SV
