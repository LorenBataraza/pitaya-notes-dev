# =============================================================================
# wave_trigger.do - Configuración de ondas para tb_axis_trigger
# =============================================================================

# Cargar setup general
source questa/wave_setup.do

# Limpiar ondas existentes
delete wave *

# -----------------------------------------------------------------------------
# Grupo: Reloj y Reset
# -----------------------------------------------------------------------------
add wave -noupdate -divider "CLOCK & RESET"
add wave -noupdate -format Logic -color Cyan /tb_axis_trigger/aclk
add wave -noupdate -format Logic -color Orange /tb_axis_trigger/aresetn

# -----------------------------------------------------------------------------
# Grupo: Configuración
# -----------------------------------------------------------------------------
add wave -noupdate -divider "CONFIGURATION"
add wave -noupdate -format Logic /tb_axis_trigger/config_i.enable
add wave -noupdate -format Literal -radix unsigned /tb_axis_trigger/config_i.threshold
add wave -noupdate -format Literal /tb_axis_trigger/config_i.mode

# -----------------------------------------------------------------------------
# Grupo: AXI-Stream Slave (Entrada)
# -----------------------------------------------------------------------------
add wave -noupdate -divider "AXI-S SLAVE (INPUT)"
add wave -noupdate -format Analog-Step -height 60 -max 1024 -min 0 \
    -color Yellow /tb_axis_trigger/s_axis_tdata
add wave -noupdate -format Logic -color Green /tb_axis_trigger/s_axis_tvalid
add wave -noupdate -format Logic -color Magenta /tb_axis_trigger/s_axis_tready

# -----------------------------------------------------------------------------
# Grupo: AXI-Stream Master (Salida)
# -----------------------------------------------------------------------------
add wave -noupdate -divider "AXI-S MASTER (OUTPUT)"
add wave -noupdate -format Analog-Step -height 60 -max 1024 -min 0 \
    -color Cyan /tb_axis_trigger/m_axis_tdata
add wave -noupdate -format Logic -color Green /tb_axis_trigger/m_axis_tvalid
add wave -noupdate -format Logic -color Magenta /tb_axis_trigger/m_axis_tready

# -----------------------------------------------------------------------------
# Grupo: Trigger Output
# -----------------------------------------------------------------------------
add wave -noupdate -divider "TRIGGER OUTPUT"
add wave -noupdate -format Logic -color Red -height 30 /tb_axis_trigger/trigger_out

# -----------------------------------------------------------------------------
# Grupo: Internos del DUT
# -----------------------------------------------------------------------------
add wave -noupdate -divider "DUT INTERNALS"
add wave -noupdate -format Literal -radix decimal /tb_axis_trigger/dut/sample_pipe
add wave -noupdate -format Logic /tb_axis_trigger/dut/valid_pipe
add wave -noupdate -format Logic /tb_axis_trigger/dut/rising_edge_detect
add wave -noupdate -format Logic /tb_axis_trigger/dut/falling_edge_detect
add wave -noupdate -format Logic /tb_axis_trigger/dut/event_detected
add wave -noupdate -format Logic /tb_axis_trigger/dut/armed

# -----------------------------------------------------------------------------
# Grupo: Scoreboard
# -----------------------------------------------------------------------------
add wave -noupdate -divider "SCOREBOARD"
add wave -noupdate -format Literal -radix unsigned /tb_axis_trigger/total_samples
add wave -noupdate -format Literal -radix unsigned /tb_axis_trigger/triggers_detected
add wave -noupdate -format Literal -radix unsigned /tb_axis_trigger/triggers_expected
add wave -noupdate -format Literal -radix unsigned /tb_axis_trigger/mismatches

# -----------------------------------------------------------------------------
# Configuración de zoom y cursor
# -----------------------------------------------------------------------------
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
WaveRestoreZoom {0 ns} {10000 ns}

# Ejecutar simulación
run -all
