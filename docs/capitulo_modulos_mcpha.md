# Capítulo: Módulos del Sistema de Adquisición MCPHA

**Autor:** Lorenzo Cabrera Blanch  
**Institución:** Instituto Balseiro / CNEA  
**Proyecto:** Analizador Multicanal de Altura de Pulsos sobre Red Pitaya (Zynq-7010)

---

## Índice

1. [Introducción](#1-introducción)
2. [Arquitectura del Sistema](#2-arquitectura-del-sistema)
3. [Módulo Trigger](#3-módulo-trigger)
4. [Módulo Scope](#4-módulo-scope)
5. [Módulo RAM Writer](#5-módulo-ram-writer)
6. [Estrategia de Verificación](#6-estrategia-de-verificación)
7. [Apéndice A: Diagramas WaveDrom](#apéndice-a-diagramas-wavedrom)
8. [Apéndice B: Glosario](#apéndice-b-glosario)

---

## 1. Introducción

Este capítulo describe los módulos principales del sistema de adquisición MCPHA. La implementación RTL se encuentra en `rtl/` y los modelos de referencia en `models/python/` y `models/systemc/`.

### 1.1 Niveles de Abstracción

| Nivel | Ubicación | Propósito |
|-------|-----------|-----------|
| Algoritmo (ESL) | `models/python/` | Definir comportamiento esperado |
| TLM 2.0 LT | `models/systemc/` | Validación transaccional, co-simulación |
| RTL | `rtl/` | Implementación sintetizable |
| Verificación UVM | `tb/uvm/` | Cobertura y regresión |

### 1.2 Convenciones

| Símbolo | Significado |
|---------|-------------|
| `[n]` | Muestra en el instante n |
| `[n-1]` | Muestra del ciclo anterior |
| `↑` / `↓` | Flanco ascendente / descendente |
| TVALID ∧ TREADY | Handshake AXI-Stream completado |

---

## 2. Arquitectura del Sistema

### 2.1 Cadena de Procesamiento

```
ADC CH1/CH2 (14 bits @ 125 MSa/s)
         │
         ▼
    ┌─────────┐
    │ TRIGGER │──────► trigger_out (pulso)
    └────┬────┘
         │ AXI-Stream (datos + evento)
         ▼
    ┌─────────┐
    │  SCOPE  │ ◄──── pre_samples, post_samples
    └────┬────┘
         │ AXI-Stream (ventana capturada)
         ▼
  ┌────────────┐
  │ RAM WRITER │──────► DDR3 via AXI4 HP
  └────────────┘
```

### 2.2 Restricciones del Sistema

| Parámetro | Valor | Origen |
|-----------|-------|--------|
| Frecuencia de reloj | 125 MHz | PLL del ADC |
| Tasa de muestreo | 125 MSa/s | ADC LTC2145-14 |
| Ancho de datos interno | 16 bits | Alineación a potencia de 2 |
| Ancho de bus AXI4 | 64 bits | Puerto HP del Zynq |
| Latencia Trigger → Scope | 2 ciclos | Pipeline de comparación |
| Buffer máximo Scope | 16384 muestras | Recursos BRAM |
| Throughput AXI4 | 1.2 GB/s | 64 bits × 150 MHz |

### 2.3 Interface AXI-Stream

Todos los módulos usan AXI-Stream para el flujo de datos:

| Señal | Dir | Descripción |
|-------|-----|-------------|
| `tdata` | M→S | Datos (16 bits por muestra) |
| `tvalid` | M→S | Indica dato válido |
| `tready` | S→M | Indica receptor listo |
| `tlast` | M→S | Marca fin de paquete |

Transferencia válida: `tvalid=1` ∧ `tready=1`

---

## 3. Módulo Trigger

**Archivo RTL:** `rtl/trigger/axis_trigger.sv`  
**Modelo Python:** `models/python/trigger_model.py`  
**Modelo TLM:** `models/systemc/trigger/trigger_tlm.h`

### 3.1 Descripción Funcional

Detecta cruces de umbral en el flujo de datos. Genera un pulso de trigger que inicia la captura en el Scope.

### 3.2 Modos de Operación

| Modo | Código | Condición de disparo |
|------|--------|---------------------|
| RISING | 0 | `sample[n-1] < threshold` ∧ `sample[n] ≥ threshold` |
| FALLING | 1 | `sample[n-1] ≥ threshold` ∧ `sample[n] < threshold` |
| BOTH | 2 | Cualquier cruce del umbral |
| LEVEL | 3 | `sample[n] ≥ threshold` (continuo) |

### 3.3 Diagrama de Bloques

```
┌──────────────────────────────────────────────────────────────┐
│                       axis_trigger                           │
│                                                              │
│  s_axis_tdata ──┬────────────────────────────► m_axis_tdata  │
│                 │                                            │
│                 ▼                                            │
│          ┌──────────┐     ┌──────────┐                       │
│          │ STAGE 0  │────►│ STAGE 1  │  (pipeline 2 ciclos)  │
│          │ (curr)   │     │ (prev)   │                       │
│          └────┬─────┘     └────┬─────┘                       │
│               └───────┬────────┘                             │
│                       ▼                                      │
│              ┌─────────────────┐                             │
│              │   COMPARADOR    │◄─── threshold, mode         │
│              └────────┬────────┘                             │
│                       ▼                                      │
│              ┌─────────────────┐                             │
│              │  LÓGICA ARMADO  │  (previene triggers múltiples)│
│              └────────┬────────┘                             │
│                       │                                      │
│  enable ────────────►AND───────────────────────► trigger_out │
└──────────────────────────────────────────────────────────────┘
```

### 3.4 Interfaz

| Señal | Dir | Ancho | Descripción |
|-------|-----|-------|-------------|
| `aclk` | in | 1 | Reloj 125 MHz |
| `aresetn` | in | 1 | Reset activo bajo |
| `config_i.enable` | in | 1 | Habilita módulo |
| `config_i.mode` | in | 2 | Modo de detección |
| `config_i.threshold` | in | 16 | Umbral (signed) |
| `s_axis_*` | in | - | AXI-Stream entrada |
| `m_axis_*` | out | - | AXI-Stream salida (passthrough) |
| `trigger_out` | out | 1 | Pulso de trigger |

### 3.5 Comportamiento Clave

**Lógica de re-armado:** Después de detectar un trigger, el módulo se "desarma" hasta que la condición deje de cumplirse. Esto previene múltiples triggers cuando la señal oscila cerca del umbral.

**Latencia:** 2 ciclos de reloj (determinístico). El pipeline permite cerrar timing a 125 MHz.

### 3.6 Casos Límite

| Caso | Comportamiento |
|------|----------------|
| Señal oscila ±1 LSB del threshold | Re-armado previene triggers múltiples |
| Threshold = 0x7FFF (máximo) | Solo señales saturadas disparan |
| Modo LEVEL con señal estable | Trigger continuo mientras esté sobre umbral |

---

## 4. Módulo Scope

**Archivo RTL:** `rtl/scope/axis_scope.sv`  
**Modelo Python:** `models/python/scope_model.py`  
**Modelo TLM:** `models/systemc/scope/scope_tlm.h`

### 4.1 Descripción Funcional

Captura ventanas de datos alrededor de eventos de trigger. Mantiene un buffer circular de pre-trigger y almacena post-trigger samples después del evento.

### 4.2 Máquina de Estados

```
         ┌─────────────────────────────────────────────────┐
         │                                                 │
         ▼                                                 │
┌──────────────┐   enable    ┌──────────────┐              │
│     IDLE     │────────────►│   FILLING    │              │
└──────────────┘             └──────┬───────┘              │
                                    │ buffer_full          │
                                    ▼                      │
                             ┌──────────────┐              │
                   ┌────────►│    ARMED     │              │
                   │         └──────┬───────┘              │
                   │                │ trigger              │
                   │                ▼                      │
                   │         ┌──────────────┐              │
                   │         │  CAPTURING   │              │
                   │         └──────┬───────┘              │
                   │                │ post_complete        │
                   │                ▼                      │
                   │         ┌──────────────┐              │
                   └─────────┤  OUTPUTTING  │──────────────┘
                    done     └──────────────┘   (vuelve a ARMED)
```

### 4.3 Parámetros de Configuración

| Parámetro | Descripción | Rango típico |
|-----------|-------------|--------------|
| `pre_samples` | Muestras antes del trigger | 1 - 8192 |
| `post_samples` | Muestras después del trigger | 1 - 8192 |
| `buffer_depth` | Profundidad total del buffer | ≤ 16384 |

### 4.4 Diagrama de Bloques

```
┌─────────────────────────────────────────────────────────────────┐
│                          axis_scope                              │
│                                                                 │
│  s_axis_tdata ──────────┬───────────────────────────────────────┤
│                         │                                       │
│                         ▼                                       │
│               ┌───────────────────┐                             │
│               │  BUFFER CIRCULAR  │◄─── pre_samples             │
│               │   (BRAM/LUTRAM)   │                             │
│               └─────────┬─────────┘                             │
│                         │                                       │
│  trigger_in ──────────►MUX────────►┌───────────────┐            │
│                         │          │ CAPTURE BUFFER│            │
│                         │          │    (BRAM)     │            │
│                         │          └───────┬───────┘            │
│                         │                  │                    │
│                         │                  ▼                    │
│               ┌─────────┴──────────────────────────┐            │
│               │             FSM                    │            │
│               │  IDLE→FILLING→ARMED→CAPTURING→OUT  │            │
│               └─────────────────────────┬──────────┘            │
│                                         │                       │
│                                         ▼                       │
│                               m_axis_tdata, tlast ──────────────┤
└─────────────────────────────────────────────────────────────────┘
```

### 4.5 Comportamiento Clave

**Buffer circular:** En estado ARMED, el buffer funciona como FIFO circular. Cada nueva muestra desplaza la más antigua. Esto permite capturar `pre_samples` muestras anteriores al trigger sin conocer de antemano cuándo ocurrirá.

**Copia en trigger:** Cuando llega el trigger, las `pre_samples` del buffer circular se copian al buffer de captura. Esto evita que sean sobrescritas mientras se captura el post-trigger.

**TLAST:** Se genera automáticamente en la última muestra de cada ventana capturada.

### 4.6 Casos Límite

| Caso | Comportamiento |
|------|----------------|
| Trigger antes de llenar pre-buffer | Captura comienza con menos muestras pre |
| Trigger durante OUTPUTTING | Se ignora (módulo ocupado) |
| post_samples = 0 | Solo pre-trigger en la salida |
| Backpressure durante output | FSM espera TREADY |

---

## 5. Módulo RAM Writer

**Archivo RTL:** `rtl/ram_writer/axis_ram_writer.sv`  
**Modelo Python:** `models/python/ram_writer_model.py`  
**Modelo TLM:** `models/systemc/ram_writer/ram_writer_tlm.h`

### 5.1 Descripción Funcional

Recibe datos por AXI-Stream y los escribe en DDR via AXI4 usando transacciones burst. Maneja el empaquetado de datos (4×16 bits → 64 bits) y respeta las restricciones AXI4.

### 5.2 Restricciones AXI4

| Restricción | Descripción |
|-------------|-------------|
| Límite 4KB | Un burst no puede cruzar frontera de 4KB |
| AWLEN máximo | 255 beats (256 transferencias) |
| Alineación | Dirección debe estar alineada al ancho de datos |

### 5.3 Diagrama de Bloques

```
┌─────────────────────────────────────────────────────────────────┐
│                       axis_ram_writer                            │
│                                                                  │
│  s_axis_tdata ─────────────────────────┐                        │
│  (16 bits)                             │                        │
│                                        ▼                        │
│                              ┌──────────────────┐               │
│                              │  EMPAQUETADOR    │               │
│                              │  4×16 → 64 bits  │               │
│                              └────────┬─────────┘               │
│                                       │                         │
│                                       ▼                         │
│                              ┌──────────────────┐               │
│                              │      FIFO        │  (absorbe     │
│                              │   (1024 words)   │   latencia    │
│                              └────────┬─────────┘   AXI)        │
│                                       │                         │
│                                       ▼                         │
│                              ┌──────────────────┐               │
│  base_addr, size ──────────►│  BURST GENERATOR │               │
│                              │  (respeta 4KB)   │               │
│                              └────────┬─────────┘               │
│                                       │                         │
│                                       ▼                         │
│                              ┌──────────────────┐               │
│                              │  AXI4 MASTER     │───► m_axi_*   │
│                              │  (write channel) │               │
│                              └──────────────────┘               │
└─────────────────────────────────────────────────────────────────┘
```

### 5.4 Parámetros de Configuración

| Parámetro | Descripción | Valor típico |
|-----------|-------------|--------------|
| `base_addr` | Dirección base en DDR | 0x1000_0000 |
| `buffer_size` | Tamaño del buffer | 1 MB |
| `burst_len` | Beats por burst | 16 |

### 5.5 Algoritmo de División de Bursts

```
Para cada bloque de datos:
  1. Calcular dirección fin = addr + burst_len × 8
  2. Si cruza frontera 4KB:
     - Primer burst hasta la frontera
     - Segundo burst desde la frontera
  3. Si FIFO tiene suficientes datos:
     - Emitir transacción AXI4
  4. En TLAST: flush de datos pendientes con padding
```

### 5.6 Casos Límite

| Caso | Comportamiento |
|------|----------------|
| Burst cruza 4KB | Se divide en dos transacciones |
| TLAST con datos parciales | Padding a 64 bits, burst corto |
| FIFO lleno | Backpressure en AXI-Stream |
| Respuesta AXI con error | Captura en registro de status |

---

## 6. Estrategia de Verificación

### 6.1 Flujo de Verificación

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Python Model   │────►│  SystemC TLM    │────►│  RTL (UVM)      │
│  (Algoritmo)    │     │  (Transaccional)│     │  (Ciclo-exacto) │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         └───────────────────────┴───────────────────────┘
                                 │
                         sim/vectors/*.hex
                      (mismos vectores en todos)
```

### 6.2 Ejecución de Tests

```bash
# TLM (SystemC)
cd models/systemc
make all
make run_trigger_all
make run_scope_all
make run_rw_all

# RTL (QuestaSim)
cd scripts
make regression
```

### 6.3 Tests Disponibles

| Módulo | Test | Descripción |
|--------|------|-------------|
| Trigger | `trigger_rising_ramp` | Rampa ascendente, flanco subida |
| Trigger | `trigger_falling_ramp` | Rampa descendente, flanco bajada |
| Trigger | `trigger_both_sine` | Senoidal, ambos flancos |
| Trigger | `trigger_rising_pulse` | Pulsos gaussianos |
| Trigger | `trigger_level_random` | Datos aleatorios, modo nivel |
| Scope | `scope_single` | Un solo trigger |
| Scope | `scope_multiple` | Múltiples triggers |
| Scope | `scope_edge_*` | Triggers en bordes del buffer |
| RAM Writer | `rw_basic_256` | Escritura básica |
| RAM Writer | `rw_near_4kb` | Cerca del límite 4KB |
| RAM Writer | `rw_stress` | Alta tasa de datos |

---

## Apéndice A: Diagramas WaveDrom

### A.1 Trigger: Detección de Flanco Ascendente

```wavedrom
{
  signal: [
    {name: 'clk',         wave: 'p........'},
    {name: 's_axis_tdata', wave: 'x3333333x', data: ['490','495','499','502','505','510','515']},
    {name: 'threshold',   wave: '2........', data: ['500']},
    {name: 'pipeline[0]', wave: 'x3333333x', data: ['490','495','499','502','505','510','515']},
    {name: 'pipeline[1]', wave: 'xx333333x', data: ['490','495','499','502','505','510']},
    {name: 'event_det',   wave: '0...10...'},
    {name: 'armed',       wave: '1...01...'},
    {name: 'trigger_out', wave: '0...10...'}
  ],
  config: { hscale: 1.5 }
}
```

### A.2 Scope: Captura de Ventana

```wavedrom
{
  signal: [
    {name: 'clk',        wave: 'p..........'},
    {name: 'state',      wave: '2.3..4..5.2', data: ['ARMED','CAPT','CAPT','OUT','ARMED']},
    {name: 'trigger_in', wave: '0.10.......'},
    {name: 'pre_ready',  wave: '1..........'},
    {name: 'post_cnt',   wave: 'x.2..3..4.x', data: ['0','1','2','3']},
    {name: 'm_axis_tvalid', wave: '0.......1.0'},
    {name: 'm_axis_tlast',  wave: '0........10'}
  ]
}
```

---

## Apéndice B: Glosario

| Término | Definición |
|---------|------------|
| ESL | Electronic System Level - Modelado a nivel de sistema |
| TLM | Transaction Level Modeling - Abstracción de comunicación |
| LT | Loosely-Timed - Temporización aproximada en TLM |
| AXI-Stream | Protocolo punto a punto para flujos de datos |
| AXI4 | Protocolo de bus para acceso a memoria |
| BRAM | Block RAM del FPGA |
| Burst | Transferencia de múltiples beats consecutivos |
| Handshake | Sincronización TVALID/TREADY |
| Re-armado | Mecanismo para evitar triggers múltiples espurios |
