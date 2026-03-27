# Arquitectura de Verificación MCPHA

## Visión General

El proyecto MCPHA utiliza un flujo de verificación multinivel que permite validar el diseño desde el algoritmo hasta el RTL final. Esta arquitectura sigue el enfoque de **refinamiento progresivo** descrito en el Capítulo 11 de Mehta.

## Niveles de Verificación

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    UNIFIED VERIFICATION PLAN                            │
│                      (Coverage Driven)                                  │
└─────────────────────────────────────────────────────────────────────────┘
         │                    │                    │
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  ESL Testbench  │  │ ESL+RTL Testbench│ │  RTL Testbench  │
│  (SystemC TLM)  │  │    (Híbrido)     │  │     (UVM)       │
│                 │  │                  │  │                 │
│  Rápido         │  │  Validación      │  │  Ciclo-exacto   │
│  Funcional      │  │  Incremental     │  │  Cobertura      │
└────────┬────────┘  └────────┬─────────┘  └────────┬────────┘
         │                    │                     │
         ▼                    ▼                     ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Python Model   │  │  TLM Model      │  │  RTL (DUT)      │
│  (Algoritmo)    │  │  (SystemC LT)   │  │  (SystemVerilog)│
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

## Estructura de Carpetas

```
mcpha_verification/
├── models/
│   ├── python/                    # Modelos algorítmicos (Golden Reference)
│   │   ├── trigger_model.py
│   │   ├── scope_model.py
│   │   └── ram_writer_model.py
│   │
│   └── systemc/                   # Modelos TLM 2.0 (LT)
│       ├── Makefile
│       ├── common/
│       │   └── axis_tlm_types.h   # Tipos y transacciones TLM
│       └── trigger/
│           ├── trigger_tlm.h      # Modelo TLM del trigger
│           └── tb_trigger_tlm.cpp # Testbench SystemC
│
├── rtl/                           # Diseño RTL sintetizable
│   ├── common/
│   │   └── axi_stream_pkg.sv
│   ├── trigger/
│   │   └── axis_trigger.sv
│   ├── scope/
│   │   └── axis_scope.sv
│   └── ram_writer/
│       └── axis_ram_writer.sv
│
├── tb/
│   ├── unit/                      # Testbenches unitarios (sin UVM)
│   │   ├── tb_axis_trigger.sv
│   │   ├── tb_axis_scope.sv
│   │   └── tb_axis_ram_writer.sv
│   │
│   └── uvm/                       # Testbenches UVM
│       ├── interfaces/
│       │   └── axis_if.sv         # Interface AXI-Stream
│       │
│       ├── agents/
│       │   └── axis/              # Agent AXI-Stream
│       │       ├── axis_seq_item.sv
│       │       ├── axis_driver.sv
│       │       ├── axis_monitor.sv
│       │       ├── axis_agent.sv
│       │       ├── axis_sequences.sv
│       │       └── axis_agent_pkg.sv
│       │
│       ├── env/
│       │   ├── trigger_scoreboard.sv
│       │   └── trigger_env.sv
│       │
│       ├── sequences/             # Sequences específicas (futuro)
│       │
│       ├── tests/
│       │   ├── trigger_tests.sv
│       │   └── tb_trigger_uvm_top.sv
│       │
│       └── pkg/
│           └── mcpha_uvm_pkg.sv
│
├── sim/
│   ├── vectors/                   # Vectores generados por Python
│   └── logs/                      # Logs de todas las simulaciones
│
└── scripts/
    ├── Makefile                   # Para RTL/QuestaSim
    └── generate_vectors.py
```

## Flujo de Ejecución

### 1. Validación Algorítmica (Python)

```bash
cd mcpha_verification

# Ejecutar tests unitarios del modelo Python
python3 -m pytest models/python/ -v

# Generar vectores para simulación RTL/TLM
python3 scripts/generate_vectors.py -o sim/vectors
```

**Propósito**: Validar que el algoritmo es correcto antes de invertir tiempo en simulación de hardware.

### 2. Simulación TLM (SystemC)

```bash
cd models/systemc

# Verificar que SystemC está instalado
make check_systemc

# Compilar testbench TLM
make tb_trigger

# Ejecutar un test
make run_trigger TEST=trigger_rising_ramp

# Ejecutar todos los tests
make run_trigger_all
```

**Propósito**: Validar el modelo TLM contra los mismos vectores que usará el RTL. Esto asegura que la traducción Python → TLM es correcta.

**Logs**: `sim/logs/trigger_tlm_*.log`

### 3. Simulación RTL Unitaria (QuestaSim)

```bash
cd scripts

# Compilar RTL y testbenches
make clean
make compile

# Ejecutar test del trigger
make sim_trigger

# Ejecutar con GUI para debug
make gui_trigger

# Regresión completa
make regression
```

**Propósito**: Verificar que el RTL implementa correctamente el comportamiento del modelo.

**Logs**: `sim/logs/trigger_sim.log`

### 4. Simulación UVM (QuestaSim)

```bash
cd scripts

# Compilar con soporte UVM
make compile_uvm

# Ejecutar test específico
vsim -c tb_trigger_uvm_top +UVM_TESTNAME=trigger_rising_ramp_test \
     -do "run -all" -l ../sim/logs/trigger_uvm.log

# Ejecutar con coverage
vsim -c tb_trigger_uvm_top +UVM_TESTNAME=trigger_rising_ramp_test \
     -coverage -do "run -all; coverage save trigger_cov.ucdb"
```

**Propósito**: Verificación exhaustiva con cobertura funcional y métricas de calidad.

**Logs**: `sim/logs/trigger_uvm.log`

## Componentes UVM

### Agent AXI-Stream

```
┌─────────────────────────────────────────────────────────┐
│                     axis_agent                          │
│                                                         │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   │
│  │  sequencer  │──►│   driver    │──►│ axis_if     │   │
│  └─────────────┘   └─────────────┘   └──────┬──────┘   │
│                                             │          │
│                    ┌─────────────┐          │          │
│                    │   monitor   │◄─────────┘          │
│                    └──────┬──────┘                     │
│                           │                            │
│                           ▼                            │
│                    ┌─────────────┐                     │
│                    │ analysis_   │──► scoreboard       │
│                    │ port        │──► coverage         │
│                    └─────────────┘                     │
└─────────────────────────────────────────────────────────┘
```

### Environment del Trigger

```
┌─────────────────────────────────────────────────────────────────────┐
│                        trigger_env                                  │
│                                                                     │
│  ┌─────────────────┐                   ┌─────────────────┐          │
│  │  input_agent    │                   │  output_agent   │          │
│  │  (ACTIVE)       │                   │  (PASSIVE)      │          │
│  │                 │                   │                 │          │
│  │  - sequencer    │                   │  - monitor      │          │
│  │  - driver       │                   │  - slave_driver │          │
│  │  - monitor      │                   │                 │          │
│  └────────┬────────┘                   └────────┬────────┘          │
│           │                                     │                   │
│           │  analysis_port                      │  analysis_port    │
│           ▼                                     ▼                   │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                     trigger_scoreboard                      │    │
│  │                                                             │    │
│  │  - Compara entrada vs salida                                │    │
│  │  - Verifica eventos de trigger                              │    │
│  │  - Calcula estadísticas (TP, FP, FN)                        │    │
│  └─────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

## Tests Disponibles

| Test | Nivel | Descripción |
|------|-------|-------------|
| `trigger_rising_ramp_test` | UVM | Rampa ascendente, flanco subida |
| `trigger_falling_ramp_test` | UVM | Rampa descendente, flanco bajada |
| `trigger_both_sine_test` | UVM | Senoidal, ambos flancos |
| `trigger_pulse_test` | UVM | Pulsos gaussianos |
| `trigger_random_test` | UVM | Datos aleatorios (sin scoreboard) |
| `trigger_backpressure_test` | UVM | Con TREADY intermitente |

## Reutilización de Vectores

El mismo conjunto de vectores `.hex` se usa en todos los niveles:

```
generate_vectors.py
        │
        ▼
   sim/vectors/
        │
        ├──► TLM Testbench (SystemC)
        │         └── tb_trigger_tlm --vectors=../sim/vectors
        │
        ├──► Unit Testbench (SV)
        │         └── $readmemh("../sim/vectors/...")
        │
        └──► UVM Testbench
                  └── axis_file_sequence::load_file()
```

Esto garantiza que si un test pasa en un nivel, debería pasar en los demás (excepto por bugs de implementación).

## Métricas de Verificación

### Cobertura Funcional (UVM)

El environment incluye covergroups para:

1. **Protocolo AXI-Stream**:
   - Estados de handshake (TVALID × TREADY)
   - Transiciones de estado
   - Presencia de TLAST

2. **Funcionalidad del Trigger**:
   - Modos de operación (RISING, FALLING, BOTH, LEVEL)
   - Cruces de umbral
   - Re-armado automático

3. **Corner Cases**:
   - Backpressure prolongado
   - Señal cerca del umbral
   - Múltiples triggers consecutivos

### Assertions (SVA)

Los archivos `*_sva.sv` en `rtl_enhanced/` contienen assertions para:

- Estabilidad de señales durante handshake
- Protocolo AXI-Stream
- Invariantes de FSM
- Límites de burst AXI4

## Próximos Pasos

1. Completar modelos TLM para Scope y RAM Writer
2. Implementar agents UVM para AXI4 (RAM Writer)
3. Crear testbench de integración (cadena completa)
4. Agregar coverage de código y assertions
5. Integrar con flujo de CI/CD
