# =============================================================================
# wave_setup.do - Script general de configuración de QuestaSim
# =============================================================================

# Configuración de simulación
set NumericStdNoWarnings 1
set StdArithNoWarnings 1

# Configuración de ondas
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns

# Configuración de colores
configure wave -foregroundcolor White
configure wave -backgroundcolor Black
configure wave -cursorcolor Yellow
configure wave -gridcolor Gray50
