# Capítulo: Módulos del Sistema de Adquisición MCPHA

## Índice

1. [Introducción](#1-introducción)
2. [Arquitectura del Testbench Híbrido](#2-arquitectura-del-testbench-híbrido)
3. [Módulo Trigger (Detector de Eventos)](#3-módulo-trigger-detector-de-eventos)
4. [Módulo Scope (Buffer de Captura)](#4-módulo-scope-buffer-de-captura)
5. [Módulo RAM Writer (Escritor de Memoria)](#5-módulo-ram-writer-escritor-de-memoria)
6. [Casos de Test](#6-casos-de-test)
7. [Sistema de Build (Makefile)](#7-sistema-de-build-makefile)
8. [Apéndice A: Diagramas de Waveform (WaveDrom)](#apéndice-a-diagramas-de-waveform-wavedrom)
9. [Apéndice B: Módulos Auxiliares](#apéndice-b-módulos-auxiliares)
10. [Apéndice C: Glosario de Transacciones](#apéndice-c-glosario-de-transacciones)

---

## 1. Introducción

Este capítulo describe los módulos principales del sistema de adquisición MCPHA (Multi-Channel Pulse Height Analyzer) implementado sobre la plataforma Red Pitaya con SoC Zynq-7010. Cada módulo se presenta en tres niveles de abstracción:

- **Nivel funcional (ESL)**: Modelo de referencia en Python que define el comportamiento esperado
- **Nivel RTL**: Implementación en SystemVerilog sintetizable
- **Nivel de verificación**: Casos de test y criterios de cobertura

### 1.1 Cadena de Procesamiento

```
ADC (14 bits @ 125 MSa/s)
         │
         ▼
    ┌─────────┐
    │ TRIGGER │──────► trigger_out
    └────┬────┘
         │
         ▼
    ┌─────────┐
    │  SCOPE  │
    └────┬────┘
         │
         ▼
  ┌────────────┐
  │ RAM WRITER │──────► DDR3 (via AXI4)
  └────────────┘
```

### 1.2 Restricciones del Sistema

| Parámetro | Valor | Origen |
|-----------|-------|--------|
| Frecuencia de reloj | 125 MHz | PLL del ADC |
| Tasa de muestreo máxima | 125 MSa/s | ADC LTC2145-14 |
| Ancho de datos ADC | 14 bits | Hardware Red Pitaya |
| Ancho de datos interno | 16 bits | Alineación a potencia de 2 |
| Ancho de bus AXI4 | 64 bits | Puerto HP del Zynq |
| Frecuencia AXI4 HP | 150 MHz | FCLK_CLK0 configurable |
| Latencia máxima Trigger→Scope | 2 ciclos | Pipeline de comparación |
| Buffer máximo Scope | 16384 muestras | Recursos BRAM disponibles |
| Throughput AXI4 teórico | 1.2 GB/s | 64 bits × 150 MHz |

### 1.3 Casos Límite Considerados

**Alta velocidad (sin decimación):**
- Entrada: 125 MSa/s × 16 bits = 2 Gbps
- El Scope debe almacenar a esta tasa sin pérdida
- El RAM Writer debe sostener escritura continua

**Baja velocidad (con decimación):**
- Después de filtros CIC/FIR la tasa puede reducirse 8x-256x
- Permite ventanas de captura más largas
- El FIFO del RAM Writer puede ser más pequeño

**Latencia crítica:**
- Trigger a Scope: máximo 2 ciclos (determinístico)
- Scope a RAM Writer: variable, depende del backpressure
- RAM Writer a DDR: variable, depende de arbitraje AXI

---

## 2. Arquitectura del Testbench Híbrido

### 2.1 Justificación del Enfoque Híbrido ESL+RTL

El proyecto utiliza un testbench híbrido que combina modelos de alto nivel (ESL en Python) con verificación a nivel de señales (RTL en SystemVerilog). Esta decisión de diseño responde a tres necesidades:

#### 2.1.1 Reutilización de Modelos

Los modelos Python sirven múltiples propósitos:
- **Golden reference**: Generan las respuestas esperadas contra las que se compara el RTL
- **Generación de estímulos**: Producen vectores de test reproducibles
- **Debugging rápido**: Permiten probar algoritmos sin compilar hardware
- **Documentación ejecutable**: El código Python es más legible que el RTL

#### 2.1.2 Coherencia entre Implementaciones

Al derivar el RTL desde el modelo Python, se garantiza coherencia funcional:

```
┌─────────────────┐     ┌─────────────────┐
│  Modelo Python  │────►│  Vectores .hex  │
│  (Referencia)   │     │  (Estímulos)    │
└────────┬────────┘     └────────┬────────┘
         │                       │
         │ Verificación          │ $readmemh
         │ conceptual            │
         ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│   RTL (DUT)     │◄────│   Testbench     │
│                 │     │   SystemVerilog │
└────────┬────────┘     └────────┬────────┘
         │                       │
         │ Simulación            │ Comparación
         ▼                       ▼
┌─────────────────┐     ┌─────────────────┐
│  Waveforms      │     │  Scoreboard     │
│  (.vcd/.wlf)    │     │  (Pass/Fail)    │
└─────────────────┘     └─────────────────┘
```

#### 2.1.3 Verificación en Múltiples Niveles

El enfoque híbrido permite verificar en diferentes granularidades:

| Nivel | Herramienta | Qué verifica |
|-------|-------------|--------------|
| Funcional | Python + pytest | Algoritmos, casos límite |
| Transaccional | Adaptadores SV | Protocolo AXI-Stream |
| Ciclo-a-ciclo | SVA (assertions) | Timing, FSM |
| Cobertura | Covergroups | Completitud de tests |

### 2.2 Flujo de Verificación

```
1. Modelo Python         2. Generación           3. Simulación RTL
   ┌──────────────┐         ┌──────────────┐        ┌──────────────┐
   │ trigger_     │         │ generate_    │        │ QuestaSim/   │
   │ model.py     │────────►│ vectors.py   │───────►│ Icarus       │
   │              │         │              │        │              │
   │ scope_       │         │ *_stimulus   │        │ tb_axis_     │
   │ model.py     │         │ .hex         │        │ *.sv         │
   │              │         │              │        │              │
   │ ram_writer_  │         │ *_expected   │        │ Scoreboard   │
   │ model.py     │         │ .hex         │        │ SVA          │
   └──────────────┘         └──────────────┘        └──────────────┘
```

### 2.3 Hipótesis de Transformación Python → RTL

Al pasar del modelo Python al RTL, se introducen características de timing que no existen en el modelo funcional. Las hipótesis de diseño son:

#### Hipótesis H1: Pipeline de Comparación
- **Python**: Comparación instantánea `prev < threshold and curr >= threshold`
- **RTL**: Se requieren 2 registros de pipeline para cumplir timing a 125 MHz
- **Implicación**: Latencia de 2 ciclos entre entrada y trigger_out

#### Hipótesis H2: Buffer Circular como BRAM
- **Python**: `deque(maxlen=N)` con acceso O(1)
- **RTL**: BRAM de doble puerto con punteros de lectura/escritura
- **Implicación**: Latencia de 1-2 ciclos en lectura de BRAM

#### Hipótesis H3: FIFO Asíncrono para Cruce de Dominios
- **Python**: Lista simple sin consideraciones de clock
- **RTL**: FIFO con flags de casi-lleno/casi-vacío para handshaking
- **Implicación**: Margen de seguridad en nivel de FIFO para evitar overflow

#### Hipótesis H4: FSM Explícita vs. Código Secuencial
- **Python**: Control de flujo con `if/elif` secuencial
- **RTL**: Máquina de estados con transiciones síncronas
- **Implicación**: Un ciclo por transición de estado

---

## 3. Módulo Trigger (Detector de Eventos)

### 3.1 Descripción

Detecta eventos en la señal de entrada comparando muestras consecutivas contra un umbral configurable. Soporta detección por flanco ascendente, descendente, ambos, o por nivel. Incluye lógica de re-armado automático para evitar triggers múltiples en un mismo cruce.

### 3.2 Interfaces

| Interfaz | Dirección | Ancho | Tasa | Descripción |
|----------|-----------|-------|------|-------------|
| **Entrada AXI-Stream** | Slave | 16 bits | 125 MSa/s máx | Muestras del ADC/filtro |
| **Salida AXI-Stream** | Master | 16 bits | 125 MSa/s máx | Passthrough de datos |
| **Salida Trigger** | - | 1 bit | Pulso | Indica evento detectado |
| **Configuración** | - | 20 bits | Estática | enable, mode, threshold |

### 3.3 Modos de Operación

| Modo | Valor | Condición de disparo |
|------|-------|---------------------|
| RISING | 0 | `prev < threshold` AND `curr >= threshold` |
| FALLING | 1 | `prev >= threshold` AND `curr < threshold` |
| BOTH | 2 | RISING OR FALLING |
| LEVEL | 3 | `curr >= threshold` |

### 3.4 Modelo Python (Referencia)

```python
class TriggerMode(IntEnum):
    RISING  = 0
    FALLING = 1
    BOTH    = 2
    LEVEL   = 3

@dataclass
class TriggerConfig:
    enable: bool = True
    mode: TriggerMode = TriggerMode.RISING
    threshold: int = 0
    ch_mask: int = 0x03

class TriggerModel:
    PIPE_STAGES = 2  # Hipótesis H1: pipeline para timing
    
    def __init__(self, config: TriggerConfig = None):
        self.config = config if config else TriggerConfig()
        self.reset()
    
    def reset(self):
        self._pipeline = [0] * self.PIPE_STAGES
        self._valid_pipe = [False] * self.PIPE_STAGES
        self._armed = True
    
    def _detect_threshold_crossing(self, prev: int, curr: int) -> bool:
        """Detecta cruce de umbral según modo configurado."""
        threshold = self.config.threshold
        
        # Conversión a signed (16 bits)
        def to_signed(val):
            return val - 65536 if val >= 32768 else val
        
        prev_s = to_signed(prev)
        curr_s = to_signed(curr)
        threshold_s = to_signed(threshold)
        
        rising_edge = (prev_s < threshold_s) and (curr_s >= threshold_s)
        falling_edge = (prev_s >= threshold_s) and (curr_s < threshold_s)
        
        if self.config.mode == TriggerMode.RISING:
            return rising_edge
        elif self.config.mode == TriggerMode.FALLING:
            return falling_edge
        elif self.config.mode == TriggerMode.BOTH:
            return rising_edge or falling_edge
        elif self.config.mode == TriggerMode.LEVEL:
            return curr_s >= threshold_s
        return False
    
    def process_sample(self, sample: int, valid: bool = True):
        """Procesa una muestra. Retorna True si hay trigger."""
        if not self.config.enable:
            return None
        
        # Shift del pipeline (emula registros RTL)
        for i in range(self.PIPE_STAGES - 1, 0, -1):
            self._pipeline[i] = self._pipeline[i-1]
            self._valid_pipe[i] = self._valid_pipe[i-1]
        
        self._pipeline[0] = sample
        self._valid_pipe[0] = valid
        
        # Necesitamos datos válidos en ambas etapas
        if not self._valid_pipe[self.PIPE_STAGES - 2]:
            return None
        
        prev_sample = self._pipeline[self.PIPE_STAGES - 1]
        curr_sample = self._pipeline[self.PIPE_STAGES - 2]
        
        event_detected = self._detect_threshold_crossing(prev_sample, curr_sample)
        
        # Lógica de armado/re-armado
        trigger_out = False
        if self._armed and event_detected:
            trigger_out = True
            self._armed = False  # Desarmar hasta que baje
        elif not event_detected:
            self._armed = True   # Re-armar
        
        return trigger_out
```

### 3.5 Hipótesis de Transformación Python → RTL

| Aspecto | Modelo Python | Implementación RTL | Justificación |
|---------|---------------|-------------------|---------------|
| Pipeline | Lista `[0]*2` | 2 registros FF | Timing closure a 125 MHz |
| Comparador | Operadores `<`, `>=` | LUTs + carry chain | Síntesis estándar |
| Signed | Función `to_signed()` | Tipo `logic signed` | Nativo en SV |
| Re-armado | Variable `_armed` | Flip-flop de estado | 1 bit de estado |

### 3.6 Arquitectura RTL

```
                         axis_trigger
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│  s_axis_tdata ──┬──────────────────────────────────► m_axis_tdata│
│                 │                                                │
│                 ▼                                                │
│          ┌────────────┐     ┌────────────┐                       │
│          │  PIPELINE  │────►│  PIPELINE  │                       │
│          │  STAGE 0   │     │  STAGE 1   │                       │
│          │  (curr)    │     │  (prev)    │                       │
│          └─────┬──────┘     └─────┬──────┘                       │
│                │                  │                              │
│                └───────┬──────────┘                              │
│                        │                                         │
│                        ▼                                         │
│               ┌─────────────────┐                                │
│               │   COMPARADOR    │◄─── cfg_threshold              │
│               │   (signed)      │◄─── cfg_mode                   │
│               └────────┬────────┘                                │
│                        │                                         │
│                        ▼                                         │
│               ┌─────────────────┐                                │
│               │  LÓGICA DE      │                                │
│               │  RE-ARMADO      │                                │
│               └────────┬────────┘                                │
│                        │                                         │
│                        ▼                                         │
│  cfg_enable ─────────►AND───────────────────────────► trigger_out│
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 3.7 Señales de Interfaz

| Señal | Dir | Ancho | Descripción |
|-------|-----|-------|-------------|
| `aclk` | in | 1 | Reloj (125 MHz) |
| `aresetn` | in | 1 | Reset asíncrono activo bajo |
| `config_i.enable` | in | 1 | Habilita el módulo |
| `config_i.mode` | in | 2 | Modo de detección |
| `config_i.threshold` | in | 16 | Umbral (signed) |
| `s_axis_tdata` | in | 16 | Dato entrada |
| `s_axis_tvalid` | in | 1 | Dato válido |
| `s_axis_tready` | out | 1 | Listo para recibir |
| `m_axis_tdata` | out | 16 | Dato salida |
| `m_axis_tvalid` | out | 1 | Salida válida |
| `m_axis_tready` | in | 1 | Downstream listo |
| `trigger_out` | out | 1 | Pulso de trigger |

### 3.8 Casos Límite

| Caso | Condición | Comportamiento esperado |
|------|-----------|------------------------|
| Ruido en umbral | Señal oscila ±1 LSB alrededor de threshold | Re-armado previene triggers múltiples |
| Señal saturada | Entrada en 0x7FFF o 0x8000 | Trigger solo en transición |
| Threshold extremo | threshold = 0x7FFF | Solo señales máximas disparan |
| Cambio de config | Nueva configuración mid-stream | Aplicar en siguiente muestra |

---

## 4. Módulo Scope (Buffer de Captura)

### 4.1 Descripción

Implementa un buffer circular que captura una ventana de datos alrededor de un evento de trigger. Almacena continuamente muestras de pre-trigger y, al recibir el trigger, captura las muestras post-trigger configuradas. Transfiere la ventana completa por AXI-Stream con TLAST al final.

### 4.2 Interfaces

| Interfaz | Dirección | Ancho | Tasa | Descripción |
|----------|-----------|-------|------|-------------|
| **Entrada AXI-Stream** | Slave | 16 bits | 125 MSa/s máx | Muestras a capturar |
| **Salida AXI-Stream** | Master | 16 bits | Variable | Ventana capturada |
| **Entrada Trigger** | - | 1 bit | Pulso | Marca el punto de captura |
| **Configuración** | - | 34 bits | Estática | enable, arm, pre/post_samples |
| **Status** | - | 35 bits | Dinámica | armed, triggered, done, count |

### 4.3 Máquina de Estados

```
                    ┌──────────────────────────────────────┐
                    │                                      │
                    ▼                                      │
              ┌──────────┐                                 │
    reset ───►│   IDLE   │◄────────────────────────────────┤
              └────┬─────┘                                 │
                   │ arm=1                                 │
                   ▼                                       │
              ┌──────────┐                                 │
              │  ARMED   │◄──────┐                         │
              │          │       │ (llenando buffer)       │
              └────┬─────┘───────┘                         │
                   │ trigger_in=1                          │
                   ▼                                       │
              ┌──────────┐                                 │
              │TRIGGERED │◄──────┐                         │
              │          │       │ (capturando post)       │
              └────┬─────┘───────┘                         │
                   │ post_count >= post_samples            │
                   ▼                                       │
              ┌──────────┐                                 │
              │ TRANSFER │◄──────┐                         │
              │          │       │ (enviando datos)        │
              └────┬─────┘───────┘                         │
                   │ transfer_complete                     │
                   ▼                                       │
              ┌──────────┐                                 │
              │   DONE   │─────────────────────────────────┘
              └──────────┘        (re-arm o reset)
```

### 4.4 Modelo Python (Referencia)

```python
class ScopeState(IntEnum):
    IDLE      = 0
    ARMED     = 1
    TRIGGERED = 2
    TRANSFER  = 3
    DONE      = 4

@dataclass
class ScopeConfig:
    enable: bool = True
    arm: bool = False
    pre_samples: int = 100
    post_samples: int = 100

class ScopeModel:
    def __init__(self, buffer_depth: int = 4096):
        self._buffer_depth = buffer_depth
        # Hipótesis H2: deque modela BRAM circular
        self._circular_buffer = deque(maxlen=buffer_depth)
        self._post_buffer = []
        self._state = ScopeState.IDLE
        self._post_count = 0
    
    def configure(self, config: ScopeConfig):
        self._config = config
        if config.pre_samples > self._buffer_depth:
            raise ValueError("pre_samples excede buffer_depth")
        
        if config.enable and config.arm and self._state == ScopeState.IDLE:
            self._state = ScopeState.ARMED
            self._circular_buffer.clear()
            self._post_buffer.clear()
    
    def process_sample(self, sample: int) -> bool:
        """Procesa una muestra. Retorna True si fue aceptada."""
        if self._state == ScopeState.ARMED:
            # Pre-trigger: buffer circular sobrescribe datos viejos
            self._circular_buffer.append(sample)
            return True
            
        elif self._state == ScopeState.TRIGGERED:
            # Post-trigger: captura lineal
            self._post_buffer.append(sample)
            self._post_count += 1
            
            if self._post_count >= self._config.post_samples:
                self._state = ScopeState.TRANSFER
            return True
        
        return False
    
    def trigger(self) -> bool:
        """Procesa evento de trigger. Retorna True si fue aceptado."""
        if self._state != ScopeState.ARMED:
            return False
        
        self._trigger_position = len(self._circular_buffer)
        self._state = ScopeState.TRIGGERED
        self._post_count = 0
        self._post_buffer.clear()
        return True
    
    def get_captured_data(self):
        """Retorna ventana capturada: pre + post samples."""
        if self._state not in [ScopeState.TRANSFER, ScopeState.DONE]:
            return None
        
        available_pre = min(self._config.pre_samples, 
                          len(self._circular_buffer))
        
        # Extraer últimas N muestras del buffer circular
        pre_data = list(self._circular_buffer)[-available_pre:]
        all_samples = pre_data + self._post_buffer
        
        self._state = ScopeState.DONE
        return all_samples
```

### 4.5 Hipótesis de Transformación Python → RTL

| Aspecto | Modelo Python | Implementación RTL | Justificación |
|---------|---------------|-------------------|---------------|
| Buffer circular | `deque(maxlen=N)` | BRAM dual-port + punteros | Recursos FPGA |
| Puntero escritura | Implícito en deque | Registro `wr_ptr` módulo N | Control explícito |
| Puntero lectura | Índice negativo `[-N:]` | Registro `rd_ptr` calculado | `trigger_pos - pre_samples` |
| FSM | Variable `_state` | `enum` + `case` statement | Síntesis de FSM |
| Contador post | `_post_count` | Registro con comparador | Condición de transición |

### 4.6 Organización del Buffer Circular

```
Buffer de 4096 posiciones (BRAM):

Estado ARMED (llenando pre-trigger):
┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│ 0 │ 1 │ 2 │...│   │   │   │...│N-3│N-2│N-1│   │
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
                                              ▲
                                              │
                                           wr_ptr (avanza módulo N)

Estado TRANSFER (leyendo ventana):
┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
│pre│pre│pre│TRG│pst│pst│pst│   │   │   │   │   │
└───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
  ▲           ▲               ▲
  │           │               │
rd_ptr    trigger_pos      wr_ptr

Secuencia de lectura:
1. rd_ptr = (trigger_pos - pre_samples) mod N
2. Lee pre_samples desde rd_ptr
3. Lee post_samples después de trigger_pos
4. Genera TLAST en la última muestra
```

### 4.7 Casos Límite

| Caso | Condición | Comportamiento |
|------|-----------|----------------|
| Trigger temprano | `trigger_pos < pre_samples` | Captura solo `trigger_pos` muestras de pre |
| Buffer wrap | `wr_ptr` da la vuelta | Datos más viejos se sobrescriben |
| Múltiples triggers | Segundo trigger mientras TRIGGERED | Ignorado (solo cuenta el primero) |
| Backpressure | `m_axis_tready = 0` durante TRANSFER | Pausa lectura, mantiene coherencia |
| Pre=0 | `pre_samples = 0` | Solo captura post-trigger |
| Post=0 | `post_samples = 0` | Solo captura pre-trigger |

---

## 5. Módulo RAM Writer (Escritor de Memoria)

### 5.1 Descripción

Transfiere datos desde la interfaz AXI-Stream hacia la memoria DDR3 usando el protocolo AXI4 Full. Implementa un FIFO interno para desacoplar dominios de reloj y absorber variaciones de latencia. Genera transacciones burst optimizadas respetando el límite de 4KB de AXI4.

### 5.2 Interfaces

| Interfaz | Dirección | Ancho | Tasa | Descripción |
|----------|-----------|-------|------|-------------|
| **Entrada AXI-Stream** | Slave | 16 bits | 125 MSa/s máx | Datos a escribir |
| **Salida AXI4** | Master | 64 bits | 150 MHz | Escritura a DDR |
| **Configuración** | - | 65 bits | Estática | enable, base_addr, buffer_size |
| **Status** | - | 68 bits | Dinámica | state, write_ptr, bytes_written |

### 5.3 Restricciones AXI4

El protocolo AXI4 impone restricciones que el módulo debe manejar:

1. **Límite de 4KB**: Un burst no puede cruzar un límite de dirección 4KB-alineado
2. **Longitud máxima**: AWLEN ≤ 255 (256 beats máximo)
3. **Alineación**: La dirección debe estar alineada al tamaño del beat
4. **Atomicidad**: Cada beat de 64 bits debe escribirse completo

### 5.4 Modelo Python (Referencia)

```python
class WriterState(IntEnum):
    WR_IDLE   = 0
    WR_CALC   = 1
    WR_ADDR   = 2
    WR_DATA   = 3
    WR_RESP   = 4
    WR_ERROR  = 5

class RamWriterModel:
    AXI4_4KB_BOUNDARY = 0x1000
    AXI4_MAX_BURST_LEN = 256
    
    def __init__(self, fifo_depth: int = 512, data_width: int = 32):
        # Hipótesis H3: FIFO para cruce de dominios
        self._fifo = FifoModel(depth=fifo_depth, width=data_width)
        self._bytes_per_beat = data_width // 8
        self._memory = {}
        self._transactions = []
        self._current_address = 0
    
    def axis_write(self, data: int, tlast: bool = False) -> bool:
        """Escribe dato al FIFO interno."""
        return self._fifo.write(data, tlast)
    
    def _calculate_burst_params(self, address: int, data_count: int):
        """Calcula longitud de burst respetando límite 4KB."""
        bytes_to_4kb = self.AXI4_4KB_BOUNDARY - (address % self.AXI4_4KB_BOUNDARY)
        beats_to_4kb = bytes_to_4kb // self._bytes_per_beat
        
        max_beats = min(self.AXI4_MAX_BURST_LEN, data_count, beats_to_4kb)
        return max_beats
    
    def process_pending(self):
        """Procesa datos pendientes generando transacciones AXI4."""
        while not self._fifo.is_empty:
            data_available = self._fifo.level
            
            burst_len = self._calculate_burst_params(
                self._current_address, 
                data_available
            )
            
            if burst_len == 0:
                break
            
            # Leer datos del FIFO
            burst_data = self._fifo.read_burst(burst_len)
            
            # Crear transacción AXI4
            txn = Axi4WriteTransaction(
                address=self._current_address,
                data=burst_data,
                burst_len=len(burst_data)
            )
            
            # Escribir a memoria simulada
            for i, data in enumerate(burst_data):
                addr = self._current_address + i * self._bytes_per_beat
                self._memory[addr] = data
            
            self._current_address += len(burst_data) * self._bytes_per_beat
            self._transactions.append(txn)
```

### 5.5 Hipótesis de Transformación Python → RTL

| Aspecto | Modelo Python | Implementación RTL | Justificación |
|---------|---------------|-------------------|---------------|
| FIFO | Clase `FifoModel` | IP FIFO Generator / custom | CDC, flags |
| Burst builder | Método `_calculate_burst_params` | FSM + aritmética | Timing crítico |
| Límite 4KB | Cálculo Python | Comparador de bits [11:0] | Detección de cruce |
| Transacción | Objeto `Axi4WriteTransaction` | Canales AW/W/B | Protocolo AXI4 |
| Memoria | Dict `_memory` | DDR3 controller externo | Fuera del módulo |

### 5.6 Arquitectura RTL

```
                              axis_ram_writer
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  s_axis_tdata ────┐                                                         │
│  s_axis_tvalid ───┤                                                         │
│  s_axis_tready ◄──┤                                                         │
│  s_axis_tlast ────┤                                                         │
│                   │                                                         │
│                   ▼                                                         │
│          ┌─────────────────┐                                                │
│          │   INPUT FIFO    │ ◄── casi_lleno, casi_vacio                     │
│          │   (CDC)         │                                                │
│          │   1024 x 64     │                                                │
│          └────────┬────────┘                                                │
│                   │                                                         │
│                   ▼                                                         │
│          ┌─────────────────┐     ┌─────────────────┐                        │
│          │  BURST BUILDER  │────►│  4KB BOUNDARY   │                        │
│          │                 │     │    CHECKER      │                        │
│          │ - Agrupa datos  │     │                 │                        │
│          │ - Detecta TLAST │     │ burst_len =     │                        │
│          │ - Calcula len   │     │ min(available,  │                        │
│          └────────┬────────┘     │     to_4kb,     │                        │
│                   │              │     MAX_BURST)  │                        │
│                   │              └─────────────────┘                        │
│                   ▼                                                         │
│          ┌──────────────────────────────────────────────────────┐           │
│          │                     FSM                              │           │
│          │  IDLE ──► CALC ──► ADDR ──► DATA ──► RESP ──► IDLE   │           │
│          └──────────────────────────────────────────────────────┘           │
│                          │        │        │                                │
│                          ▼        ▼        ▼                                │
│                    m_axi_aw*  m_axi_w*  m_axi_b*                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.7 Manejo del Límite de 4KB

```
Ejemplo: Dirección base = 0x10000F00, datos = 512 bytes

Límite de 4KB en 0x10001000 (4096 bytes alineados)

Cálculo:
  bytes_to_4kb = 0x1000 - (0xF00) = 0x100 = 256 bytes
  burst_1_len = min(512, 256, 256*8) = 256 bytes = 32 beats @ 64 bits

Primera transacción (antes del límite):
  AWADDR = 0x10000F00
  AWLEN  = 31 (32 beats)
  Rango: 0x10000F00 - 0x10000FFF

Segunda transacción (después del límite):
  AWADDR = 0x10001000
  AWLEN  = 31 (32 beats)
  Rango: 0x10001000 - 0x100010FF
```

### 5.8 Bugs Conocidos y Hipótesis

| ID | Hipótesis | Descripción | SVA de detección |
|----|-----------|-------------|------------------|
| H1 | TLAST no flush | FIFO no se vacía al recibir TLAST | `p_tlast_causes_flush` |
| H2 | Burst incompleto | Último burst con menos beats que AWLEN | `aw_pending` counter |
| H3 | Violación 4KB | Burst cruza límite incorrectamente | `p_4kb_boundary` |
| H4 | Deadlock | Backpressure AXI4 bloquea pipeline | `p_no_deadlock` |

### 5.9 Casos Límite

| Caso | Condición | Comportamiento esperado |
|------|-----------|------------------------|
| Paquete pequeño | < 1 burst completo + TLAST | Flush inmediato del FIFO |
| Cruce de 4KB | Datos cruzan límite 4KB | Split en 2 transacciones |
| FIFO lleno | Backpressure de AXI4 | `s_axis_tready = 0` |
| Burst máximo | 256 beats | AWLEN = 255 |
| Respuesta SLVERR | bresp != OKAY | Transición a WR_ERROR |

---

## 6. Casos de Test

### 6.1 Tests del Módulo Trigger

| ID | Test | Estímulo | Resultado esperado |
|----|------|----------|-------------------|
| T1 | `test_rising_ramp` | Rampa 0→1023, th=500 | Trigger en sample ~500 |
| T2 | `test_falling_ramp` | Rampa 1023→0, th=500 | Trigger en sample ~523 |
| T3 | `test_both_sine` | Senoidal, th=512 | Triggers en cruces |
| T4 | `test_level_pulse` | Pulso rectangular | Trigger mientras > th |
| T5 | `test_noise_immunity` | Ruido cerca de th | Sin triggers espurios |
| T6 | `test_disabled` | enable=0 | Sin triggers |
| T7 | `test_rearm` | Múltiples cruces | Un trigger por cruce |

### 6.2 Tests del Módulo Scope

| ID | Test | Configuración | Resultado esperado |
|----|------|---------------|-------------------|
| S1 | `test_basic_capture` | pre=100, post=200 | 300 muestras |
| S2 | `test_pre_only` | pre=150, post=0 | 150 muestras pre |
| S3 | `test_post_only` | pre=0, post=150 | 150 muestras post |
| S4 | `test_early_trigger` | pre=100, trig@30 | 30 pre + 100 post |
| S5 | `test_multiple_triggers` | Dos triggers | Solo el primero |
| S6 | `test_backpressure` | TREADY intermitente | Datos íntegros |
| S7 | `test_state_machine` | Secuencia completa | FSM correcta |

### 6.3 Tests del Módulo RAM Writer

| ID | Test | Estímulo | Verificación |
|----|------|----------|--------------|
| R1 | `test_basic_write` | 100 muestras | bytes == 100×2 |
| R2 | `test_burst_alignment` | 500 muestras | Sin cruces 4KB |
| R3 | `test_tlast_flush` | 10 + TLAST | FIFO vacío |
| R4 | `test_backpressure` | READY intermitente | Sin pérdida |
| R5 | `test_max_burst` | 256+ muestras | AWLEN=255 |
| R6 | `test_4kb_boundary` | Addr cerca de 4KB | Split correcto |
| R7 | `test_multiple_packets` | 3 paquetes | Todos procesados |

---

## 7. Sistema de Build (Makefile)

### 7.1 Descripción General

El Makefile implementa el flujo de verificación completo, desde la generación de vectores hasta la ejecución de regresiones. Está diseñado para QuestaSim pero puede adaptarse a otros simuladores.

### 7.2 Estructura del Makefile

```makefile
# ============================================================================
# MCPHA Verification Makefile
# ============================================================================

# Herramientas
VLIB  := vlib
VMAP  := vmap
VLOG  := vlog
VSIM  := vsim
PYTHON := python3

# Directorios
RTL_DIR    := ../rtl
TB_DIR     := ../tb
WORK_DIR   := work
VECTORS_DIR := ../sim/vectors
LOG_DIR    := logs
WAVE_DIR   := waves

# Opciones de compilación
VLOG_OPTS := -sv -work $(WORK_DIR) +incdir+$(RTL_DIR)/common
VLOG_OPTS += -suppress 2583   # variable not used
VLOG_OPTS += -suppress 13314  # hierarchical name

# Opciones de simulación
VSIM_OPTS := -work $(WORK_DIR) -t 1ps
VSIM_OPTS += -voptargs="+acc"   # visibilidad para debug
VSIM_OPTS += +nowarnTFMPC       # suppress timing warnings

# Modos de ejecución
VSIM_BATCH := $(VSIM_OPTS) -c -do "run -all; quit -f"
VSIM_GUI   := $(VSIM_OPTS) -do questa/wave_setup.do

# Archivos fuente
PKG_FILES   := $(RTL_DIR)/common/axi_stream_pkg.sv
TRIGGER_RTL := $(RTL_DIR)/trigger/axis_trigger.sv
TRIGGER_TB  := $(TB_DIR)/unit/tb_axis_trigger.sv
SCOPE_RTL   := $(RTL_DIR)/scope/axis_scope.sv
SCOPE_TB    := $(TB_DIR)/unit/tb_axis_scope.sv
RW_RTL      := $(RTL_DIR)/ram_writer/axis_ram_writer.sv
RW_TB       := $(TB_DIR)/unit/tb_axis_ram_writer.sv
```

### 7.3 Targets Principales

```makefile
# Target por defecto
all: lib compile

# Ayuda
help:
    @echo "Targets disponibles:"
    @echo "  make vectors     - Generar vectores (Python)"
    @echo "  make lib         - Crear biblioteca"
    @echo "  make compile     - Compilar fuentes"
    @echo "  make sim_trigger - Simular trigger (batch)"
    @echo "  make sim_scope   - Simular scope (batch)"
    @echo "  make sim_rw      - Simular RAM writer (batch)"
    @echo "  make gui_trigger - GUI + waveforms"
    @echo "  make regression  - Todos los tests"
    @echo "  make clean       - Limpiar"

# Crear biblioteca de trabajo
lib: $(WORK_DIR)

$(WORK_DIR):
    $(VLIB) $(WORK_DIR)
    $(VMAP) work $(WORK_DIR)

# Generar vectores de test
vectors:
    cd .. && $(PYTHON) scripts/generate_vectors.py -o sim/vectors
```

### 7.4 Flujo de Compilación

```makefile
# Compilación jerárquica con dependencias
compile: lib compile_pkg compile_trigger compile_scope compile_rw

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
    $(VLOG) $(VLOG_OPTS) $(SCOPE_TB)

compile_rw: compile_pkg
    @echo ">>> Compilando RAM writer..."
    $(VLOG) $(VLOG_OPTS) $(RW_RTL)
    $(VLOG) $(VLOG_OPTS) $(RW_TB)
```

### 7.5 Flujo de Simulación

```makefile
# Simulación batch (para CI/regresión)
sim_trigger: compile_trigger vectors $(LOG_DIR)
    $(VSIM) $(VSIM_BATCH) tb_axis_trigger \
        +VECTORS_DIR=$(VECTORS_DIR) \
        -l $(LOG_DIR)/trigger_sim.log

sim_scope: compile_scope vectors $(LOG_DIR)
    $(VSIM) $(VSIM_BATCH) tb_axis_scope \
        +VECTORS_DIR=$(VECTORS_DIR) \
        -l $(LOG_DIR)/scope_sim.log

sim_rw: compile_rw vectors $(LOG_DIR)
    $(VSIM) $(VSIM_BATCH) tb_axis_ram_writer \
        +VECTORS_DIR=$(VECTORS_DIR) \
        -l $(LOG_DIR)/ram_writer_sim.log

# Simulación con GUI (para debug)
gui_trigger: compile_trigger vectors $(WAVE_DIR)
    $(VSIM) $(VSIM_GUI) tb_axis_trigger \
        +VECTORS_DIR=$(VECTORS_DIR) \
        -do "source questa/wave_trigger.do"

# Regresión completa
regression: sim_trigger sim_scope sim_rw
    @echo "========================================="
    @echo "REGRESIÓN COMPLETA"
    @echo "========================================="
    @grep -l "PASSED\|FAILED" $(LOG_DIR)/*.log
```

### 7.6 Diagrama de Flujo de Ejecución

```
┌─────────────────────────────────────────────────────────────────┐
│                    make regression                              │
└───────────────────────────┬─────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│ sim_trigger   │   │  sim_scope    │   │   sim_rw      │
└───────┬───────┘   └───────┬───────┘   └───────┬───────┘
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│compile_trigger│   │ compile_scope │   │  compile_rw   │
└───────┬───────┘   └───────┬───────┘   └───────┬───────┘
        │                   │                   │
        └───────────────────┼───────────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │  compile_pkg  │
                    └───────┬───────┘
                            │
                            ▼
                    ┌───────────────┐       ┌───────────────┐
                    │      lib      │       │   vectors     │
                    │  (vlib/vmap)  │       │   (Python)    │
                    └───────────────┘       └───────────────┘
```

### 7.7 Uso Típico

```bash
# Primera vez: setup completo
cd scripts
make clean
make all

# Desarrollo iterativo: un módulo
make gui_trigger    # Debug con waveforms

# CI/CD: regresión completa
make regression

# Ver resultados
cat logs/trigger_sim.log | grep -E "PASS|FAIL|Error"
```

---

## Apéndice A: Diagramas de Waveform (WaveDrom)

Los siguientes diagramas están en formato JSON compatible con WaveDrom (https://wavedrom.com). Pueden renderizarse en documentación HTML o herramientas compatibles.

### A.1 Transacción AXI-Stream Básica

```json
{ "signal": [
  { "name": "aclk",        "wave": "p.........", "period": 2 },
  { "name": "s_axis_tvalid", "wave": "0.1.....0.", "node": "..a.....b." },
  { "name": "s_axis_tready", "wave": "1.....0.1.", "node": "......c..." },
  { "name": "s_axis_tdata",  "wave": "x.2345.6.x", "data": ["D0", "D1", "D2", "D3", "D4"] },
  { "name": "s_axis_tlast",  "wave": "0.......1." }
],
  "edge": ["a~b Paquete de 5 beats", "c Backpressure"],
  "head": { "text": "AXI-Stream: Transferencia con backpressure" },
  "foot": { "text": "Handshake cuando tvalid=1 AND tready=1" }
}
```

**Interpretación:**
- Ciclos 1-4: Transferencias exitosas (tvalid ∧ tready)
- Ciclo 5: Stall por backpressure (tready=0)
- Ciclo 6: Última transferencia con tlast=1

### A.2 Detección de Trigger (Flanco Ascendente)

```json
{ "signal": [
  { "name": "aclk",       "wave": "p.......", "period": 2 },
  { "name": "tvalid",     "wave": "1.......", },
  { "name": "tdata",      "wave": "x2345678x", "data": ["400", "450", "480", "510", "550", "600", "650"] },
  { "name": "threshold",  "wave": "2.......", "data": ["500"] },
  { "name": "pipe[0]",    "wave": "x2345678x", "data": ["400", "450", "480", "510", "550", "600", "650"] },
  { "name": "pipe[1]",    "wave": "xx234567x", "data": ["400", "450", "480", "510", "550", "600"] },
  {},
  { "name": "event_det",  "wave": "0...1.0.." },
  { "name": "armed",      "wave": "1...0.1.." },
  { "name": "trigger_out","wave": "0...10...", "node": "....A...." }
],
  "edge": ["A Trigger detectado"],
  "head": { "text": "Trigger: Modo RISING, threshold=500" },
  "foot": { "text": "Latencia: 2 ciclos (pipeline)" },
  "config": { "hscale": 1.5 }
}
```

**Interpretación:**
- Ciclo 4: `pipe[1]=480 < 500` AND `pipe[0]=510 >= 500` → Evento detectado
- `trigger_out` se activa por 1 ciclo
- Re-armado automático cuando la señal vuelve a estar por debajo

### A.3 Captura del Scope

```json
{ "signal": [
  { "name": "aclk",       "wave": "p...............", "period": 2 },
  { "name": "state",      "wave": "2..3....4...5...", "data": ["ARMED", "TRIG'D", "TRANSFER", "DONE"] },
  { "name": "trigger_in", "wave": "0..10............" },
  {},
  { "name": "s_tvalid",   "wave": "1........0......", "node": ".........a" },
  { "name": "s_tdata",    "wave": "x23456789x......", "data": ["P-2", "P-1", "P0", "P1", "P2", "P3", "P4"] },
  {},
  { "name": "m_tvalid",   "wave": "0........1....0.", "node": ".........b" },
  { "name": "m_tdata",    "wave": "x........2345.x.", "data": ["P-2", "P-1", "P0", "P1"] },
  { "name": "m_tlast",    "wave": "0............10." }
],
  "edge": ["a~b Comienza transferencia"],
  "head": { "text": "Scope: pre=2, post=2 (ventana de 4 muestras)" },
  "config": { "hscale": 1.2 }
}
```

**Interpretación:**
- ARMED: Buffer circular captura pre-trigger
- TRIGGERED: Captura post_samples adicionales
- TRANSFER: Envía ventana completa (pre + post)
- tlast=1 marca fin de ventana

### A.4 Transacción AXI4 Write Burst

```json
{ "signal": [
  { "name": "aclk",      "wave": "p............", "period": 2 },
  {},
  ["AW Channel",
    { "name": "awvalid",  "wave": "0.10..........", "node": "..A" },
    { "name": "awready",  "wave": "1............." },
    { "name": "awaddr",   "wave": "x.2x..........", "data": ["0x1000"] },
    { "name": "awlen",    "wave": "x.2x..........", "data": ["3"] }
  ],
  {},
  ["W Channel",
    { "name": "wvalid",   "wave": "0..1.....0....", "node": "...B.....C" },
    { "name": "wready",   "wave": "1....0.1......", "node": ".....D" },
    { "name": "wdata",    "wave": "x..2345..x....", "data": ["D0", "D1", "D2", "D3"] },
    { "name": "wlast",    "wave": "0......1.0...." }
  ],
  {},
  ["B Channel",
    { "name": "bvalid",   "wave": "0........1.0..", "node": ".........E" },
    { "name": "bready",   "wave": "1............." },
    { "name": "bresp",    "wave": "x........2.x..", "data": ["OK"] }
  ]
],
  "edge": ["A AW handshake", "B~C W phase", "D Stall", "E Response"],
  "head": { "text": "AXI4: Burst de 4 beats con stall" },
  "foot": { "text": "wlast debe coincidir con beat #(awlen+1)" }
}
```

**Interpretación:**
- Fase AW: Dirección y longitud (awlen=3 → 4 beats)
- Fase W: Datos con wlast en el último beat
- Stall: wready=0 pausa la transferencia
- Fase B: Respuesta confirma escritura exitosa

### A.5 Flush por TLAST en RAM Writer

```json
{ "signal": [
  { "name": "aclk",       "wave": "p..........", "period": 2 },
  { "name": "state",      "wave": "2..3.4.5.2..", "data": ["IDLE", "CALC", "ADDR", "DATA", "IDLE"] },
  {},
  { "name": "s_tvalid",   "wave": "1....0......", },
  { "name": "s_tdata",    "wave": "x234x.......", "data": ["D0", "D1", "D2"] },
  { "name": "s_tlast",    "wave": "0..10.......", "node": "...A" },
  {},
  { "name": "fifo_level", "wave": "2345.4.3210.", "data": ["0", "1", "2", "3", "2", "1", "0"] },
  { "name": "fifo_empty", "wave": "1.0........1", "node": "...........B" },
  {},
  { "name": "awvalid",    "wave": "0....10.....", },
  { "name": "wvalid",     "wave": "0......1..0.", },
  { "name": "wlast",      "wave": "0........10." }
],
  "edge": ["A TLAST recibido", "B FIFO vacío (flush completo)"],
  "head": { "text": "RAM Writer: Flush por TLAST (3 datos < burst completo)" }
}
```

**Interpretación:**
- TLAST fuerza flush del FIFO aunque no haya burst completo
- El módulo genera un burst corto (awlen = datos_pendientes - 1)
- Verifica hipótesis H1: TLAST debe causar vaciado del FIFO

---

## Apéndice B: Módulos Auxiliares

### B.1 FifoModel (Python)

Modelo de FIFO interno para el RAM Writer. Simula comportamiento de FIFO asíncrono con detección de TLAST.

```python
class FifoModel:
    """
    Modelo de FIFO para simulación.
    
    Atributos:
        depth: Profundidad en palabras
        width: Ancho en bits
    
    Métodos:
        write(data, tlast): Escribe dato, retorna False si lleno
        read(): Lee dato, retorna None si vacío
        read_burst(count): Lee múltiples datos
    
    Propiedades:
        is_full, is_empty: Estados del FIFO
        level: Ocupación actual
        has_complete_packet: True si hay TLAST pendiente
    """
    
    def __init__(self, depth: int = 512, width: int = 32):
        self._depth = depth
        self._width = width
        self._data = deque(maxlen=depth)
        self._tlast_positions = []
        self._write_count = 0
    
    def reset(self):
        self._data.clear()
        self._tlast_positions.clear()
        self._write_count = 0
    
    def write(self, data: int, tlast: bool = False) -> bool:
        if len(self._data) >= self._depth:
            return False
        
        self._data.append(data)
        self._write_count += 1
        
        if tlast:
            self._tlast_positions.append(len(self._data) - 1)
        
        return True
    
    def read(self) -> Optional[int]:
        if len(self._data) == 0:
            return None
        
        data = self._data.popleft()
        self._tlast_positions = [p - 1 for p in self._tlast_positions if p > 0]
        return data
    
    def read_burst(self, count: int) -> List[int]:
        result = []
        for _ in range(min(count, len(self._data))):
            data = self.read()
            if data is not None:
                result.append(data)
        return result
    
    @property
    def is_full(self) -> bool:
        return len(self._data) >= self._depth
    
    @property
    def is_empty(self) -> bool:
        return len(self._data) == 0
    
    @property
    def level(self) -> int:
        return len(self._data)
    
    @property
    def has_complete_packet(self) -> bool:
        return len(self._tlast_positions) > 0
```

### B.2 Axi4WriteTransaction (Python)

Representa una transacción de escritura AXI4 completa.

```python
@dataclass
class Axi4WriteTransaction:
    """
    Transacción de escritura AXI4.
    
    Atributos:
        address: Dirección base (AWADDR)
        data: Lista de datos a escribir
        burst_len: Número de beats (AWLEN + 1)
        burst_size: Tamaño de beat en log2 bytes (AWSIZE)
        burst_type: Tipo de burst (1=INCR)
        response: Respuesta recibida (BRESP)
    
    Propiedades:
        total_bytes: Bytes totales de la transacción
        end_address: Dirección final
    """
    
    address: int
    data: List[int]
    burst_len: int
    burst_size: int = 3      # 8 bytes (64 bits)
    burst_type: int = 1      # INCR
    response: Optional[int] = None
    
    @property
    def total_bytes(self) -> int:
        return self.burst_len * (1 << self.burst_size)
    
    @property
    def end_address(self) -> int:
        return self.address + self.total_bytes
    
    def crosses_4kb(self) -> bool:
        """Verifica si la transacción cruza un límite de 4KB."""
        start_4kb = self.address & ~0xFFF
        end_4kb = (self.end_address - 1) & ~0xFFF
        return start_4kb != end_4kb
```

### B.3 TriggerEvent (Python)

Representa un evento de trigger detectado.

```python
@dataclass
class TriggerEvent:
    """
    Evento de trigger detectado.
    
    Atributos:
        sample_index: Índice de la muestra donde ocurrió
        sample_value: Valor de la muestra actual
        prev_value: Valor de la muestra anterior
        mode: Modo de detección que lo activó
    """
    
    sample_index: int
    sample_value: int
    prev_value: int
    mode: TriggerMode
    
    def __str__(self) -> str:
        return (f"TriggerEvent(idx={self.sample_index}, "
                f"val={self.sample_value}, prev={self.prev_value}, "
                f"mode={self.mode.name})")
```

### B.4 CapturedWindow (Python)

Representa una ventana de datos capturada por el Scope.

```python
@dataclass
class CapturedWindow:
    """
    Ventana de datos capturada.
    
    Atributos:
        samples: Array de muestras capturadas
        trigger_index: Índice del trigger dentro de la ventana
        pre_samples: Número de muestras antes del trigger
        post_samples: Número de muestras después del trigger
    
    Métodos:
        get_pre_trigger_data(): Retorna solo pre-trigger
        get_post_trigger_data(): Retorna solo post-trigger
    """
    
    samples: np.ndarray
    trigger_index: int
    pre_samples: int
    post_samples: int
    
    @property
    def total_samples(self) -> int:
        return len(self.samples)
    
    def get_pre_trigger_data(self) -> np.ndarray:
        return self.samples[:self.trigger_index]
    
    def get_post_trigger_data(self) -> np.ndarray:
        return self.samples[self.trigger_index:]
    
    def verify_integrity(self) -> bool:
        """Verifica que la ventana tenga el tamaño esperado."""
        expected = self.pre_samples + self.post_samples
        return len(self.samples) == expected
```

### B.5 axis_transaction_t (SystemVerilog)

Estructura de transacción para adaptadores del testbench.

```systemverilog
typedef struct packed {
    logic [15:0]           data;       // Payload
    logic                  last;       // Fin de paquete
    logic                  valid;      // Dato válido
    logic [31:0]           timestamp;  // Ciclo de reloj
    logic [$clog2(256)-1:0] packet_id; // ID de paquete
} axis_transaction_t;

// Funciones de utilidad
function automatic axis_transaction_t create_axis_data(
    input logic [15:0] data,
    input logic last = 1'b0
);
    axis_transaction_t txn;
    txn.data = data;
    txn.last = last;
    txn.valid = 1'b1;
    txn.timestamp = $time;
    txn.packet_id = 0;
    return txn;
endfunction

function automatic string axis_txn_to_string(axis_transaction_t txn);
    return $sformatf("AXIS[data=%04X, last=%b, t=%0d]",
                     txn.data, txn.last, txn.timestamp);
endfunction
```

---

## Apéndice C: Glosario de Transacciones

### C.1 Terminología AXI-Stream

| Término | Definición |
|---------|------------|
| **Beat** | Transferencia elemental (tvalid=1 ∧ tready=1) |
| **Packet** | Secuencia de beats terminada con tlast=1 |
| **Frame** | Sinónimo de packet en algunos contextos |
| **Backpressure** | Condición donde tready=0 detiene el flujo |
| **Handshake** | Momento donde tvalid=1 ∧ tready=1 |
| **Stall** | Ciclos donde tvalid=1 pero tready=0 |
| **Bubble** | Ciclos donde tvalid=0 (gap en datos) |
| **Throughput** | Beats por unidad de tiempo |

### C.2 Terminología AXI4

| Término | Definición |
|---------|------------|
| **Burst** | Secuencia de transferencias con una dirección |
| **Beat** | Transferencia individual dentro de un burst |
| **INCR** | Burst con direcciones incrementales |
| **WRAP** | Burst con direcciones que "envuelven" |
| **FIXED** | Burst con dirección fija (FIFO-like) |
| **Outstanding** | Transacciones iniciadas no completadas |
| **In-order** | Respuestas en mismo orden que solicitudes |
| **Out-of-order** | Respuestas en orden diferente |
| **Narrow burst** | Burst que no usa todo el ancho del bus |

### C.3 Estados de Verificación

| Estado | Significado | Color en waveform |
|--------|-------------|-------------------|
| IDLE | Sin actividad | Gris |
| PENDING | Esperando respuesta | Amarillo |
| COMPLETE | Finalizado exitosamente | Verde |
| ERROR | Violación detectada | Rojo |
| TIMEOUT | Tiempo excedido | Naranja |

### C.4 Métricas de Performance

| Métrica | Definición | Fórmula |
|---------|------------|---------|
| Throughput | Datos/tiempo | bytes / (ciclos × T_clk) |
| Efficiency | Utilización | beats_útiles / ciclos_totales |
| Latency | Solicitud→respuesta | ciclos × T_clk |
| Stall rate | Frecuencia de pausa | ciclos_stall / ciclos_totales |
| Bandwidth | Capacidad teórica | bits × frecuencia |

---

## Referencias

1. ARM IHI 0022E: AMBA AXI and ACE Protocol Specification
2. ARM IHI 0051A: AMBA AXI4-Stream Protocol Specification
3. Xilinx UG585: Zynq-7000 SoC Technical Reference Manual
4. Pavel Demin: Red Pitaya Notes (https://github.com/pavel-demin/red-pitaya-notes)
5. WaveDrom: Digital Timing Diagram Editor (https://wavedrom.com)
