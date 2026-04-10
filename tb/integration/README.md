# Testbench de Integración MCPHA

## Descripción

Este testbench verifica la cadena completa de adquisición del MCPHA:

```
                         ┌───────────┐
  Stimulus ──► Trigger 0 ─┤           │
                          │ Combiner  ├──► Scope ──► RAM Writer ──► Memory
  Stimulus ──► Trigger 1 ─┤           │
                         └───────────┘
```

## Componentes

### RTL bajo test

| Módulo | Archivo | Función |
|--------|---------|---------|
| `axis_trigger` | `rtl/trigger/axis_trigger.sv` | Detección de umbral por canal |
| `trigger_combiner` | `rtl/trigger/trigger_combiner.sv` | Lógica de combinación configurable |
| `axis_scope` | `rtl/scope/axis_scope.sv` | Buffer circular pre/post trigger |
| `axis_ram_writer` | `rtl/ram_writer/axis_ram_writer.sv` | Empaquetado y escritura AXI4 |

### Componentes de verificación

| Componente | Ubicación | Función |
|------------|-----------|---------|
| `axi4_write_agent` | `tb/agents/axi4_write/` | Agent UVM para AXI4 Write |
| `axi4_write_memory` | `tb/agents/axi4_write/` | Modelo de memoria AXI4 |
| `dpi_bridge` | `tb/dpi/` | Interfaz DPI-C para modelo de referencia |

## Modos de combinación de triggers

El módulo `trigger_combiner` soporta los siguientes modos:

| Modo | Valor | Descripción |
|------|-------|-------------|
| `MODE_OR` | `3'b000` | OR de todos los canales habilitados |
| `MODE_AND` | `3'b001` | AND de todos los canales habilitados |
| `MODE_CH0` | `3'b010` | Solo canal 0 |
| `MODE_CH1` | `3'b011` | Solo canal 1 |
| `MODE_BLOCK` | `3'b100` | CH0 dispara solo si CH1 inactivo (`trig0 && ~trig1`) |
| `MODE_BLOCK_R` | `3'b101` | CH1 dispara solo si CH0 inactivo (`trig1 && ~trig0`) |

## Tests implementados

### Funcionales básicos

| Test | Descripción | Verificación |
|------|-------------|--------------|
| `basic_single_trigger` | Un trigger, captura normal | Datos en memoria = datos enviados |
| `min_window` | Ventana mínima (pre=1, post=1) | 2 muestras capturadas |
| `early_trigger` | Trigger antes de llenar pre-buffer | Captura parcial correcta |

### Combinación de triggers

| Test | Descripción | Verificación |
|------|-------------|--------------|
| `trig_or` | OR de ambos canales | El primer trigger dispara |
| `trig_blocking` | CH0 bloqueado por CH1 activo | Trigger retrasado hasta CH1 inactivo |

### Corner cases (pendientes de implementar)

| Test | Descripción |
|------|-------------|
| `rapid_triggers` | Múltiples triggers antes de completar captura |
| `backpressure_scope` | TREADY intermitente en salida del scope |
| `backpressure_ram` | AXI4 slave con backpressure |
| `boundary_4kb` | Burst que cruza frontera de 4KB |
| `max_window` | Ventana máxima (buffer completo) |

## Ejecución

```bash
cd scripts

# Compilar todo
make compile_integration

# Ejecutar simulación
make sim_integration

# Con GUI para debug
make sim_integration_gui
```

## Estructura de archivos

```
tb/
├── integration/
│   └── tb_acquisition_chain.sv    # Testbench principal
├── agents/
│   └── axi4_write/
│       ├── axi4_write_if.sv       # Interface AXI4
│       ├── axi4_write_seq_item.sv # Transacción
│       ├── axi4_write_monitor.sv  # Monitor
│       ├── axi4_write_memory.sv   # Modelo de memoria
│       ├── axi4_write_agent.sv    # Agent completo
│       └── axi4_write_pkg.sv      # Package
└── dpi/
    ├── dpi_bridge.h               # Header C
    ├── dpi_bridge.c               # Implementación C
    └── dpi_bridge.sv              # Wrapper SV
```

## Modelo de referencia (DPI-C)

El scoreboard usa modelos Python via DPI-C para predecir los datos esperados:

1. El testbench envía el estímulo a través de `dpi_send_axis_burst()`
2. El modelo Python procesa los datos y calcula la captura esperada
3. El scoreboard compara memoria AXI4 con la predicción

Para habilitar:
```bash
# Compilar librería compartida
cd tb/dpi
make dpi_bridge.so

# Ejecutar con la librería
vsim -sv_lib ../tb/dpi/dpi_bridge tb_acquisition_chain
```

## Configuración de backpressure

El `axi4_write_memory` soporta backpressure configurable:

```systemverilog
// En el test
axi_agent.aw_backpressure = 20;  // 20% probabilidad de AWREADY=0
axi_agent.w_backpressure  = 30;  // 30% probabilidad de WREADY=0
axi_agent.b_latency_min   = 1;   // Latencia mínima de respuesta
axi_agent.b_latency_max   = 10;  // Latencia máxima de respuesta
```

## Extensión a 4 canales

El sistema está preparado para expandirse a 4 canales:

1. Cambiar `NUM_CHANNELS = 4` en `trigger_combiner`
2. Agregar instancias de `axis_trigger` para CH2 y CH3
3. Extender `channel_mask` a 4 bits
4. Agregar modos de combinación adicionales si es necesario
