#!/bin/bash
# =============================================================================
# run_verification.sh - Script de ejecución del flujo de verificación
# =============================================================================
#
# Uso:
#   ./run_verification.sh [opciones]
#
# Opciones:
#   -g, --generate     Solo generar vectores (Python)
#   -c, --compile      Solo compilar RTL
#   -s, --simulate     Solo ejecutar simulación
#   -t, --test NAME    Ejecutar test específico
#   -d, --debug        Abrir GUI de QuestaSim para debug
#   -m, --module MOD   Módulo a simular (trigger, scope, ram_writer)
#   -h, --help         Mostrar ayuda
#
# Ejemplos:
#   ./run_verification.sh                    # Flujo completo
#   ./run_verification.sh -g                 # Solo generar vectores
#   ./run_verification.sh -m trigger -d      # Debug del trigger con GUI
#   ./run_verification.sh -m ram_writer -t rw_partial_257  # Test específico
# =============================================================================

set -e  # Salir en caso de error

# -----------------------------------------------------------------------------
# Configuración
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

VECTORS_DIR="$PROJECT_DIR/sim/vectors"
LOG_DIR="$SCRIPT_DIR/logs"
WORK_DIR="$SCRIPT_DIR/work"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Funciones de utilidad
# -----------------------------------------------------------------------------
print_header() {
    echo ""
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}============================================================${NC}"
}

print_step() {
    echo -e "${GREEN}>>> $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

show_help() {
    head -30 "$0" | grep -E "^#" | sed 's/^# *//'
    exit 0
}

# -----------------------------------------------------------------------------
# Parsear argumentos
# -----------------------------------------------------------------------------
DO_GENERATE=true
DO_COMPILE=true
DO_SIMULATE=true
DEBUG_MODE=false
MODULE="all"
TEST_NAME=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -g|--generate)
            DO_COMPILE=false
            DO_SIMULATE=false
            shift
            ;;
        -c|--compile)
            DO_GENERATE=false
            DO_SIMULATE=false
            shift
            ;;
        -s|--simulate)
            DO_GENERATE=false
            DO_COMPILE=false
            shift
            ;;
        -t|--test)
            TEST_NAME="$2"
            shift 2
            ;;
        -d|--debug)
            DEBUG_MODE=true
            shift
            ;;
        -m|--module)
            MODULE="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        *)
            print_error "Opción desconocida: $1"
            show_help
            ;;
    esac
done

# -----------------------------------------------------------------------------
# 1. Generación de vectores (Python)
# -----------------------------------------------------------------------------
if [ "$DO_GENERATE" = true ]; then
    print_header "GENERACIÓN DE VECTORES DE TEST"
    
    cd "$PROJECT_DIR"
    
    print_step "Ejecutando generate_vectors.py..."
    python3 scripts/generate_vectors.py -o sim/vectors
    
    print_step "Vectores generados en: $VECTORS_DIR"
    ls -la "$VECTORS_DIR"/*.hex 2>/dev/null | head -10 || true
    echo ""
fi

# -----------------------------------------------------------------------------
# 2. Compilación (QuestaSim)
# -----------------------------------------------------------------------------
if [ "$DO_COMPILE" = true ]; then
    print_header "COMPILACIÓN RTL"
    
    cd "$SCRIPT_DIR"
    
    # Crear biblioteca de trabajo
    if [ ! -d "$WORK_DIR" ]; then
        print_step "Creando biblioteca de trabajo..."
        vlib "$WORK_DIR"
        vmap work "$WORK_DIR"
    fi
    
    # Compilar package común
    print_step "Compilando axi_stream_pkg.sv..."
    vlog -sv -work "$WORK_DIR" +incdir+"$PROJECT_DIR/rtl/common" \
        "$PROJECT_DIR/rtl/common/axi_stream_pkg.sv"
    
    # Compilar módulos según selección
    case $MODULE in
        trigger|all)
            print_step "Compilando trigger..."
            vlog -sv -work "$WORK_DIR" "$PROJECT_DIR/rtl/trigger/axis_trigger.sv"
            vlog -sv -work "$WORK_DIR" "$PROJECT_DIR/tb/unit/tb_axis_trigger.sv"
            ;;
    esac
    
    case $MODULE in
        scope|all)
            print_step "Compilando scope..."
            vlog -sv -work "$WORK_DIR" "$PROJECT_DIR/rtl/scope/axis_scope.sv"
            if [ -f "$PROJECT_DIR/tb/unit/tb_axis_scope.sv" ]; then
                vlog -sv -work "$WORK_DIR" "$PROJECT_DIR/tb/unit/tb_axis_scope.sv"
            else
                print_warn "tb_axis_scope.sv no existe aún"
            fi
            ;;
    esac
    
    case $MODULE in
        ram_writer|all)
            print_step "Compilando RAM writer..."
            vlog -sv -work "$WORK_DIR" "$PROJECT_DIR/rtl/ram_writer/axis_ram_writer.sv"
            vlog -sv -work "$WORK_DIR" "$PROJECT_DIR/tb/unit/tb_axis_ram_writer.sv"
            ;;
    esac
    
    print_step "Compilación completada"
fi

# -----------------------------------------------------------------------------
# 3. Simulación (QuestaSim)
# -----------------------------------------------------------------------------
if [ "$DO_SIMULATE" = true ]; then
    print_header "SIMULACIÓN"
    
    cd "$SCRIPT_DIR"
    mkdir -p "$LOG_DIR"
    
    # Construir argumentos de vsim
    VSIM_ARGS="-work $WORK_DIR -t 1ps"
    VSIM_ARGS="$VSIM_ARGS +VECTORS_DIR=$VECTORS_DIR"
    
    if [ -n "$TEST_NAME" ]; then
        VSIM_ARGS="$VSIM_ARGS +TEST=$TEST_NAME"
    fi
    
    run_sim() {
        local tb_name=$1
        local log_file=$2
        local wave_do=$3
        
        if [ "$DEBUG_MODE" = true ]; then
            print_step "Abriendo GUI para $tb_name..."
            vsim $VSIM_ARGS -voptargs="+acc" "$tb_name" \
                -do "source questa/$wave_do; run -all"
        else
            print_step "Ejecutando $tb_name en batch..."
            vsim $VSIM_ARGS -c "$tb_name" \
                -do "run -all; quit -f" \
                -l "$LOG_DIR/$log_file" 2>&1 | tee "$LOG_DIR/${log_file%.log}_console.log"
        fi
    }
    
    case $MODULE in
        trigger)
            run_sim "tb_axis_trigger" "trigger_sim.log" "wave_trigger.do"
            ;;
        scope)
            if [ -f "$PROJECT_DIR/tb/unit/tb_axis_scope.sv" ]; then
                run_sim "tb_axis_scope" "scope_sim.log" "wave_scope.do"
            else
                print_warn "Testbench del scope no disponible"
            fi
            ;;
        ram_writer)
            run_sim "tb_axis_ram_writer" "ram_writer_sim.log" "wave_ram_writer.do"
            ;;
        all)
            run_sim "tb_axis_trigger" "trigger_sim.log" "wave_trigger.do"
            run_sim "tb_axis_ram_writer" "ram_writer_sim.log" "wave_ram_writer.do"
            ;;
    esac
fi

# -----------------------------------------------------------------------------
# 4. Resumen
# -----------------------------------------------------------------------------
print_header "RESUMEN"

if [ "$DO_SIMULATE" = true ] && [ "$DEBUG_MODE" = false ]; then
    echo ""
    echo "Resultados de simulación:"
    echo "-------------------------"
    
    for log in "$LOG_DIR"/*.log; do
        if [ -f "$log" ]; then
            name=$(basename "$log")
            pass_count=$(grep -c "PASS" "$log" 2>/dev/null || echo "0")
            fail_count=$(grep -c "FAIL" "$log" 2>/dev/null || echo "0")
            
            if [ "$fail_count" -gt 0 ]; then
                echo -e "  ${RED}✗${NC} $name: $fail_count FAIL(s)"
            else
                echo -e "  ${GREEN}✓${NC} $name: $pass_count PASS"
            fi
        fi
    done
    
    echo ""
    echo "Logs guardados en: $LOG_DIR/"
fi

echo ""
print_step "Verificación completada"
