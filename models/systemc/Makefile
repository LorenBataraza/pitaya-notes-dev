# ============================================================================
# Makefile para testbenches SystemC TLM 2.0
# ============================================================================
#
# Uso:
#   make all              - Compilar todos los testbenches
#   make tb_trigger       - Compilar testbench del trigger
#   make run_trigger      - Ejecutar testbench del trigger
#   make run_trigger_all  - Ejecutar todos los tests del trigger
#   make clean            - Limpiar archivos generados
#
# Requisitos:
#   - SystemC 2.3.3+ instalado
#   - Variable SYSTEMC_HOME apuntando a la instalación
#
# ============================================================================

# -----------------------------------------------------------------------------
# Configuración de SystemC
# -----------------------------------------------------------------------------

# Detectar SYSTEMC_HOME o usar default
SYSTEMC_HOME ?= /opt/systemc
SYSTEMC_INC   = $(SYSTEMC_HOME)/include
SYSTEMC_LIB   = $(SYSTEMC_HOME)/lib-linux64

# Verificar que existe
ifeq ($(wildcard $(SYSTEMC_INC)/systemc.h),)
    $(warning SystemC not found at $(SYSTEMC_HOME))
    $(warning Set SYSTEMC_HOME to your SystemC installation)
endif

# -----------------------------------------------------------------------------
# Compilador y flags
# -----------------------------------------------------------------------------

CXX      = g++
CXXFLAGS = -std=c++17 -Wall -Wextra -O2 -g
CXXFLAGS += -I$(SYSTEMC_INC)
CXXFLAGS += -I./common
CXXFLAGS += -I.

LDFLAGS  = -L$(SYSTEMC_LIB)
LDLIBS   = -lsystemc -lm -lpthread

# Para runtime
export LD_LIBRARY_PATH := $(SYSTEMC_LIB):$(LD_LIBRARY_PATH)

# -----------------------------------------------------------------------------
# Directorios
# -----------------------------------------------------------------------------

BUILD_DIR   = build
BIN_DIR     = bin
VECTORS_DIR = ../../../sim/vectors
LOG_DIR     = ../../../sim/logs

# Crear directorios si no existen
$(shell mkdir -p $(BUILD_DIR) $(BIN_DIR))

# -----------------------------------------------------------------------------
# Fuentes
# -----------------------------------------------------------------------------

# Trigger
TRIGGER_SRC = trigger/tb_trigger_tlm.cpp
TRIGGER_HDR = trigger/trigger_tlm.h common/axis_tlm_types.h
TRIGGER_BIN = $(BIN_DIR)/tb_trigger_tlm

# Scope
SCOPE_SRC   = scope/tb_scope_tlm.cpp
SCOPE_HDR   = scope/scope_tlm.h common/axis_tlm_types.h
SCOPE_BIN   = $(BIN_DIR)/tb_scope_tlm

# RAM Writer
RW_SRC      = ram_writer/tb_ram_writer_tlm.cpp
RW_HDR      = ram_writer/ram_writer_tlm.h common/axis_tlm_types.h
RW_BIN      = $(BIN_DIR)/tb_ram_writer_tlm

# -----------------------------------------------------------------------------
# Targets principales
# -----------------------------------------------------------------------------

.PHONY: all clean help run_trigger run_trigger_all run_scope run_scope_all run_rw run_rw_all

all: tb_trigger tb_scope tb_ram_writer

help:
	@echo "============================================================"
	@echo "Makefile para testbenches SystemC TLM 2.0"
	@echo "============================================================"
	@echo ""
	@echo "Targets de compilación:"
	@echo "  make tb_trigger      - Compilar testbench del trigger"
	@echo "  make tb_scope        - Compilar testbench del scope"
	@echo "  make tb_ram_writer   - Compilar testbench del RAM writer"
	@echo "  make all             - Compilar todos"
	@echo ""
	@echo "Targets de ejecución:"
	@echo "  make run_trigger           - Ejecutar test por defecto"
	@echo "  make run_trigger_all       - Ejecutar todos los tests"
	@echo "  make run_trigger TEST=name - Ejecutar test específico"
	@echo ""
	@echo "Otros:"
	@echo "  make clean           - Limpiar archivos generados"
	@echo ""
	@echo "Variables de entorno:"
	@echo "  SYSTEMC_HOME=$(SYSTEMC_HOME)"

# -----------------------------------------------------------------------------
# Compilación
# -----------------------------------------------------------------------------

tb_trigger: $(TRIGGER_BIN)

$(TRIGGER_BIN): $(TRIGGER_SRC) $(TRIGGER_HDR)
	@echo ">>> Compilando testbench TLM del trigger..."
	$(CXX) $(CXXFLAGS) -I. $(TRIGGER_SRC) -o $@ $(LDFLAGS) $(LDLIBS)
	@echo ">>> Generado: $@"

tb_scope: $(SCOPE_BIN)

$(SCOPE_BIN): $(SCOPE_SRC) $(SCOPE_HDR)
	@echo ">>> Compilando testbench TLM del scope..."
	$(CXX) $(CXXFLAGS) -I. $(SCOPE_SRC) -o $@ $(LDFLAGS) $(LDLIBS)

tb_ram_writer: $(RW_BIN)

$(RW_BIN): $(RW_SRC) $(RW_HDR)
	@echo ">>> Compilando testbench TLM del RAM writer..."
	$(CXX) $(CXXFLAGS) -I. $(RW_SRC) -o $@ $(LDFLAGS) $(LDLIBS)

# -----------------------------------------------------------------------------
# Ejecución
# -----------------------------------------------------------------------------

# Test por defecto
TEST ?= trigger_rising_ramp

run_trigger: $(TRIGGER_BIN)
	@mkdir -p $(LOG_DIR)
	@echo ">>> Ejecutando test TLM: $(TEST)..."
	$(TRIGGER_BIN) --vectors=$(VECTORS_DIR) --test=$(TEST) \
		--log=$(LOG_DIR)/trigger_tlm_$(TEST).log
	@echo ">>> Log guardado en: $(LOG_DIR)/trigger_tlm_$(TEST).log"
	@tail -20 $(LOG_DIR)/trigger_tlm_$(TEST).log

run_trigger_all: $(TRIGGER_BIN)
	@mkdir -p $(LOG_DIR)
	@echo ">>> Ejecutando todos los tests TLM del trigger..."
	@echo "============================================================" > $(LOG_DIR)/trigger_tlm_regression.log
	@echo "REGRESSION TLM - TRIGGER" >> $(LOG_DIR)/trigger_tlm_regression.log
	@echo "============================================================" >> $(LOG_DIR)/trigger_tlm_regression.log
	@PASSED=0; FAILED=0; \
	for TEST in trigger_rising_ramp trigger_falling_ramp trigger_both_sine trigger_rising_pulse trigger_level_random; do \
		echo ""; \
		echo ">>> Test: $$TEST"; \
		$(TRIGGER_BIN) --vectors=$(VECTORS_DIR) --test=$$TEST \
			--log=$(LOG_DIR)/trigger_tlm_$$TEST.log; \
		if [ $$? -eq 0 ]; then \
			echo "    PASSED"; \
			PASSED=$$((PASSED+1)); \
		else \
			echo "    FAILED"; \
			FAILED=$$((FAILED+1)); \
		fi; \
		cat $(LOG_DIR)/trigger_tlm_$$TEST.log >> $(LOG_DIR)/trigger_tlm_regression.log; \
	done; \
	echo ""; \
	echo "============================================================"; \
	echo "RESUMEN: $$PASSED passed, $$FAILED failed"; \
	echo "============================================================"; \
	echo "Log completo: $(LOG_DIR)/trigger_tlm_regression.log"; \
	test $$FAILED -eq 0

# -----------------------------------------------------------------------------
# Ejecución - Scope
# -----------------------------------------------------------------------------

SCOPE_TEST ?= scope_single

run_scope: $(SCOPE_BIN)
	@mkdir -p $(LOG_DIR)
	@echo ">>> Ejecutando test TLM scope: $(SCOPE_TEST)..."
	$(SCOPE_BIN) --vectors=$(VECTORS_DIR) --test=$(SCOPE_TEST) \
		--log=$(LOG_DIR)/scope_tlm_$(SCOPE_TEST).log
	@echo ">>> Log: $(LOG_DIR)/scope_tlm_$(SCOPE_TEST).log"
	@tail -15 $(LOG_DIR)/scope_tlm_$(SCOPE_TEST).log

run_scope_all: $(SCOPE_BIN)
	@mkdir -p $(LOG_DIR)
	@echo ">>> Ejecutando todos los tests TLM del scope..."
	@PASSED=0; FAILED=0; \
	for TEST in scope_single scope_multiple scope_edge_start scope_edge_end scope_large_pre; do \
		echo ">>> Test: $$TEST"; \
		$(SCOPE_BIN) --vectors=$(VECTORS_DIR) --test=$$TEST \
			--log=$(LOG_DIR)/scope_tlm_$$TEST.log; \
		if [ $$? -eq 0 ]; then \
			echo "    PASSED"; PASSED=$$((PASSED+1)); \
		else \
			echo "    FAILED"; FAILED=$$((FAILED+1)); \
		fi; \
	done; \
	echo "RESUMEN: $$PASSED passed, $$FAILED failed"; \
	test $$FAILED -eq 0

# -----------------------------------------------------------------------------
# Ejecución - RAM Writer
# -----------------------------------------------------------------------------

RW_TEST ?= rw_basic_256

run_rw: $(RW_BIN)
	@mkdir -p $(LOG_DIR)
	@echo ">>> Ejecutando test TLM ram_writer: $(RW_TEST)..."
	$(RW_BIN) --vectors=$(VECTORS_DIR) --test=$(RW_TEST) \
		--log=$(LOG_DIR)/rw_tlm_$(RW_TEST).log
	@echo ">>> Log: $(LOG_DIR)/rw_tlm_$(RW_TEST).log"
	@tail -15 $(LOG_DIR)/rw_tlm_$(RW_TEST).log

run_rw_all: $(RW_BIN)
	@mkdir -p $(LOG_DIR)
	@echo ">>> Ejecutando todos los tests TLM del RAM writer..."
	@PASSED=0; FAILED=0; \
	for TEST in rw_basic_256 rw_partial_100 rw_partial_257 rw_multi_packet rw_near_4kb rw_stress; do \
		echo ">>> Test: $$TEST"; \
		$(RW_BIN) --vectors=$(VECTORS_DIR) --test=$$TEST \
			--log=$(LOG_DIR)/rw_tlm_$$TEST.log; \
		if [ $$? -eq 0 ]; then \
			echo "    PASSED"; PASSED=$$((PASSED+1)); \
		else \
			echo "    FAILED"; FAILED=$$((FAILED+1)); \
		fi; \
	done; \
	echo "RESUMEN: $$PASSED passed, $$FAILED failed"; \
	test $$FAILED -eq 0

# -----------------------------------------------------------------------------
# Limpieza
# -----------------------------------------------------------------------------

clean:
	@echo ">>> Limpiando..."
	rm -rf $(BUILD_DIR) $(BIN_DIR)
	rm -f *.o *.vcd
	@echo ">>> Limpieza completada"

# -----------------------------------------------------------------------------
# Debug
# -----------------------------------------------------------------------------

.PHONY: check_systemc

check_systemc:
	@echo "SYSTEMC_HOME = $(SYSTEMC_HOME)"
	@echo "SYSTEMC_INC  = $(SYSTEMC_INC)"
	@echo "SYSTEMC_LIB  = $(SYSTEMC_LIB)"
	@test -f $(SYSTEMC_INC)/systemc.h && echo "systemc.h: OK" || echo "systemc.h: NOT FOUND"
	@test -f $(SYSTEMC_LIB)/libsystemc.so && echo "libsystemc.so: OK" || echo "libsystemc.so: NOT FOUND"
