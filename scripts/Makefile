# =============================================================================
# Makefile para simulación con QuestaSim
# Sistema de Adquisición Multi-Canal MCPHA
# Soporte para simulación mixta ESL + RTL
# =============================================================================

# -----------------------------------------------------------------------------
# Configuración de herramientas
# -----------------------------------------------------------------------------
VLIB    := vlib
VMAP    := vmap
VLOG    := vlog
VSIM    := vsim
PYTHON  := python3
GCC     := gcc

# -----------------------------------------------------------------------------
# Directorios
# -----------------------------------------------------------------------------
RTL_DIR       := ../rtl
RTL_ENH_DIR   := ../rtl_enhanced
TB_DIR        := ../tb
ADAPTERS_DIR  := ../tb/adapters
CHECKERS_DIR  := ../tb/checkers
DPI_DIR       := ../tb/dpi
SCRIPTS_DIR   := .
VECTORS_DIR   := ../sim/vectors
WORK_DIR      := work
LOG_DIR       := ../sim/logs
WAVE_DIR      := waves
LIB_DIR       := lib

# -----------------------------------------------------------------------------
# Opciones de compilación
# -----------------------------------------------------------------------------
VLOG_OPTS := -sv -work $(WORK_DIR) +incdir+$(RTL_DIR)/common
VLOG_OPTS += -suppress 2583  # Suppress "variable not used" warnings
VLOG_OPTS += -suppress 13314 # Suppress "hierarchical name" warnings

# Opciones de simulación
VSIM_OPTS := -work $(WORK_DIR) -t 1ps
VSIM_OPTS += -voptargs="+acc"  # Full visibility for debugging
VSIM_OPTS += +nowarnTFMPC      # Suppress timing check warnings

# Para regresión (batch mode)
VSIM_BATCH := $(VSIM_OPTS) -c -do "run -all; quit -f"

# Para GUI
VSIM_GUI := $(VSIM_OPTS) -do questa/wave_setup.do

# -----------------------------------------------------------------------------
# Archivos fuente
# -----------------------------------------------------------------------------
PKG_FILES := $(RTL_DIR)/common/axi_stream_pkg.sv

TRIGGER_RTL := $(RTL_DIR)/trigger/axis_trigger.sv
TRIGGER_TB  := $(TB_DIR)/unit/tb_axis_trigger.sv

SCOPE_RTL   := $(RTL_DIR)/scope/axis_scope.sv
SCOPE_TB    := $(TB_DIR)/unit/tb_axis_scope.sv

RW_RTL      := $(RTL_DIR)/ram_writer/axis_ram_writer.sv
RW_TB       := $(TB_DIR)/unit/tb_axis_ram_writer.sv

# Integración
TRIG_COMB_RTL := $(RTL_DIR)/trigger/trigger_combiner.sv
# Interface AXI4 simplificada (sin clocking blocks)
AXI4_SIMPLE_IF := $(TB_DIR)/integration/axi4_write_simple_if.sv
# Agent UVM completo (para tests UVM futuros)
AXI4_AGENT    := $(TB_DIR)/agents/axi4_write/axi4_write_if.sv \
                 $(TB_DIR)/agents/axi4_write/axi4_write_pkg.sv
INTEG_TB      := $(TB_DIR)/integration/tb_acquisition_chain.sv

# -----------------------------------------------------------------------------
# Targets principales
# -----------------------------------------------------------------------------
.PHONY: all clean vectors lib compile sim_trigger sim_scope sim_rw \
        gui_trigger gui_scope gui_rw regression help \
        compile_integration sim_integration gui_integration

all: lib compile

help:
	@echo "============================================================"
	@echo "  MCPHA Verification - QuestaSim Flow"
	@echo "============================================================"
	@echo ""
	@echo "Targets disponibles:"
	@echo "  make vectors     - Generar vectores de test (Python)"
	@echo "  make lib         - Crear biblioteca de trabajo"
	@echo "  make compile     - Compilar todos los fuentes"
	@echo ""
	@echo "  === Tests Unitarios ==="
	@echo "  make sim_trigger - Simular trigger (batch)"
	@echo "  make sim_scope   - Simular scope (batch)"
	@echo "  make sim_rw      - Simular RAM writer (batch)"
	@echo ""
	@echo "  make gui_trigger - Simular trigger (GUI + waves)"
	@echo "  make gui_scope   - Simular scope (GUI + waves)"
	@echo "  make gui_rw      - Simular RAM writer (GUI + waves)"
	@echo ""
	@echo "  === Test de Integracion ==="
	@echo "  make compile_integration - Compilar cadena completa"
	@echo "  make sim_integration     - Simular integracion (batch)"
	@echo "  make gui_integration     - Simular integracion (GUI)"
	@echo ""
	@echo "  make regression  - Ejecutar todos los tests (batch)"
	@echo "  make clean       - Limpiar archivos generados"
	@echo ""

# -----------------------------------------------------------------------------
# Preparación
# -----------------------------------------------------------------------------
lib: $(WORK_DIR)

$(WORK_DIR):
	@echo ">>> Creando biblioteca de trabajo..."
	$(VLIB) $(WORK_DIR)
	$(VMAP) work $(WORK_DIR)

$(LOG_DIR):
	@mkdir -p $(LOG_DIR)

$(WAVE_DIR):
	@mkdir -p $(WAVE_DIR)

vectors:
	@echo ">>> Generando vectores de test..."
	cd .. && $(PYTHON) scripts/generate_vectors.py -o sim/vectors
	@echo ">>> Vectores generados en $(VECTORS_DIR)"

# -----------------------------------------------------------------------------
# Compilación
# -----------------------------------------------------------------------------
compile: lib compile_pkg compile_trigger compile_scope compile_rw
	@echo ">>> Compilación completa"

compile_pkg: lib
	@echo ">>> Compilando package..."
	$(VLOG) $(VLOG_OPTS) $(PKG_FILES)

compile_trigger: compile_pkg
	@echo ">>> Compilando trigger..."
	$(VLOG) $(VLOG_OPTS) $(TRIGGER_RTL)
	$(VLOG) $(VLOG_OPTS) $(TRIGGER_TB)

compile_scope: compile_pkg
	@echo ">>> Compilando scope..."
	$(VLOG) $(VLOG_OPTS) $(SCOPE_RTL)
	@if [ -f "$(SCOPE_TB)" ]; then \
		$(VLOG) $(VLOG_OPTS) $(SCOPE_TB); \
	else \
		echo "    [WARN] $(SCOPE_TB) no existe aún"; \
	fi

compile_rw: compile_pkg
	@echo ">>> Compilando RAM writer..."
	$(VLOG) $(VLOG_OPTS) $(RW_RTL)
	$(VLOG) $(VLOG_OPTS) $(RW_TB)

# -----------------------------------------------------------------------------
# Simulación en batch (para regresión)
# -----------------------------------------------------------------------------
sim_trigger: compile_trigger vectors $(LOG_DIR)
	@echo ">>> Simulando trigger (batch)..."
	$(VSIM) $(VSIM_BATCH) tb_axis_trigger \
		+VECTORS_DIR=$(VECTORS_DIR) \
		-l $(LOG_DIR)/trigger_sim.log
	@echo ">>> Log guardado en $(LOG_DIR)/trigger_sim.log"

sim_scope: compile_scope vectors $(LOG_DIR)
	@echo ">>> Simulando scope (batch)..."
	@if [ -f "$(SCOPE_TB)" ]; then \
		$(VSIM) $(VSIM_BATCH) tb_axis_scope \
			+VECTORS_DIR=$(VECTORS_DIR) \
			-l $(LOG_DIR)/scope_sim.log; \
		echo ">>> Log guardado en $(LOG_DIR)/scope_sim.log"; \
	else \
		echo "    [SKIP] Testbench no disponible"; \
	fi

sim_rw: compile_rw vectors $(LOG_DIR)
	@echo ">>> Simulando RAM writer (batch)..."
	$(VSIM) $(VSIM_BATCH) tb_axis_ram_writer \
		+VECTORS_DIR=$(VECTORS_DIR) \
		-l $(LOG_DIR)/ram_writer_sim.log
	@echo ">>> Log guardado en $(LOG_DIR)/ram_writer_sim.log"

# -----------------------------------------------------------------------------
# Simulación con GUI (para debug)
# -----------------------------------------------------------------------------
gui_trigger: compile_trigger vectors $(WAVE_DIR)
	@echo ">>> Abriendo GUI para trigger..."
	$(VSIM) $(VSIM_GUI) tb_axis_trigger \
		+VECTORS_DIR=$(VECTORS_DIR) \
		-do "source questa/wave_trigger.do"

gui_scope: compile_scope vectors $(WAVE_DIR)
	@echo ">>> Abriendo GUI para scope..."
	$(VSIM) $(VSIM_GUI) tb_axis_scope \
		+VECTORS_DIR=$(VECTORS_DIR) \
		-do "source questa/wave_scope.do"

gui_rw: compile_rw vectors $(WAVE_DIR)
	@echo ">>> Abriendo GUI para RAM writer..."
	$(VSIM) $(VSIM_GUI) tb_axis_ram_writer \
		+VECTORS_DIR=$(VECTORS_DIR) \
		-do "source questa/wave_ram_writer.do"

# -----------------------------------------------------------------------------
# Regresión completa
# -----------------------------------------------------------------------------
regression: $(LOG_DIR)
	@echo "============================================================"
	@echo "  REGRESIÓN COMPLETA"
	@echo "============================================================"
	@$(MAKE) sim_trigger
	@$(MAKE) sim_scope
	@$(MAKE) sim_rw
	@$(MAKE) sim_integration
	@echo ""
	@echo ">>> Regresión completada. Revisar logs en $(LOG_DIR)/"
	@grep -h "PASS\|FAIL" $(LOG_DIR)/*.log || true

# -----------------------------------------------------------------------------
# Testbench de Integración
# -----------------------------------------------------------------------------
compile_integration: compile_pkg
	@echo ">>> Compilando modulos RTL para integracion..."
	$(VLOG) $(VLOG_OPTS) $(TRIGGER_RTL)
	$(VLOG) $(VLOG_OPTS) $(TRIG_COMB_RTL)
	$(VLOG) $(VLOG_OPTS) $(SCOPE_RTL)
	$(VLOG) $(VLOG_OPTS) $(RW_RTL)
	@echo ">>> Compilando interface AXI4 simplificada..."
	$(VLOG) $(VLOG_OPTS) $(AXI4_SIMPLE_IF)
	@echo ">>> Compilando testbench de integracion..."
	$(VLOG) $(VLOG_OPTS) $(INTEG_TB)
	@echo ">>> Compilacion de integracion completa"

sim_integration: compile_integration $(LOG_DIR)
	@echo ">>> Simulando cadena de adquisicion (batch)..."
	$(VSIM) $(VSIM_BATCH) tb_acquisition_chain \
		-l $(LOG_DIR)/integration_sim.log
	@echo ">>> Log guardado en $(LOG_DIR)/integration_sim.log"

gui_integration: compile_integration $(WAVE_DIR)
	@echo ">>> Abriendo GUI para integracion..."
	$(VSIM) $(VSIM_OPTS) tb_acquisition_chain \
		-do "add wave -r /*; run -all"

# -----------------------------------------------------------------------------
# Limpieza
# -----------------------------------------------------------------------------
clean:
	@echo ">>> Limpiando..."
	rm -rf $(WORK_DIR)
	rm -rf $(LOG_DIR)
	rm -rf $(WAVE_DIR)
	rm -f transcript
	rm -f vsim.wlf
	rm -f *.vcd
	@echo ">>> Limpieza completa"

clean_vectors:
	@echo ">>> Limpiando vectores..."
	rm -rf $(VECTORS_DIR)/*

distclean: clean clean_vectors
