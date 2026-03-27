/**
 * @file sva_bindings.sv
 * @brief Archivo de bindings SVA para todos los módulos MCPHA
 *
 * Este archivo conecta los módulos de assertions SVA con los módulos
 * RTL originales usando el patrón 'bind'. Esto permite agregar
 * verificación sin modificar el código fuente original.
 *
 * @par Uso:
 * Incluir este archivo en la compilación del testbench:
 * @code
 *   vlog ... +incdir+rtl_enhanced/common \
 *            rtl_enhanced/trigger/axis_trigger_sva.sv \
 *            rtl_enhanced/scope/axis_scope_sva.sv \
 *            rtl_enhanced/ram_writer/axis_ram_writer_sva.sv \
 *            rtl_enhanced/common/sva_bindings.sv
 * @endcode
 *
 * @par Arquitectura:
 * @code
 *   ┌─────────────────────────────────────────────────────────────┐
 *   │  RTL Original (cores/)                                      │
 *   │  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐     │
 *   │  │ axis_trigger  │ │  axis_scope   │ │axis_ram_writer│     │
 *   │  └───────┬───────┘ └───────┬───────┘ └───────┬───────┘     │
 *   │          │                 │                 │              │
 *   │          │ bind            │ bind            │ bind         │
 *   │          ▼                 ▼                 ▼              │
 *   │  ┌───────────────┐ ┌───────────────┐ ┌───────────────┐     │
 *   │  │ trigger_sva   │ │  scope_sva    │ │ram_writer_sva │     │
 *   │  │ (assertions)  │ │ (assertions)  │ │ (assertions)  │     │
 *   │  └───────────────┘ └───────────────┘ └───────────────┘     │
 *   │                                                             │
 *   │  RTL Enhanced (rtl_enhanced/)                               │
 *   └─────────────────────────────────────────────────────────────┘
 * @endcode
 */

`ifndef SVA_BINDINGS_SV
`define SVA_BINDINGS_SV

//=============================================================================
// Binding para axis_trigger
//=============================================================================

/**
 * @brief Conecta assertions SVA al módulo axis_trigger
 *
 * El bind busca todas las instancias de axis_trigger en el diseño
 * y les conecta el módulo de assertions.
 */
bind axis_trigger axis_trigger_sva #(
    .DATA_WIDTH(DATA_WIDTH),
    .PIPE_STAGES(PIPE_STAGES)
) sva_inst (
    .aclk(aclk),
    .aresetn(aresetn),
    
    // Mapeo de configuración
    // Nota: ajustar según la interfaz real del módulo
    .cfg_enable(config_i.enable),
    .cfg_threshold(config_i.threshold),
    .cfg_mode(config_i.mode),
    
    // AXI-Stream
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    
    // Trigger
    .trigger_out(trigger_out)
);

//=============================================================================
// Binding para axis_scope
//=============================================================================

bind axis_scope axis_scope_sva #(
    .DATA_WIDTH(DATA_WIDTH),
    .BUFFER_DEPTH(BUFFER_DEPTH)
) sva_inst (
    .aclk(aclk),
    .aresetn(aresetn),
    
    // Configuración
    .cfg_enable(config_i.enable),
    .cfg_arm(config_i.arm),
    .cfg_pre_samples(config_i.pre_samples),
    .cfg_post_samples(config_i.post_samples),
    
    // Status
    .sts_state(status_o.state),
    .sts_armed(status_o.armed),
    .sts_triggered(status_o.triggered),
    .sts_done(status_o.done),
    
    // AXI-Stream
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .trigger_i(trigger_i),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast)
);

//=============================================================================
// Binding para axis_ram_writer
//=============================================================================

bind axis_ram_writer axis_ram_writer_sva #(
    .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH)
) sva_inst (
    .aclk(aclk),
    .aresetn(aresetn),
    
    // Configuración
    .cfg_enable(cfg_enable),
    .cfg_base_addr(cfg_base_addr),
    .cfg_buffer_size(cfg_buffer_size),
    
    // Status
    .sts_busy(sts_busy),
    .sts_error(sts_error),
    .sts_bytes_written(sts_bytes_written),
    
    // AXI-Stream
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    
    // AXI4 Master
    .m_axi_awaddr(m_axi_awaddr),
    .m_axi_awlen(m_axi_awlen),
    .m_axi_awsize(m_axi_awsize),
    .m_axi_awburst(m_axi_awburst),
    .m_axi_awvalid(m_axi_awvalid),
    .m_axi_awready(m_axi_awready),
    .m_axi_wdata(m_axi_wdata),
    .m_axi_wstrb(m_axi_wstrb),
    .m_axi_wlast(m_axi_wlast),
    .m_axi_wvalid(m_axi_wvalid),
    .m_axi_wready(m_axi_wready),
    .m_axi_bresp(m_axi_bresp),
    .m_axi_bvalid(m_axi_bvalid),
    .m_axi_bready(m_axi_bready)
);

`endif // SVA_BINDINGS_SV
