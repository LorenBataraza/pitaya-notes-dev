# =============================================================================
# wave_scope.do - Configuración de ondas para tb_axis_scope
# =============================================================================

source questa/wave_setup.do

delete wave *

# -----------------------------------------------------------------------------
# Grupo: Reloj y Reset
# -----------------------------------------------------------------------------
add wave -noupdate -divider "CLOCK & RESET"
add wave -noupdate -format Logic -color Cyan /tb_axis_scope/aclk
add wave -noupdate -format Logic -color Orange /tb_axis_scope/aresetn

# -----------------------------------------------------------------------------
# Grupo: Configuración
# -----------------------------------------------------------------------------
add wave -noupdate -divider "CONFIGURATION"
add wave -noupdate -format Logic /tb_axis_scope/config_i.enable
add wave -noupdate -format Logic /tb_axis_scope/config_i.arm
add wave -noupdate -format Literal -radix unsigned /tb_axis_scope/config_i.pre_samples
add wave -noupdate -format Literal -radix unsigned /tb_axis_scope/config_i.post_samples

# -----------------------------------------------------------------------------
# Grupo: AXI-Stream Slave (Entrada)
# -----------------------------------------------------------------------------
add wave -noupdate -divider "AXI-S INPUT"
add wave -noupdate -format Analog-Step -height 60 -max 1024 -min 0 \
    -color Yellow /tb_axis_scope/s_axis_tdata
add wave -noupdate -format Logic -color Green /tb_axis_scope/s_axis_tvalid
add wave -noupdate -format Logic -color Magenta /tb_axis_scope/s_axis_tready

# -----------------------------------------------------------------------------
# Grupo: Trigger Input
# -----------------------------------------------------------------------------
add wave -noupdate -divider "TRIGGER"
add wave -noupdate -format Logic -color Red -height 20 /tb_axis_scope/trigger_i

# -----------------------------------------------------------------------------
# Grupo: AXI-Stream Master (Salida)
# -----------------------------------------------------------------------------
add wave -noupdate -divider "AXI-S OUTPUT"
add wave -noupdate -format Analog-Step -height 60 -max 1024 -min 0 \
    -color Cyan /tb_axis_scope/m_axis_tdata
add wave -noupdate -format Logic -color Green /tb_axis_scope/m_axis_tvalid
add wave -noupdate -format Logic -color Magenta /tb_axis_scope/m_axis_tready
add wave -noupdate -format Logic -color Red -height 20 /tb_axis_scope/m_axis_tlast

# -----------------------------------------------------------------------------
# Grupo: Status
# -----------------------------------------------------------------------------
add wave -noupdate -divider "STATUS"
add wave -noupdate -format Literal /tb_axis_scope/status_o.state
add wave -noupdate -format Logic /tb_axis_scope/status_o.armed
add wave -noupdate -format Logic /tb_axis_scope/status_o.triggered
add wave -noupdate -format Logic /tb_axis_scope/status_o.done

# -----------------------------------------------------------------------------
# Grupo: Internos del DUT
# -----------------------------------------------------------------------------
add wave -noupdate -divider "DUT STATE MACHINE"
add wave -noupdate -format Literal -color Orange /tb_axis_scope/dut/state

add wave -noupdate -divider "DUT COUNTERS"
add wave -noupdate -format Literal -radix unsigned /tb_axis_scope/dut/wr_ptr
add wave -noupdate -format Literal -radix unsigned /tb_axis_scope/dut/rd_ptr
add wave -noupdate -format Literal -radix unsigned /tb_axis_scope/dut/post_count
add wave -noupdate -format Literal -radix unsigned /tb_axis_scope/dut/transfer_count

# -----------------------------------------------------------------------------
# Configuración de zoom
# -----------------------------------------------------------------------------
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
WaveRestoreZoom {0 ns} {20000 ns}

run -all
