# =============================================================================
# wave_ram_writer.do - Configuración de ondas para tb_axis_ram_writer
# Diseñado para debugging del bug conocido
# =============================================================================

# Cargar setup general
source questa/wave_setup.do

# Limpiar ondas existentes
delete wave *

# -----------------------------------------------------------------------------
# Grupo: Reloj y Reset
# -----------------------------------------------------------------------------
add wave -noupdate -divider "CLOCK & RESET"
add wave -noupdate -format Logic -color Cyan /tb_axis_ram_writer/aclk
add wave -noupdate -format Logic -color Orange /tb_axis_ram_writer/aresetn

# -----------------------------------------------------------------------------
# Grupo: Configuración y Status
# -----------------------------------------------------------------------------
add wave -noupdate -divider "CONFIG & STATUS"
add wave -noupdate -format Logic /tb_axis_ram_writer/cfg_enable
add wave -noupdate -format Literal -radix hexadecimal /tb_axis_ram_writer/cfg_base_addr
add wave -noupdate -format Literal -radix hexadecimal /tb_axis_ram_writer/cfg_buffer_size
add wave -noupdate -divider ""
add wave -noupdate -format Logic -color Yellow /tb_axis_ram_writer/sts_busy
add wave -noupdate -format Logic -color Red /tb_axis_ram_writer/sts_error
add wave -noupdate -format Literal -radix unsigned -color Magenta \
    /tb_axis_ram_writer/sts_bytes_written

# -----------------------------------------------------------------------------
# Grupo: AXI-Stream Slave (Entrada de datos)
# -----------------------------------------------------------------------------
add wave -noupdate -divider "AXI-STREAM INPUT"
add wave -noupdate -format Literal -radix hexadecimal -color Yellow \
    /tb_axis_ram_writer/s_axis_tdata
add wave -noupdate -format Logic -color Green /tb_axis_ram_writer/s_axis_tvalid
add wave -noupdate -format Logic -color Magenta /tb_axis_ram_writer/s_axis_tready
add wave -noupdate -format Logic -color Red -height 20 /tb_axis_ram_writer/s_axis_tlast

# -----------------------------------------------------------------------------
# Grupo: AXI4 Write Address Channel (AW) - CRÍTICO
# -----------------------------------------------------------------------------
add wave -noupdate -divider "AXI4 AW CHANNEL"
add wave -noupdate -format Literal -radix hexadecimal -color Cyan \
    /tb_axis_ram_writer/m_axi_awaddr
add wave -noupdate -format Literal -radix unsigned /tb_axis_ram_writer/m_axi_awlen
add wave -noupdate -format Literal -radix unsigned /tb_axis_ram_writer/m_axi_awsize
add wave -noupdate -format Literal /tb_axis_ram_writer/m_axi_awburst
add wave -noupdate -format Logic -color Green /tb_axis_ram_writer/m_axi_awvalid
add wave -noupdate -format Logic -color Magenta /tb_axis_ram_writer/m_axi_awready

# -----------------------------------------------------------------------------
# Grupo: AXI4 Write Data Channel (W) - CRÍTICO
# -----------------------------------------------------------------------------
add wave -noupdate -divider "AXI4 W CHANNEL"
add wave -noupdate -format Literal -radix hexadecimal -color Yellow \
    /tb_axis_ram_writer/m_axi_wdata
add wave -noupdate -format Literal -radix binary /tb_axis_ram_writer/m_axi_wstrb
add wave -noupdate -format Logic -color Red -height 20 /tb_axis_ram_writer/m_axi_wlast
add wave -noupdate -format Logic -color Green /tb_axis_ram_writer/m_axi_wvalid
add wave -noupdate -format Logic -color Magenta /tb_axis_ram_writer/m_axi_wready

# -----------------------------------------------------------------------------
# Grupo: AXI4 Write Response Channel (B)
# -----------------------------------------------------------------------------
add wave -noupdate -divider "AXI4 B CHANNEL"
add wave -noupdate -format Literal /tb_axis_ram_writer/m_axi_bresp
add wave -noupdate -format Logic -color Green /tb_axis_ram_writer/m_axi_bvalid
add wave -noupdate -format Logic -color Magenta /tb_axis_ram_writer/m_axi_bready

# -----------------------------------------------------------------------------
# Grupo: Internos del DUT - FSM y contadores (para debugging)
# -----------------------------------------------------------------------------
add wave -noupdate -divider "DUT FSM STATE"
add wave -noupdate -format Literal -color Orange /tb_axis_ram_writer/dut/state

add wave -noupdate -divider "DUT COUNTERS"
add wave -noupdate -format Literal -radix unsigned /tb_axis_ram_writer/dut/beat_count
add wave -noupdate -format Literal -radix unsigned /tb_axis_ram_writer/dut/burst_len
add wave -noupdate -format Literal -radix hexadecimal /tb_axis_ram_writer/dut/current_addr

add wave -noupdate -divider "DUT FIFO"
add wave -noupdate -format Literal -radix unsigned /tb_axis_ram_writer/dut/fifo_count
add wave -noupdate -format Logic /tb_axis_ram_writer/dut/fifo_empty
add wave -noupdate -format Logic /tb_axis_ram_writer/dut/fifo_full
add wave -noupdate -format Logic /tb_axis_ram_writer/dut/fifo_rd_en
add wave -noupdate -format Logic /tb_axis_ram_writer/dut/fifo_wr_en
add wave -noupdate -format Logic /tb_axis_ram_writer/dut/tlast_pending

# -----------------------------------------------------------------------------
# Grupo: Contadores del Testbench (Verificación)
# -----------------------------------------------------------------------------
add wave -noupdate -divider "TB VERIFICATION"
add wave -noupdate -format Literal -radix unsigned -color Green \
    /tb_axis_ram_writer/samples_sent
add wave -noupdate -format Literal -radix unsigned -color Cyan \
    /tb_axis_ram_writer/axi_txn_count
add wave -noupdate -format Literal -radix unsigned -color Yellow \
    /tb_axis_ram_writer/axi_beat_count
add wave -noupdate -format Literal -radix unsigned -color Magenta \
    /tb_axis_ram_writer/total_bytes_to_memory
add wave -noupdate -format Literal -radix unsigned -color Red \
    /tb_axis_ram_writer/mismatches

# -----------------------------------------------------------------------------
# Configuración de zoom y cursores
# -----------------------------------------------------------------------------
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
WaveRestoreZoom {0 ns} {50000 ns}

# Mensaje inicial
echo "============================================================"
echo "  RAM Writer Debug Session"
echo "============================================================"
echo "  Buscando bug: datos no escritos completamente"
echo "  Hipótesis:"
echo "    H1 - TLAST no dispara flush"
echo "    H2 - Último burst incompleto"
echo "    H3 - Límite 4KB"
echo "    H4 - Backpressure"
echo "============================================================"
echo ""
echo "  Comandos útiles:"
echo "    run 100us    - Ejecutar 100 microsegundos"
echo "    run -all     - Ejecutar hasta $finish"
echo "    bp <signal>  - Breakpoint en señal"
echo "============================================================"

# Ejecutar simulación
run -all
