# Módulos del Sistema MCPHA

## Descripción Funcional y Verificación

**Autor:** Lorenzo Cabrera Blanch  
**Institución:** Instituto Balseiro / CNEA  
**Proyecto:** Analizador Multicanal de Altura de Pulsos sobre Red Pitaya

---

## Índice

1. [Introducción](#1-introducción)
2. [Módulo axis_trigger](#2-módulo-axis_trigger)
3. [Módulo axis_scope](#3-módulo-axis_scope)
4. [Módulo axis_ram_writer](#4-módulo-axis_ram_writer)
5. [Apéndice A: Interpretación de Waveforms](#apéndice-a-interpretación-de-waveforms)
6. [Apéndice B: Resumen de Casos de Test](#apéndice-b-resumen-de-casos-de-test)

---

## 1. Introducción

Este documento describe los módulos de procesamiento de señales del sistema MCPHA (Multi-Channel Pulse Height Analyzer). Cada sección presenta:

- Descripción funcional del módulo
- Modelo de referencia en Python (ESL)
- Diagrama de bloques RTL
- Casos de test empleados
- Guía de interpretación de waveforms

### 1.1 Convenciones

| Símbolo | Significado |
|---------|-------------|
| `→` | Transición de estado |
| `↑` | Flanco ascendente |
| `↓` | Flanco descendente |
| `[n]` | Muestra en el instante n |
| `[n-1]` | Muestra anterior |

### 1.2 Interfaces Comunes

Todos los módulos utilizan interfaces AXI-Stream para el flujo de datos:

| Señal | Dirección | Descripción |
|-------|-----------|-------------|
| `tdata` | M→S | Datos de la muestra |
| `tvalid` | M→S | Indica dato válido |
| `tready` | S→M | Indica receptor listo |
| `tlast` | M→S | Marca fin de paquete |

El handshake se completa cuando `tvalid=1` y `tready=1` simultáneamente.

---

## 2. Módulo axis_trigger

### 2.1 Descripción Funcional

El módulo `axis_trigger` detecta eventos de cruce de umbral en el flujo de datos de entrada. Soporta cuatro modos de operación:

| Modo | Condición de disparo |
|------|---------------------|
| `RISING` | `sample[n-1] < threshold` AND `sample[n] >= threshold` |
| `FALLING` | `sample[n-1] >= threshold` AND `sample[n] < threshold` |
| `BOTH` | Cualquier cruce del umbral |
| `LEVEL` | `sample[n] >= threshold` (continuo) |

### 2.2 Modelo Python (ESL)

```python
"""
trigger_model.py - Modelo de referencia para axis_trigger
"""
from enum import IntEnum
from dataclasses import dataclass
from typing import List, Tuple

class TriggerMode(IntEnum):
    """Modos de detección del trigger."""
    RISING = 0   # Flanco ascendente
    FALLING = 1  # Flanco descendente
    BOTH = 2     # Ambos flancos
    LEVEL = 3    # Por nivel

@dataclass
class TriggerConfig:
    """Configuración del trigger."""
    enable: bool = True
    threshold: int = 0
    mode: TriggerMode = TriggerMode.RISING

class TriggerModel:
    """
    Modelo funcional del detector de trigger.
    
    Este modelo NO tiene noción de ciclos de reloj.
    Opera puramente a nivel de transacciones (muestras).
    """
    
    def __init__(self, config: TriggerConfig):
        self.config = config
        self.prev_sample = 0
        self.trigger_count = 0
    
    def process_sample(self, sample: int) -> Tuple[int, bool]:
        """
        Procesa una muestra y determina si hay trigger.
        
        Args:
            sample: Valor de la muestra actual (entero con signo)
            
        Returns:
            Tupla (sample, trigger_fired)
        """
        trigger = False
        
        if self.config.enable:
            if self.config.mode == TriggerMode.RISING:
                # Trigger en cruce ascendente del umbral
                trigger = (self.prev_sample < self.config.threshold and 
                          sample >= self.config.threshold)
                          
            elif self.config.mode == TriggerMode.FALLING:
                # Trigger en cruce descendente del umbral
                trigger = (self.prev_sample >= self.config.threshold and 
                          sample < self.config.threshold)
                          
            elif self.config.mode == TriggerMode.BOTH:
                # Trigger en cualquier cruce
                crossed_up = (self.prev_sample < self.config.threshold and 
                             sample >= self.config.threshold)
                crossed_down = (self.prev_sample >= self.config.threshold and 
                               sample < self.config.threshold)
                trigger = crossed_up or crossed_down
                
            elif self.config.mode == TriggerMode.LEVEL:
                # Trigger mientras esté por encima del umbral
                trigger = sample >= self.config.threshold
        
        if trigger:
            self.trigger_count += 1
            
        self.prev_sample = sample
        return (sample, trigger)
    
    def process_stream(self, samples: List[int]) -> List[Tuple[int, bool]]:
        """
        Procesa un stream completo de muestras.
        
        Args:
            samples: Lista de muestras
            
        Returns:
            Lista de tuplas (sample, trigger_fired)
        """
        return [self.process_sample(s) for s in samples]
    
    def get_trigger_indices(self, samples: List[int]) -> List[int]:
        """
        Retorna los índices donde ocurrieron triggers.
        
        Args:
            samples: Lista de muestras
            
        Returns:
            Lista de índices con trigger
        """
        results = self.process_stream(samples)
        return [i for i, (_, trig) in enumerate(results) if trig]


def generate_test_vectors(
    samples: List[int],
    config: TriggerConfig,
    output_prefix: str
) -> None:
    """
    Genera archivos .hex para simulación RTL.
    
    Args:
        samples: Lista de muestras de entrada
        config: Configuración del trigger
        output_prefix: Prefijo para archivos de salida
    """
    model = TriggerModel(config)
    results = model.process_stream(samples)
    
    # Escribir estímulos
    with open(f"{output_prefix}_stimulus.hex", 'w') as f:
        for sample in samples:
            # Formato: 16 bits hexadecimal
            f.write(f"{sample & 0xFFFF:04X}\n")
    
    # Escribir esperados (datos de salida)
    with open(f"{output_prefix}_expected.hex", 'w') as f:
        for sample, _ in results:
            f.write(f"{sample & 0xFFFF:04X}\n")
    
    # Escribir índices de trigger
    trigger_indices = [i for i, (_, t) in enumerate(results) if t]
    with open(f"{output_prefix}_triggers.txt", 'w') as f:
        for idx in trigger_indices:
            f.write(f"{idx}\n")
    
    # Escribir configuración
    with open(f"{output_prefix}_config.txt", 'w') as f:
        f.write(f"threshold={config.threshold}\n")
        f.write(f"mode={config.mode.name}\n")
        f.write(f"enable={int(config.enable)}\n")
```

### 2.3 Diagrama de Bloques RTL

El módulo RTL implementa la lógica del modelo con pipeline de 2 etapas:

```
                    ┌─────────────────────────────────────────────────────┐
                    │                    axis_trigger                     │
                    │                                                     │
  s_axis_tdata ────►│  ┌──────────┐   ┌──────────┐   ┌──────────────┐    │
  s_axis_tvalid ───►│  │ Registro │──►│ Registro │──►│  Comparador  │    │
                    │  │  [n-1]   │   │   [n]    │   │ vs Threshold │    │
                    │  └──────────┘   └──────────┘   └──────┬───────┘    │
                    │                                       │            │
                    │  ┌──────────────┐   ┌────────────────┐│            │
                    │  │Configuración │──►│ Selector Modo  ││            │
                    │  │mode,threshold│   │RISE/FALL/BOTH  │◄┘           │
                    │  └──────────────┘   └───────┬────────┘             │
                    │                             │                      │
                    │                             ▼                      │──► trigger_out
                    │                      ┌────────────┐                │
                    │                      │  Trigger   │                │──► m_axis_tdata
                    │                      │   Output   │                │
                    │                      └────────────┘                │
                    └─────────────────────────────────────────────────────┘
```

### 2.4 Casos de Test

| Test | Descripción | Verificación |
|------|-------------|--------------|
| `test_rising_ramp` | Rampa 0→1023, threshold=500 | Un trigger en cruce |
| `test_falling_ramp` | Rampa 1023→0, threshold=500 | Un trigger en cruce |
| `test_both_sine` | Sinusoide ±800, threshold=0 | Múltiples triggers |
| `test_level_pulse` | Pulso de 100 muestras | Trigger continuo |
| `test_disabled` | Enable=0 | Sin triggers |
| `test_noise` | Ruido aleatorio | Verificar timing |

#### Ejemplo: test_rising_ramp

```python
# Generar rampa ascendente
samples = list(range(1024))
config = TriggerConfig(enable=True, threshold=500, mode=TriggerMode.RISING)

model = TriggerModel(config)
triggers = model.get_trigger_indices(samples)

# Esperado: un único trigger en índice 500
assert triggers == [500], f"Expected [500], got {triggers}"
```

---

## 3. Módulo axis_scope

### 3.1 Descripción Funcional

El módulo `axis_scope` implementa un buffer de captura estilo osciloscopio. Almacena muestras en un buffer circular y, al recibir un trigger, captura una ventana de datos con muestras pre y post trigger.

#### Estados de la FSM

| Estado | Descripción |
|--------|-------------|
| `IDLE` | Módulo deshabilitado, esperando configuración |
| `ARMED` | Buffer circular activo, esperando trigger |
| `TRIGGERED` | Capturando muestras post-trigger |
| `TRANSFER` | Enviando datos capturados por AXI-Stream |
| `DONE` | Captura completa, esperando lectura de status |

#### Secuencia de operación

```
     ┌──────┐  arm   ┌────────┐  trigger  ┌───────────┐
     │ IDLE │───────►│ ARMED  │──────────►│ TRIGGERED │
     └──────┘        └────────┘           └─────┬─────┘
        ▲                                       │
        │                                       │ post_samples
        │                                       │ complete
        │            ┌────────┐           ┌─────▼─────┐
        └────────────│  DONE  │◄──────────│ TRANSFER  │
                     └────────┘  TLAST    └───────────┘
```

### 3.2 Modelo Python (ESL)

```python
"""
scope_model.py - Modelo de referencia para axis_scope
"""
from enum import IntEnum
from dataclasses import dataclass, field
from typing import List, Optional
from collections import deque

class ScopeState(IntEnum):
    """Estados de la máquina de estados."""
    IDLE = 0
    ARMED = 1
    TRIGGERED = 2
    TRANSFER = 3
    DONE = 4

@dataclass
class ScopeConfig:
    """Configuración del scope."""
    enable: bool = True
    pre_samples: int = 100   # Muestras antes del trigger
    post_samples: int = 200  # Muestras después del trigger

@dataclass
class ScopeStatus:
    """Estado actual del scope."""
    state: ScopeState = ScopeState.IDLE
    armed: bool = False
    triggered: bool = False
    done: bool = False
    sample_count: int = 0

class ScopeModel:
    """
    Modelo funcional del buffer de captura.
    
    Implementa un buffer circular para pre-trigger y
    captura lineal para post-trigger.
    """
    
    def __init__(self, config: ScopeConfig, buffer_depth: int = 4096):
        self.config = config
        self.buffer_depth = buffer_depth
        
        # Buffer circular para pre-trigger
        self.circular_buffer: deque = deque(maxlen=buffer_depth)
        
        # Buffer de captura
        self.capture_buffer: List[int] = []
        
        # Estado
        self.state = ScopeState.IDLE
        self.post_count = 0
        self.trigger_index = -1
    
    def arm(self) -> None:
        """Arma el scope para esperar trigger."""
        if self.config.enable:
            self.state = ScopeState.ARMED
            self.circular_buffer.clear()
            self.capture_buffer = []
            self.post_count = 0
            self.trigger_index = -1
    
    def process_sample(self, sample: int, trigger: bool) -> Optional[int]:
        """
        Procesa una muestra según el estado actual.
        
        Args:
            sample: Valor de la muestra
            trigger: Señal de trigger
            
        Returns:
            Muestra de salida durante TRANSFER, None en otros casos
        """
        if self.state == ScopeState.IDLE:
            return None
            
        elif self.state == ScopeState.ARMED:
            # Agregar al buffer circular
            self.circular_buffer.append(sample)
            
            if trigger:
                # Trigger detectado
                self.state = ScopeState.TRIGGERED
                self.trigger_index = len(self.circular_buffer) - 1
                self.post_count = 1
                
                # Las muestras de pre-trigger ya están en el buffer
            return None
            
        elif self.state == ScopeState.TRIGGERED:
            # Capturando post-trigger
            self.circular_buffer.append(sample)
            self.post_count += 1
            
            if self.post_count >= self.config.post_samples:
                # Captura completa
                self.state = ScopeState.TRANSFER
                self._prepare_output()
            return None
            
        elif self.state == ScopeState.TRANSFER:
            # Este estado se maneja en get_output()
            return None
            
        return None
    
    def _prepare_output(self) -> None:
        """Prepara el buffer de salida con pre y post samples."""
        # Calcular índices
        total_samples = self.config.pre_samples + self.config.post_samples
        buffer_list = list(self.circular_buffer)
        
        # El trigger está en trigger_index
        # Pre: desde (trigger_index - pre_samples) hasta trigger_index
        # Post: desde trigger_index hasta (trigger_index + post_samples)
        
        start_idx = max(0, len(buffer_list) - total_samples)
        self.capture_buffer = buffer_list[start_idx:]
    
    def get_output(self) -> List[int]:
        """
        Obtiene los datos capturados.
        
        Returns:
            Lista de muestras capturadas (pre + post trigger)
        """
        if self.state == ScopeState.TRANSFER:
            self.state = ScopeState.DONE
            return self.capture_buffer
        return []
    
    def get_status(self) -> ScopeStatus:
        """Retorna el estado actual."""
        return ScopeStatus(
            state=self.state,
            armed=(self.state == ScopeState.ARMED),
            triggered=(self.state in [ScopeState.TRIGGERED, 
                                       ScopeState.TRANSFER, 
                                       ScopeState.DONE]),
            done=(self.state == ScopeState.DONE),
            sample_count=len(self.capture_buffer)
        )


def simulate_acquisition(
    samples: List[int],
    trigger_indices: List[int],
    config: ScopeConfig
) -> List[int]:
    """
    Simula una adquisición completa.
    
    Args:
        samples: Stream de muestras de entrada
        trigger_indices: Índices donde ocurre trigger
        config: Configuración del scope
        
    Returns:
        Muestras capturadas
    """
    scope = ScopeModel(config)
    scope.arm()
    
    for i, sample in enumerate(samples):
        trigger = i in trigger_indices
        scope.process_sample(sample, trigger)
        
        if scope.state == ScopeState.TRANSFER:
            break
    
    return scope.get_output()
```

### 3.3 Diagrama de Bloques RTL

```
                ┌───────────────────────────────────────────────────────────┐
                │                       axis_scope                          │
                │                                                           │
  s_axis ──────►│  ┌──────────────────┐                                     │
                │  │   Buffer Circular │                                    │
                │  │      (BRAM)       │                                    │
                │  │   PRE-TRIGGER     │──────┐                             │
                │  └──────────────────┘      │      ┌─────────┐             │
                │           ▲                 ├─────►│   MUX   │────────────►│──► m_axis
  trigger_in ──►│           │                 │      │Pre/Post │             │    + TLAST
                │  ┌────────┴───────┐        │      └─────────┘             │
                │  │      FSM       │        │           ▲                  │
                │  │ IDLE→ARMED→    │────────┘           │                  │
                │  │ TRIGGERED→     │                    │                  │
                │  │ TRANSFER→DONE  │    ┌───────────────┘                  │
                │  └────────────────┘    │                                  │
                │           ▲            │  ┌─────────────┐                 │
                │           │            │  │   Captura   │                 │
                │  ┌────────┴───────┐    └──│ POST-TRIGGER│                 │
                │  │  Configuración │       │ (contador)  │                 │
                │  │  pre_samples   │       └─────────────┘                 │
                │  │  post_samples  │                                       │──► status
                │  └────────────────┘                                       │
                └───────────────────────────────────────────────────────────┘
```

### 3.4 Casos de Test

| Test | Descripción | Verificación |
|------|-------------|--------------|
| `test_basic_capture` | pre=100, post=200, trigger@200 | 300 muestras correctas |
| `test_pre_only` | pre=150, post=0 | Solo muestras pre-trigger |
| `test_post_only` | pre=0, post=150 | Solo muestras post-trigger |
| `test_early_trigger` | Trigger antes de llenar pre | Captura lo disponible |
| `test_multiple_triggers` | Varios triggers | Solo responde al primero |
| `test_backpressure` | m_axis_tready intermitente | Sin pérdida de datos |
| `test_state_transitions` | Verificar FSM | Transiciones correctas |

#### Ejemplo: test_basic_capture

```python
# Configuración
config = ScopeConfig(enable=True, pre_samples=100, post_samples=200)

# Stream de entrada: 500 muestras, trigger en índice 200
samples = list(range(500))
trigger_indices = [200]

# Simular
captured = simulate_acquisition(samples, trigger_indices, config)

# Verificar
assert len(captured) == 300, f"Expected 300, got {len(captured)}"

# Primera muestra debe ser índice 100 (200 - 100 pre)
assert captured[0] == 100, f"Expected 100, got {captured[0]}"

# Última muestra debe ser índice 399 (200 + 199 post)
assert captured[-1] == 399, f"Expected 399, got {captured[-1]}"
```

---

## 4. Módulo axis_ram_writer

### 4.1 Descripción Funcional

El módulo `axis_ram_writer` escribe datos recibidos por AXI-Stream a memoria DDR utilizando el protocolo AXI4 Master. Implementa un FIFO interno para desacoplar la velocidad de entrada de la de escritura a memoria.

#### Características principales

- FIFO interno de 1024 posiciones
- Bursts AXI4 de hasta 256 beats
- Verificación automática de límite de 4KB
- Soporte para buffer circular en memoria

#### Estados de la FSM

| Estado | Descripción |
|--------|-------------|
| `IDLE` | Esperando datos en el FIFO |
| `CALC` | Calculando dirección y longitud de burst |
| `ADDR` | Enviando dirección (canal AW) |
| `DATA` | Transfiriendo datos (canal W) |
| `RESP` | Esperando respuesta (canal B) |
| `ERROR` | Estado de error recuperable |

### 4.2 Modelo Python (ESL)

```python
"""
ram_writer_model.py - Modelo de referencia para axis_ram_writer
"""
from enum import IntEnum
from dataclasses import dataclass
from typing import List, Tuple, Dict
from collections import deque

class WriterState(IntEnum):
    """Estados de la máquina de estados."""
    IDLE = 0
    CALC = 1
    ADDR = 2
    DATA = 3
    RESP = 4
    ERROR = 5

@dataclass
class WriterConfig:
    """Configuración del escritor."""
    enable: bool = True
    base_addr: int = 0x10000000
    buffer_size: int = 65536  # 64 KB

@dataclass
class WriterStatus:
    """Estado actual del escritor."""
    state: WriterState = WriterState.IDLE
    write_ptr: int = 0
    bytes_written: int = 0
    overflow: bool = False

@dataclass
class AXI4Transaction:
    """Representa una transacción AXI4."""
    addr: int
    data: List[int]
    burst_len: int  # AWLEN (0-255)
    burst_size: int  # AWSIZE (bytes per beat = 2^size)

class RAMWriterModel:
    """
    Modelo funcional del escritor de RAM.
    
    Simula el comportamiento del módulo sin timing preciso.
    """
    
    # Constantes
    AXI_DATA_WIDTH = 64  # bits
    AXI_BYTES_PER_BEAT = 8
    MAX_BURST_LEN = 16  # Configurable
    BOUNDARY_4KB = 4096
    
    def __init__(self, config: WriterConfig):
        self.config = config
        
        # FIFO interno
        self.fifo: deque = deque()
        
        # Estado
        self.state = WriterState.IDLE
        self.write_ptr = 0
        self.bytes_written = 0
        
        # Transacciones generadas
        self.transactions: List[AXI4Transaction] = []
        
        # Memoria simulada
        self.memory: Dict[int, int] = {}
    
    def push_data(self, data: int, last: bool = False) -> None:
        """
        Agrega datos al FIFO interno.
        
        Args:
            data: Dato de 16 bits
            last: Indica fin de stream (TLAST)
        """
        if self.config.enable:
            self.fifo.append((data, last))
    
    def process(self) -> List[AXI4Transaction]:
        """
        Procesa el FIFO y genera transacciones AXI4.
        
        Returns:
            Lista de transacciones generadas
        """
        transactions = []
        
        while len(self.fifo) >= self.MAX_BURST_LEN or self._has_tlast():
            txn = self._build_transaction()
            if txn:
                transactions.append(txn)
                self._execute_transaction(txn)
        
        self.transactions.extend(transactions)
        return transactions
    
    def _has_tlast(self) -> bool:
        """Verifica si hay TLAST en el FIFO."""
        return any(last for _, last in self.fifo)
    
    def _build_transaction(self) -> AXI4Transaction:
        """Construye una transacción AXI4."""
        if len(self.fifo) == 0:
            return None
        
        # Calcular cuántos beats podemos hacer
        available = len(self.fifo)
        
        # Verificar límite de 4KB
        addr = self.config.base_addr + self.write_ptr
        bytes_to_4kb = self.BOUNDARY_4KB - (addr % self.BOUNDARY_4KB)
        max_beats_4kb = bytes_to_4kb // self.AXI_BYTES_PER_BEAT
        
        # Tomar el mínimo
        burst_len = min(available, self.MAX_BURST_LEN, max_beats_4kb)
        
        # Extraer datos del FIFO
        data = []
        has_last = False
        for _ in range(burst_len):
            if self.fifo:
                d, last = self.fifo.popleft()
                data.append(d)
                has_last = has_last or last
        
        return AXI4Transaction(
            addr=addr,
            data=data,
            burst_len=burst_len - 1,  # AWLEN = beats - 1
            burst_size=3  # 8 bytes per beat (2^3)
        )
    
    def _execute_transaction(self, txn: AXI4Transaction) -> None:
        """Ejecuta una transacción (escribe en memoria simulada)."""
        addr = txn.addr
        bytes_per_beat = 1 << txn.burst_size
        
        for data in txn.data:
            # Escribir en memoria (simplificado)
            self.memory[addr] = data
            addr += bytes_per_beat
            self.bytes_written += bytes_per_beat
        
        # Actualizar puntero (con wrap-around)
        self.write_ptr = (self.write_ptr + len(txn.data) * bytes_per_beat)
        self.write_ptr = self.write_ptr % self.config.buffer_size
    
    def flush(self) -> List[AXI4Transaction]:
        """
        Fuerza escritura de datos pendientes.
        
        Usado cuando se recibe TLAST.
        """
        transactions = []
        
        while len(self.fifo) > 0:
            txn = self._build_transaction()
            if txn:
                transactions.append(txn)
                self._execute_transaction(txn)
        
        self.transactions.extend(transactions)
        return transactions
    
    def get_status(self) -> WriterStatus:
        """Retorna el estado actual."""
        return WriterStatus(
            state=self.state,
            write_ptr=self.write_ptr,
            bytes_written=self.bytes_written,
            overflow=(self.write_ptr >= self.config.buffer_size)
        )
    
    def verify_4kb_boundary(self, txn: AXI4Transaction) -> bool:
        """
        Verifica que una transacción no cruce el límite de 4KB.
        
        Args:
            txn: Transacción a verificar
            
        Returns:
            True si es válida, False si cruza el límite
        """
        start_addr = txn.addr
        bytes_per_beat = 1 << txn.burst_size
        end_addr = start_addr + (txn.burst_len + 1) * bytes_per_beat
        
        # Verificar si cruza límite de 4KB
        start_4kb = start_addr // self.BOUNDARY_4KB
        end_4kb = (end_addr - 1) // self.BOUNDARY_4KB
        
        return start_4kb == end_4kb


def verify_transactions(transactions: List[AXI4Transaction]) -> List[str]:
    """
    Verifica una lista de transacciones AXI4.
    
    Returns:
        Lista de errores encontrados (vacía si todo OK)
    """
    errors = []
    model = RAMWriterModel(WriterConfig())
    
    for i, txn in enumerate(transactions):
        # Verificar límite de 4KB
        if not model.verify_4kb_boundary(txn):
            errors.append(f"Transaction {i}: crosses 4KB boundary")
        
        # Verificar burst_len válido
        if txn.burst_len > 255:
            errors.append(f"Transaction {i}: burst_len > 255")
        
        # Verificar alineación
        bytes_per_beat = 1 << txn.burst_size
        if txn.addr % bytes_per_beat != 0:
            errors.append(f"Transaction {i}: address not aligned")
    
    return errors
```

### 4.3 Diagrama de Bloques RTL

```
            ┌────────────────────────────────────────────────────────────────────┐
            │                        axis_ram_writer                             │
            │                                                                    │
s_axis_tdata ──►│  ┌───────────┐   ┌─────────────────┐   ┌────────────┐          │
s_axis_tlast ──►│  │  INPUT    │   │     Burst       │   │ AW Channel │──────────►│──► m_axi_aw*
            │  │   FIFO     │──►│    Builder      │──►│            │          │
            │  │ (1024 deep)│   │                 │   ├────────────┤          │
            │  └───────────┘   │  AWLEN calc     │   │ W Channel  │──────────►│──► m_axi_w*
            │                  │  4KB check      │──►│            │          │
            │                  │                 │   ├────────────┤          │
            │                  └────────┬────────┘   │ B Channel  │◄─────────│◄── m_axi_b*
            │                           │            └────────────┘          │
            │                           │                   │                │
            │                  ┌────────▼────────┐         │                │
            │                  │      FSM        │◄────────┘                │
            │                  │ IDLE→CALC→ADDR  │                          │
            │                  │ →DATA→RESP      │                          │
            │                  └────────┬────────┘                          │
            │                           │                                   │
            │  ┌───────────────┐        │         ┌───────────────┐         │
            │  │ Configuración │────────┘         │    Status     │─────────►│──► status
            │  │ base_addr     │                  │ write_ptr     │         │
            │  │ buffer_size   │                  │ bytes_written │         │
            │  └───────────────┘                  └───────────────┘         │
            └────────────────────────────────────────────────────────────────┘
```

### 4.4 Casos de Test

| Test | Descripción | Verificación |
|------|-------------|--------------|
| `test_basic_write` | 100 muestras con TLAST | Datos en memoria correctos |
| `test_burst_alignment` | 500 muestras | Múltiples bursts, sin cruce 4KB |
| `test_tlast_flush` | 10 muestras (< burst) | Flush inmediato con TLAST |
| `test_backpressure` | AWREADY/WREADY intermitente | Sin pérdida de datos |
| `test_4kb_boundary` | Datos cerca de límite | Burst se divide correctamente |
| `test_max_burst` | 256 beats consecutivos | AWLEN=255 correcto |

#### Ejemplo: test_4kb_boundary

```python
# Configuración cerca del límite de 4KB
config = WriterConfig(
    enable=True,
    base_addr=0x10000F00,  # 256 bytes antes del límite
    buffer_size=65536
)

model = RAMWriterModel(config)

# Agregar 100 muestras (más de lo que cabe antes del límite)
for i in range(100):
    model.push_data(i, last=(i == 99))

transactions = model.flush()

# Verificar que ninguna transacción cruza el límite
errors = verify_transactions(transactions)
assert len(errors) == 0, f"Errors: {errors}"

# Verificar que hubo múltiples transacciones (split por 4KB)
assert len(transactions) >= 2, "Expected split at 4KB boundary"
```

### 4.5 Hipótesis de Bugs Conocidos

El módulo presenta un bug donde no escribe todos los datos esperados. Las hipótesis bajo verificación son:

| ID | Hipótesis | SVA Assertion |
|----|-----------|---------------|
| H1 | TLAST no dispara flush del FIFO | `p_tlast_causes_flush` |
| H2 | Último burst incompleto no se escribe | `p_aw_pending_positive` |
| H3 | Límite de 4KB causa pérdida de datos | `p_4kb_boundary` |
| H4 | Backpressure AXI4 causa deadlock | `p_no_deadlock` |

---

## Apéndice A: Interpretación de Waveforms

Este apéndice describe cómo interpretar las formas de onda en la simulación RTL a nivel de transacciones.

### A.1 Señales AXI-Stream

#### Handshake básico

```
         ┌───┐   ┌───┐   ┌───┐   ┌───┐
 clk   ──┘   └───┘   └───┘   └───┘   └──

       ────────┬───────────────────────
 tdata   XXXX  │  D0  │  D1  │  D2  │
       ────────┴───────────────────────

              ┌───────────────────┐
 tvalid ──────┘                   └────
              
              ┌───────┐       ┌───┐
 tready ──────┘       └───────┘   └────

              │   T   │       │ T │
              └───────┘       └───┘
                 ▲               ▲
                 │               │
              Transferencia   Transferencia
                  D0              D2
```

**Interpretación:**
- `T` = Transferencia válida (tvalid=1 AND tready=1)
- D1 NO se transfiere porque tready=0 durante ese ciclo
- El dato permanece estable mientras espera tready

#### TLAST marca fin de paquete

```
       ────────┬───────────────┬───────
 tdata   XXXX  │  D0  │  D1  │  D2  │
       ────────┴───────────────┴───────

              ┌───────────────────────┐
 tvalid ──────┘                       └

       ────────────────────────────────
 tready 

                            ┌───┐
 tlast  ────────────────────┘   └──────
                            │   │
                            └───┘
                              ▲
                              │
                         Fin de paquete
```

### A.2 Transacciones a Nivel de Módulo

#### axis_trigger: Detección de evento

```
         ┌───┐   ┌───┐   ┌───┐   ┌───┐
 clk   ──┘   └───┘   └───┘   └───┘   └──

       ──┬─────┬─────┬─────┬─────┬─────
 tdata   │ 498 │ 499 │ 500 │ 501 │ 502
       ──┴─────┴─────┴─────┴─────┴─────
                       ▲
                       │ threshold = 500
                       
                            ┌───┐
 trigger ───────────────────┘   └──────
                            │   │
                            └───┘
                              ▲
                              │
                        RISING edge
                        499 < 500 AND
                        500 >= 500
```

#### axis_scope: Captura de ventana

```
 Estado:    IDLE    │  ARMED  │ TRIGGERED │ TRANSFER │ DONE
          ──────────┼─────────┼───────────┼──────────┼─────
                    │         │           │          │
                    ▼         ▼           ▼          ▼
                   arm    trigger      post       TLAST
                           │          complete     │
              ┌────────────┼──────────────────────────────
 s_axis      │    ...     │    ...     │    ...   │ XXX
              └────────────┼──────────────────────────────
                           │
                           │◄── pre ──►│◄── post ──►│
                           │                        │
              ─────────────┴────────────────────────┴─────
 m_axis                    │  Captura completa     │
              ─────────────┴────────────────────────┴─────
```

#### axis_ram_writer: Burst AXI4

```
                    │ CALC │ ADDR │     DATA      │RESP│
                    ├──────┼──────┼───────────────┼────┤
                    
                          ┌────┐
 awvalid ─────────────────┘    └──────────────────────────
                          │    │
                          └────┘
                            ▲
                            │ AWLEN=3 (4 beats)
                            │ AWADDR=0x10001000
                            
                                 ┌─────────────────┐
 wvalid  ────────────────────────┘                 └──────
                                 │  │  │  │  │
                                 D0 D1 D2 D3
                                          │
                                          └─ wlast=1
                                          
                                                   ┌───┐
 bvalid  ──────────────────────────────────────────┘   └──
                                                   │   │
                                                   └───┘
                                                     ▲
                                                     │
                                                  OKAY
```

### A.3 Tabla de Referencia Rápida

| Patrón en Waveform | Significado | Módulo |
|--------------------|-------------|--------|
| tvalid↑ sin tready | Backpressure | Todos |
| tvalid↓ sin transfer | BUG: dato perdido | Todos |
| trigger_out=1 | Evento detectado | trigger |
| state: ARMED→TRIGGERED | Trigger capturado | scope |
| tlast=1 con transfer | Fin de paquete | scope, rw |
| awlen+1 ≠ wlast count | BUG: burst incorrecto | ram_writer |
| bresp≠0 | Error de escritura | ram_writer |

---

## Apéndice B: Resumen de Casos de Test

### B.1 axis_trigger

| # | Nombre | Entrada | Config | Esperado | Verifica |
|---|--------|---------|--------|----------|----------|
| 1 | rising_ramp | 0→1023 | th=500, RISING | 1 trigger @500 | Cruce ascendente |
| 2 | falling_ramp | 1023→0 | th=500, FALLING | 1 trigger @523 | Cruce descendente |
| 3 | both_sine | sin(x)*800 | th=0, BOTH | N triggers | Ambos cruces |
| 4 | level_pulse | pulso 0/800 | th=400, LEVEL | Trigger continuo | Detección nivel |
| 5 | disabled | 0→1023 | enable=0 | 0 triggers | Enable funciona |
| 6 | threshold_edge | 499,500,501 | th=500, RISING | 1 trigger | Valor exacto |

### B.2 axis_scope

| # | Nombre | pre | post | trigger@ | Esperado |
|---|--------|-----|------|----------|----------|
| 1 | basic | 100 | 200 | 200 | 300 muestras, idx 100-399 |
| 2 | pre_only | 150 | 0 | 200 | 150 muestras, idx 50-199 |
| 3 | post_only | 0 | 150 | 50 | 150 muestras, idx 50-199 |
| 4 | early_trig | 100 | 100 | 30 | ~130 muestras (lo disponible) |
| 5 | multi_trig | 50 | 100 | 100,120 | 150 muestras (ignora 2do) |
| 6 | backpressure | 50 | 50 | 100 | 100 muestras sin pérdida |

### B.3 axis_ram_writer

| # | Nombre | Muestras | Condición | Verifica |
|---|--------|----------|-----------|----------|
| 1 | basic | 100+TLAST | Normal | Escritura completa |
| 2 | alignment | 500 | Múltiples bursts | Sin cruce 4KB |
| 3 | tlast_flush | 10+TLAST | < burst len | Flush inmediato |
| 4 | backpressure | 200 | AWREADY 80% | Sin pérdida |
| 5 | 4kb_edge | 100 | addr=0xF00 | Split correcto |
| 6 | max_burst | 256 | Burst completo | AWLEN=255 |

---

## Referencias

1. ARM IHI 0022 - AMBA AXI Protocol Specification
2. ARM IHI 0051A - AMBA 4 AXI4-Stream Protocol Specification
3. IEEE 1800-2017 - SystemVerilog Language Reference Manual
4. Mehta, A.B. - ASIC/SoC Functional Design Verification (Springer, 2018)
