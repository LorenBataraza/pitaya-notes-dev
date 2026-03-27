# Sistema de Adquisición MCPHA: Diseño e Implementación de Módulos

## Tabla de Contenidos

1. [Introducción](#introducción)
2. [Arquitectura del Sistema](#arquitectura-del-sistema)
3. [Módulo Trigger](#módulo-trigger)
   - [Descripción Funcional](#trigger-descripción-funcional)
   - [Modelo de Referencia en Python](#trigger-modelo-python)
   - [Implementación RTL](#trigger-implementación-rtl)
   - [Casos de Test](#trigger-casos-de-test)
4. [Módulo Scope](#módulo-scope)
   - [Descripción Funcional](#scope-descripción-funcional)
   - [Modelo de Referencia en Python](#scope-modelo-python)
   - [Implementación RTL](#scope-implementación-rtl)
   - [Casos de Test](#scope-casos-de-test)
5. [Módulo RAM Writer](#módulo-ram-writer)
   - [Descripción Funcional](#ram-writer-descripción-funcional)
   - [Modelo de Referencia en Python](#ram-writer-modelo-python)
   - [Implementación RTL](#ram-writer-implementación-rtl)
   - [Casos de Test](#ram-writer-casos-de-test)
6. [Apéndice: Análisis de Waveforms](#apéndice-análisis-de-waveforms)

---

## Introducción

Este documento describe el diseño e implementación de los módulos principales del sistema de adquisición MCPHA (Multi-Channel Pulse Height Analyzer) desarrollado para la plataforma Red Pitaya basada en SoC Zynq-7010.

El sistema implementa una cadena de adquisición de datos que procesa señales analógicas desde el ADC hasta la memoria DDR del sistema, permitiendo tanto análisis en tiempo real como captura de formas de onda.

### Metodología de Desarrollo

Se emplea una metodología de verificación híbrida ESL+RTL:

1. **Modelos ESL (Electronic System Level)**: Implementados en Python, sirven como referencia funcional del comportamiento esperado.
2. **Implementación RTL**: Código SystemVerilog sintetizable para FPGA.
3. **Verificación**: Comparación automática entre modelo y RTL usando testbenches con scoreboard.

---

## Arquitectura del Sistema

### Diagrama de Bloques General

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SISTEMA MCPHA                                      │
│                                                                              │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────────┐              │
│  │   ADC   │───▶│   CIC   │───▶│   FIR   │───▶│ BROADCASTER │              │
│  │ 14b/125M│    │ Decim.  │    │ Filter  │    │             │              │
│  └─────────┘    └─────────┘    └─────────┘    └──────┬──────┘              │
│                                                      │                      │
│                                    ┌─────────────────┼─────────────────┐   │
│                                    │                 │                 │   │
│                                    ▼                 ▼                 │   │
│                              ┌──────────┐      ┌──────────┐           │   │
│                              │ TRIGGER  │      │   PHA    │           │   │
│                              │          │      │          │           │   │
│                              └────┬─────┘      └──────────┘           │   │
│                                   │                                    │   │
│                                   ▼                                    │   │
│                              ┌──────────┐                             │   │
│                              │  SCOPE   │                             │   │
│                              │ (Buffer) │                             │   │
│                              └────┬─────┘                             │   │
│                                   │                                    │   │
│                                   ▼                                    │   │
│                              ┌──────────┐      ┌──────────┐           │   │
│                              │   RAM    │─────▶│   DDR    │           │   │
│                              │  WRITER  │ AXI4 │  Memory  │           │   │
│                              └──────────┘      └──────────┘           │   │
│                                                                        │   │
│  ┌──────────────────────────────────────────────────────────────────┐ │   │
│  │                          AXI HUB                                  │ │   │
│  │                    (Configuración/Status)                         │ │   │
│  └──────────────────────────────────────────────────────────────────┘ │   │
│                                   │                                    │   │
│                                   ▼                                    │   │
│                              ┌──────────┐                             │   │
│                              │   PS     │                             │   │
│                              │ ARM Core │                             │   │
│                              └──────────┘                             │   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Flujo de Datos

1. El **ADC** digitaliza la señal de entrada a 14 bits, 125 MSa/s
2. Los filtros **CIC** y **FIR** realizan decimación y conformación de pulsos
3. El **Broadcaster** distribuye los datos a los módulos de procesamiento
4. El **Trigger** detecta eventos según el umbral y modo configurados
5. El **Scope** captura una ventana de datos alrededor del trigger
6. El **RAM Writer** transfiere los datos capturados a memoria DDR via AXI4

---

## Módulo Trigger

### Trigger: Descripción Funcional

El módulo Trigger implementa un detector de eventos configurable que identifica cruces de umbral en la señal de entrada. Su función es generar una señal de disparo que sincroniza la captura de datos en el módulo Scope.

#### Modos de Operación

| Modo | Código | Descripción |
|------|--------|-------------|
| RISING | 0 | Detecta cuando la señal cruza el umbral de abajo hacia arriba |
| FALLING | 1 | Detecta cuando la señal cruza el umbral de arriba hacia abajo |
| BOTH | 2 | Detecta cruces en ambas direcciones |
| LEVEL | 3 | Genera trigger mientras la señal supera el umbral |

#### Diagrama de Bloques

```
                    ┌─────────────────────────────────────────────────────┐
                    │                     TRIGGER                          │
                    │                                                      │
  s_axis_tdata ────▶│  ┌──────────┐    ┌───────────┐    ┌────────────┐   │
  s_axis_tvalid ───▶│  │ PIPELINE │───▶│  COMPARE  │───▶│  ARM/FIRE  │───▶│──▶ trigger_out
                    │  │ (2 etap) │    │           │    │   LOGIC    │   │
                    │  └──────────┘    └───────────┘    └────────────┘   │
                    │        │               ▲                            │
                    │        │               │                            │
                    │        ▼               │                            │
                    │  ┌──────────┐    ┌───────────┐                     │
                    │  │ SAMPLE   │    │ THRESHOLD │◀────────────────────│──── config.threshold
                    │  │ DELAY    │    │  REGISTER │                     │
                    │  └──────────┘    └───────────┘                     │
                    │                                                      │
                    │                        ▲                            │
                    │                        │                            │
                    │                  config.mode ◀──────────────────────│──── config
                    │                  config.enable                      │
                    └─────────────────────────────────────────────────────┘
```

#### Algoritmo de Detección

El trigger compara dos muestras consecutivas para detectar cruces de umbral:

```
prev_sample ────┐
                ├──▶ (prev < threshold) AND (curr >= threshold) = RISING_EDGE
curr_sample ────┘
                ├──▶ (prev >= threshold) AND (curr < threshold) = FALLING_EDGE
threshold ──────┘
```

La lógica de armado previene múltiples triggers consecutivos:
- El trigger se **arma** cuando no hay evento activo
- El trigger se **dispara** cuando hay evento y está armado
- El trigger se **desarma** inmediatamente después de disparar
- El trigger se **re-arma** cuando la condición de evento desaparece

### Trigger: Modelo Python

El modelo de referencia en Python implementa el comportamiento exacto del módulo RTL:

```python
class TriggerMode(IntEnum):
    """Modos de detección del trigger"""
    RISING  = 0  # Flanco ascendente
    FALLING = 1  # Flanco descendente
    BOTH    = 2  # Ambos flancos
    LEVEL   = 3  # Por nivel

@dataclass
class TriggerConfig:
    """Estructura de configuración del trigger"""
    enable: bool = True
    mode: TriggerMode = TriggerMode.RISING
    threshold: int = 0
    ch_mask: int = 0x03

class TriggerModel:
    """
    Modelo funcional del detector de eventos.
    
    Implementa un pipeline de 2 etapas para comparación
    de muestras consecutivas, replicando la latencia del RTL.
    """
    
    PIPE_STAGES = 2
    
    def __init__(self, config: TriggerConfig = None):
        self.config = config if config else TriggerConfig()
        self.reset()
    
    def reset(self):
        """Reinicia el estado interno"""
        self._pipeline = [0] * self.PIPE_STAGES
        self._valid_pipe = [False] * self.PIPE_STAGES
        self._armed = True
    
    def _detect_threshold_crossing(self, prev: int, curr: int) -> bool:
        """
        Detecta cruce de umbral según el modo configurado.
        
        Args:
            prev: Valor de la muestra anterior
            curr: Valor de la muestra actual
        
        Returns:
            True si se detecta un evento
        """
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
    
    def process_sample(self, sample: int, valid: bool = True) -> bool:
        """
        Procesa una muestra a través del pipeline.
        
        Comportamiento ciclo-a-ciclo equivalente al RTL.
        
        Args:
            sample: Valor de la muestra de entrada
            valid: Indica si la muestra es válida
        
        Returns:
            True si se genera trigger en este ciclo
        """
        if not self.config.enable:
            return None
        
        # Shift del pipeline
        for i in range(self.PIPE_STAGES - 1, 0, -1):
            self._pipeline[i] = self._pipeline[i-1]
            self._valid_pipe[i] = self._valid_pipe[i-1]
        
        self._pipeline[0] = sample
        self._valid_pipe[0] = valid
        
        # Verificar datos válidos para comparación
        if not self._valid_pipe[self.PIPE_STAGES - 2]:
            return None
        
        prev_sample = self._pipeline[self.PIPE_STAGES - 1]
        curr_sample = self._pipeline[self.PIPE_STAGES - 2]
        
        event_detected = self._detect_threshold_crossing(prev_sample, curr_sample)
        
        trigger_out = False
        if self._armed and event_detected:
            trigger_out = True
            self._armed = False  # Desarmar
        elif not event_detected:
            self._armed = True   # Re-armar
        
        return trigger_out
```

#### Generación de Vectores de Test

El modelo puede generar vectores de test con respuestas esperadas:

```python
def generate_test_vectors(self, num_samples: int = 1000, 
                          seed: int = 42) -> Tuple[np.ndarray, List[int]]:
    """
    Genera vectores de test con resultados esperados.
    
    Returns:
        Tupla (muestras, lista de índices con trigger)
    """
    np.random.seed(seed)
    
    # Señal base: senoidal con offset
    t = np.linspace(0, 10*np.pi, num_samples)
    signal = 512 + 400 * np.sin(t)
    
    # Añadir ruido gaussiano
    noise = np.random.normal(0, 20, num_samples)
    signal = signal + noise
    
    # Añadir pulsos agudos
    pulse_positions = np.random.choice(num_samples, size=5, replace=False)
    for pos in pulse_positions:
        if pos + 10 < num_samples:
            signal[pos:pos+10] += 300
    
    # Cuantizar a enteros
    samples = np.clip(signal, 0, 1023).astype(np.int16)
    
    # Calcular triggers esperados
    events = self.process_samples(samples)
    expected_indices = [e.sample_index for e in events]
    
    return samples, expected_indices
```

### Trigger: Implementación RTL

La implementación RTL sigue fielmente el modelo funcional:

```systemverilog
module axis_trigger
    import axi_stream_pkg::*;
#(
    parameter int unsigned DATA_WIDTH = DSP_DATA_WIDTH
)(
    input  wire                         aclk,
    input  wire                         aresetn,
    
    // Configuración
    input  trigger_config_t             config_i,
    
    // AXI-Stream entrada
    input  wire signed [DATA_WIDTH-1:0] s_axis_tdata,
    input  wire                         s_axis_tvalid,
    output logic                        s_axis_tready,
    
    // AXI-Stream salida (passthrough)
    output logic signed [DATA_WIDTH-1:0] m_axis_tdata,
    output logic                         m_axis_tvalid,
    input  wire                          m_axis_tready,
    
    // Señal de trigger
    output logic                         trigger_out
);

    // Pipeline de 2 etapas
    logic signed [DATA_WIDTH-1:0] sample_d1, sample_d2;
    logic                         valid_d1, valid_d2;
    
    // Estado de armado
    logic armed;
    
    // Detección de cruce de umbral
    logic rising_edge, falling_edge, event_detected;
    
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            sample_d1 <= '0;
            sample_d2 <= '0;
            valid_d1  <= 1'b0;
            valid_d2  <= 1'b0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            sample_d1 <= s_axis_tdata;
            sample_d2 <= sample_d1;
            valid_d1  <= 1'b1;
            valid_d2  <= valid_d1;
        end
    end
    
    // Lógica de detección
    assign rising_edge  = (sample_d2 < config_i.threshold) && 
                          (sample_d1 >= config_i.threshold);
    assign falling_edge = (sample_d2 >= config_i.threshold) && 
                          (sample_d1 < config_i.threshold);
    
    always_comb begin
        case (config_i.mode)
            TRIG_RISING:  event_detected = rising_edge;
            TRIG_FALLING: event_detected = falling_edge;
            TRIG_BOTH:    event_detected = rising_edge | falling_edge;
            TRIG_LEVEL:   event_detected = (sample_d1 >= config_i.threshold);
            default:      event_detected = 1'b0;
        endcase
    end
    
    // Lógica de armado y disparo
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            armed <= 1'b1;
            trigger_out <= 1'b0;
        end else begin
            if (config_i.enable && valid_d1) begin
                if (armed && event_detected) begin
                    trigger_out <= 1'b1;
                    armed <= 1'b0;
                end else begin
                    trigger_out <= 1'b0;
                    if (!event_detected)
                        armed <= 1'b1;
                end
            end else begin
                trigger_out <= 1'b0;
            end
        end
    end

endmodule
```

### Trigger: Casos de Test

| ID | Nombre | Descripción | Estímulo | Resultado Esperado |
|----|--------|-------------|----------|-------------------|
| T1 | Rising Edge Básico | Detectar flanco ascendente | Rampa ascendente cruzando umbral | Un trigger al cruzar |
| T2 | Falling Edge Básico | Detectar flanco descendente | Rampa descendente cruzando umbral | Un trigger al cruzar |
| T3 | Both Edges | Detectar ambos flancos | Señal triangular | Triggers en subida y bajada |
| T4 | Level Mode | Detectar nivel sostenido | Pulso rectangular | Triggers mientras está alto |
| T5 | No Rearm | Evitar triggers consecutivos | Señal ruidosa sobre umbral | Un solo trigger por cruce |
| T6 | Disabled | Trigger deshabilitado | Cualquier señal | Sin triggers |
| T7 | Umbral Negativo | Umbral en zona negativa | Señal bipolar | Detecta cruces correctamente |
| T8 | Latencia Pipeline | Verificar latencia de 2 ciclos | Pulso angosto | Trigger 2 ciclos después |

---

## Módulo Scope

### Scope: Descripción Funcional

El módulo Scope implementa un buffer de captura estilo osciloscopio digital. Almacena una ventana de datos centrada alrededor de un evento de trigger, permitiendo analizar tanto las muestras anteriores (pre-trigger) como posteriores (post-trigger) al evento.

#### Máquina de Estados

```
                    ┌─────────────────┐
                    │                 │
                    │      IDLE       │◀──────────────────────┐
                    │                 │                       │
                    └────────┬────────┘                       │
                             │                                │
                        enable && arm                    !enable
                             │                                │
                             ▼                                │
                    ┌─────────────────┐                       │
                    │                 │                       │
                    │     ARMED       │◀──────┐               │
                    │                 │       │               │
                    └────────┬────────┘       │               │
                             │                │               │
                         trigger_in           │               │
                             │                │               │
                             ▼                │               │
                    ┌─────────────────┐       │               │
                    │                 │       │               │
                    │   TRIGGERED     │       │               │
                    │                 │       │               │
                    └────────┬────────┘       │               │
                             │                │               │
                    post_samples completo     │               │
                             │                │               │
                             ▼                │               │
                    ┌─────────────────┐       │               │
                    │                 │       │               │
                    │    TRANSFER     │       │               │
                    │                 │       │               │
                    └────────┬────────┘       │               │
                             │                │               │
                    transferencia completa    │               │
                             │                │               │
                             ▼                │               │
                    ┌─────────────────┐       │               │
                    │                 │       │               │
                    │      DONE       │───────┴───────────────┘
                    │                 │     re-arm
                    └─────────────────┘
```

#### Buffer Circular

El módulo utiliza un buffer circular para almacenar las muestras de pre-trigger:

```
                          write_ptr
                              │
                              ▼
    ┌───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┐
    │ 7 │ 8 │ 9 │10 │11 │12 │13 │   │ 0 │ 1 │ 2 │ 3 │ 4 │ 5 │ 6 │   │
    └───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┴───┘
                              │           ▲
                         muestras         │
                          nuevas      muestras
                                       viejas
    
    En estado ARMED: Las muestras se escriben continuamente,
    sobrescribiendo las más antiguas (buffer circular)
    
    Cuando llega TRIGGER: Se congela el write_ptr y se comienza
    a capturar post_samples adicionales
```

### Scope: Modelo Python

```python
class ScopeState(IntEnum):
    """Estados de la FSM del Scope"""
    IDLE      = 0  # Inactivo
    ARMED     = 1  # Armado, esperando trigger
    TRIGGERED = 2  # Capturando post-trigger
    TRANSFER  = 3  # Transfiriendo datos
    DONE      = 4  # Captura completa

@dataclass
class ScopeConfig:
    """Configuración del módulo Scope"""
    enable: bool = True
    arm: bool = False
    pre_samples: int = 100   # Muestras antes del trigger
    post_samples: int = 100  # Muestras después del trigger

class ScopeModel:
    """
    Modelo funcional del buffer de captura.
    
    Utiliza un deque como buffer circular para emular
    el comportamiento de la BRAM en el RTL.
    """
    
    def __init__(self, buffer_depth: int = 4096):
        self._buffer_depth = buffer_depth
        self._circular_buffer = deque(maxlen=buffer_depth)
        self._post_buffer = []
        self._state = ScopeState.IDLE
    
    def configure(self, config: ScopeConfig):
        """Aplica nueva configuración"""
        self._config = config
        
        if config.pre_samples > self._buffer_depth:
            raise ValueError("pre_samples excede buffer_depth")
        
        if config.enable and config.arm and self._state == ScopeState.IDLE:
            self._state = ScopeState.ARMED
            self._circular_buffer.clear()
            self._post_buffer.clear()
    
    def process_sample(self, sample: int) -> bool:
        """
        Procesa una nueva muestra.
        
        En estado ARMED: almacena en buffer circular
        En estado TRIGGERED: captura en buffer lineal
        """
        if self._state == ScopeState.ARMED:
            self._circular_buffer.append(sample)
            return True
            
        elif self._state == ScopeState.TRIGGERED:
            self._post_buffer.append(sample)
            
            if len(self._post_buffer) >= self._config.post_samples:
                self._state = ScopeState.TRANSFER
            
            return True
        
        return False
    
    def trigger(self) -> bool:
        """
        Procesa evento de trigger.
        
        Marca la posición actual y transiciona a TRIGGERED.
        """
        if self._state != ScopeState.ARMED:
            return False
        
        self._trigger_position = len(self._circular_buffer)
        self._state = ScopeState.TRIGGERED
        self._post_buffer.clear()
        
        return True
    
    def get_captured_data(self) -> CapturedWindow:
        """
        Obtiene los datos capturados.
        
        Combina pre-trigger del buffer circular con
        post-trigger del buffer lineal.
        """
        if self._state not in [ScopeState.TRANSFER, ScopeState.DONE]:
            return None
        
        available_pre = min(self._config.pre_samples, 
                           len(self._circular_buffer))
        
        # Extraer pre-trigger (últimas N muestras del buffer circular)
        pre_data = list(self._circular_buffer)[-available_pre:]
        
        # Combinar pre + post
        all_samples = np.array(pre_data + self._post_buffer)
        
        self._state = ScopeState.DONE
        
        return CapturedWindow(
            samples=all_samples,
            trigger_index=available_pre,
            pre_samples=available_pre,
            post_samples=len(self._post_buffer)
        )
```

### Scope: Implementación RTL

```systemverilog
module axis_scope
    import axi_stream_pkg::*;
#(
    parameter int unsigned DATA_WIDTH   = DSP_DATA_WIDTH,
    parameter int unsigned BUFFER_DEPTH = 4096,
    parameter int unsigned NUM_CH       = NUM_CHANNELS
)(
    input  wire                              aclk,
    input  wire                              aresetn,
    
    input  scope_config_t                    config_i,
    output scope_status_t                    status_o,
    input  wire                              trigger_in,
    
    // AXI-Stream Slave
    input  wire signed [DATA_WIDTH-1:0]      s_axis_tdata,
    input  wire                              s_axis_tvalid,
    output logic                             s_axis_tready,
    
    // AXI-Stream Master
    output logic signed [DATA_WIDTH-1:0]     m_axis_tdata,
    output logic                             m_axis_tvalid,
    input  wire                              m_axis_tready,
    output logic                             m_axis_tlast
);

    // Parámetros derivados
    localparam int ADDR_WIDTH = $clog2(BUFFER_DEPTH);
    
    // Estados
    typedef enum logic [2:0] {
        S_IDLE,
        S_ARMED,
        S_TRIGGERED,
        S_TRANSFER,
        S_DONE
    } state_e;
    
    state_e state, next_state;
    
    // Buffer circular (BRAM)
    logic [DATA_WIDTH-1:0] buffer [BUFFER_DEPTH];
    logic [ADDR_WIDTH-1:0] write_ptr;
    logic [ADDR_WIDTH-1:0] read_ptr;
    logic [ADDR_WIDTH-1:0] trigger_ptr;
    
    // Contadores
    logic [15:0] pre_count;
    logic [15:0] post_count;
    logic [15:0] transfer_count;
    
    // FSM
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn)
            state <= S_IDLE;
        else
            state <= next_state;
    end
    
    always_comb begin
        next_state = state;
        
        case (state)
            S_IDLE: begin
                if (config_i.enable && config_i.arm)
                    next_state = S_ARMED;
            end
            
            S_ARMED: begin
                if (trigger_in)
                    next_state = S_TRIGGERED;
                else if (!config_i.enable)
                    next_state = S_IDLE;
            end
            
            S_TRIGGERED: begin
                if (post_count >= config_i.post_samples)
                    next_state = S_TRANSFER;
            end
            
            S_TRANSFER: begin
                if (transfer_count >= (pre_count + post_count))
                    next_state = S_DONE;
            end
            
            S_DONE: begin
                if (config_i.arm)
                    next_state = S_ARMED;
                else if (!config_i.enable)
                    next_state = S_IDLE;
            end
        endcase
    end
    
    // Escritura en buffer circular (estado ARMED)
    always_ff @(posedge aclk) begin
        if (state == S_ARMED && s_axis_tvalid && s_axis_tready) begin
            buffer[write_ptr] <= s_axis_tdata;
            write_ptr <= write_ptr + 1;
            
            if (pre_count < config_i.pre_samples)
                pre_count <= pre_count + 1;
        end
    end
    
    // Captura post-trigger
    always_ff @(posedge aclk) begin
        if (state == S_TRIGGERED && s_axis_tvalid && s_axis_tready) begin
            buffer[write_ptr] <= s_axis_tdata;
            write_ptr <= write_ptr + 1;
            post_count <= post_count + 1;
        end
    end
    
    // Transferencia de datos
    always_ff @(posedge aclk) begin
        if (state == S_TRANSFER && m_axis_tvalid && m_axis_tready) begin
            read_ptr <= read_ptr + 1;
            transfer_count <= transfer_count + 1;
        end
    end

endmodule
```

### Scope: Casos de Test

| ID | Nombre | Descripción | Estímulo | Resultado Esperado |
|----|--------|-------------|----------|-------------------|
| S1 | Captura Básica | Pre y post trigger | Rampa + trigger en medio | Ventana centrada en trigger |
| S2 | Solo Pre-trigger | post_samples = 0 | Datos + trigger | Solo muestras anteriores |
| S3 | Solo Post-trigger | pre_samples = 0 | Datos + trigger | Solo muestras posteriores |
| S4 | Trigger Temprano | Trigger antes de llenar pre | Trigger en muestra 30 | Pre parcial disponible |
| S5 | Múltiples Triggers | Solo el primero cuenta | 2 triggers consecutivos | Captura del primero |
| S6 | Backpressure | m_axis_tready intermitente | Datos normales | Transferencia completa |
| S7 | Transiciones FSM | Verificar todos los estados | Secuencia completa | Estados correctos |
| S8 | Re-arm | Captura, done, re-arm | Dos capturas | Ambas correctas |

---

## Módulo RAM Writer

### RAM Writer: Descripción Funcional

El módulo RAM Writer recibe datos desde el Scope via AXI-Stream y los escribe a memoria DDR utilizando el protocolo AXI4 Full. Implementa un FIFO interno para desacoplar las velocidades de entrada y salida, y genera transacciones burst para maximizar el throughput.

#### Arquitectura Interna

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              RAM WRITER                                      │
│                                                                              │
│   s_axis_tdata ───▶│  ┌─────────────┐    ┌──────────────┐    ┌──────────┐  │
│   s_axis_tvalid ──▶│  │             │    │              │    │          │  │
│   s_axis_tready ◀──│  │    FIFO     │───▶│    BURST     │───▶│   AXI4   │──┼──▶ m_axi_aw*
│   s_axis_tlast ───▶│  │   (1024)    │    │   BUILDER    │    │  MASTER  │──┼──▶ m_axi_w*
│                    │  │             │    │              │    │          │◀─┼─── m_axi_b*
│                    │  └─────────────┘    └──────────────┘    └──────────┘  │
│                    │        │                  │                  │         │
│                    │        │                  │                  │         │
│                    │        ▼                  ▼                  ▼         │
│                    │   ┌──────────────────────────────────────────────┐    │
│                    │   │              CONTROL FSM                     │    │
│                    │   │                                              │    │
│                    │   │  IDLE → CALC → ADDR → DATA → RESP → IDLE    │    │
│                    │   └──────────────────────────────────────────────┘    │
│                    │        │                                               │
│                    │        ▼                                               │
│                    │   ┌──────────────────────────────────────────────┐    │
│                    │   │           ADDRESS CALCULATOR                 │    │
│                    │   │                                              │    │
│                    │   │  • Siguiente dirección de burst              │    │
│                    │   │  • Verificación límite 4KB                   │    │
│                    │   │  • Cálculo de burst length                   │    │
│                    │   └──────────────────────────────────────────────┘    │
│                    │                                                        │
│    config_i ──────▶│                                                        │
│    status_o ◀──────│                                                        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

#### Consideraciones AXI4

El módulo debe respetar las restricciones del protocolo AXI4:

1. **Límite de 4KB**: Un burst no puede cruzar un límite de 4KB
2. **Burst máximo**: AWLEN puede ser hasta 255 (256 beats)
3. **Alineación**: La dirección debe estar alineada al tamaño del beat
4. **WLAST**: Debe activarse en el último beat del burst

#### Cálculo de Burst

```
Dado:
  - current_addr: Dirección actual
  - data_available: Datos en FIFO
  - max_burst: Burst máximo configurado
  - bytes_per_beat: 8 (AXI 64-bit)

Calcular:
  1. bytes_to_4k = 0x1000 - (current_addr & 0xFFF)
  2. beats_to_4k = bytes_to_4k / bytes_per_beat
  3. burst_len = min(data_available, max_burst, beats_to_4k)
```

### RAM Writer: Modelo Python

```python
class WriterState(IntEnum):
    """Estados de la FSM del RAM Writer"""
    WR_IDLE   = 0  # Esperando datos
    WR_CALC   = 1  # Calculando parámetros de burst
    WR_ADDR   = 2  # Enviando dirección (AW channel)
    WR_DATA   = 3  # Enviando datos (W channel)
    WR_RESP   = 4  # Esperando respuesta (B channel)
    WR_ERROR  = 5  # Estado de error

class RamWriterModel:
    """
    Modelo funcional del módulo RAM Writer.
    
    Simula el comportamiento del escritor de memoria incluyendo
    el manejo de bursts y el límite de 4KB.
    """
    
    AXI4_4KB_BOUNDARY = 0x1000
    AXI4_MAX_BURST_LEN = 256
    
    def __init__(self, fifo_depth: int = 512, data_width: int = 32):
        self._fifo = FifoModel(depth=fifo_depth, width=data_width)
        self._bytes_per_beat = data_width // 8
        self._memory = {}
        self._transactions = []
    
    def configure(self, config: RamWriterConfig):
        """Aplica configuración"""
        self._config = config
        self._current_address = config.base_addr
    
    def axis_write(self, data: int, tlast: bool = False) -> bool:
        """
        Recibe dato desde AXI-Stream.
        
        Simula la interfaz slave del módulo.
        """
        if not self._config.enable:
            return False
        
        return self._fifo.write(data, tlast)
    
    def _calculate_burst_length(self) -> int:
        """
        Calcula la longitud óptima del próximo burst.
        
        Considera:
          - Datos disponibles en FIFO
          - Límite de 4KB
          - Burst máximo configurado
        """
        data_available = self._fifo.level
        if data_available == 0:
            return 0
        
        # Límite de 4KB
        bytes_to_4k = self.AXI4_4KB_BOUNDARY - \
                      (self._current_address & (self.AXI4_4KB_BOUNDARY - 1))
        beats_to_4k = bytes_to_4k // self._bytes_per_beat
        
        # Calcular longitud final
        burst_len = min(
            data_available,
            self._config.max_burst_len,
            beats_to_4k,
            self.AXI4_MAX_BURST_LEN
        )
        
        return burst_len
    
    def process_pending(self) -> int:
        """
        Procesa datos pendientes generando transacciones AXI4.
        
        Returns:
            Número de transacciones generadas
        """
        transactions_generated = 0
        
        while not self._fifo.is_empty:
            burst_len = self._calculate_burst_length()
            if burst_len == 0:
                break
            
            # Leer datos del FIFO
            data = self._fifo.read_burst(burst_len)
            
            # Crear transacción
            txn = Axi4WriteTransaction(
                address=self._current_address,
                data=data,
                burst_len=len(data),
                burst_size=2  # 4 bytes
            )
            
            # Escribir en memoria simulada
            for i, d in enumerate(data):
                addr = self._current_address + (i * self._bytes_per_beat)
                self._memory[addr] = d
            
            # Actualizar dirección
            self._current_address += len(data) * self._bytes_per_beat
            
            # Verificar wrap del buffer
            if self._current_address >= \
               self._config.base_addr + self._config.buffer_size:
                self._current_address = self._config.base_addr
            
            self._transactions.append(txn)
            transactions_generated += 1
        
        return transactions_generated
```

### RAM Writer: Implementación RTL

Ver archivo `rtl/ram_writer/axis_ram_writer.sv` para la implementación completa.

Puntos clave de la implementación:

```systemverilog
// Cálculo del límite de 4KB
logic [AXI_ADDR_W-1:0] bytes_to_4k;
logic [7:0] beats_to_4k;

assign bytes_to_4k = 13'h1000 - {1'b0, current_addr[11:0]};
assign beats_to_4k = bytes_to_4k >> $clog2(AXI_DATA_W/8);

// Longitud de burst
logic [7:0] burst_len_calc;

always_comb begin
    burst_len_calc = fifo_count;
    
    if (burst_len_calc > MAX_BURST_LEN)
        burst_len_calc = MAX_BURST_LEN;
    
    if (burst_len_calc > beats_to_4k)
        burst_len_calc = beats_to_4k;
end
```

### RAM Writer: Casos de Test

| ID | Nombre | Descripción | Estímulo | Resultado Esperado |
|----|--------|-------------|----------|-------------------|
| R1 | Escritura Básica | Burst completo | 100 muestras | Datos en memoria |
| R2 | Burst Parcial | Menos que MAX_BURST | 10 muestras + TLAST | Flush correcto |
| R3 | Límite 4KB | Burst cruza 4KB | Datos en 0xXXXF00 | Split en 2 bursts |
| R4 | TLAST Flush | Flush por TLAST | Datos + TLAST | Todos escritos |
| R5 | Backpressure AW | AWREADY intermitente | Datos continuos | Sin pérdida |
| R6 | Backpressure W | WREADY intermitente | Datos continuos | Sin pérdida |
| R7 | Buffer Circular | Wrap de dirección | Datos > buffer_size | Wrap correcto |
| R8 | FIFO Full | FIFO saturado | Burst de datos | Backpressure AXIS |

#### Bug Conocido

Se ha detectado un bug donde el buffer no escribe todos los datos esperados. Las hipótesis son:

1. **H1**: TLAST no dispara correctamente el flush del FIFO
2. **H2**: El último burst queda incompleto
3. **H3**: El cálculo del límite de 4KB tiene off-by-one
4. **H4**: Deadlock por backpressure en respuestas

Los tests R2 y R4 están diseñados específicamente para detectar estas condiciones.

---

## Apéndice: Análisis de Waveforms

Esta sección documenta la interpretación de las formas de onda generadas durante la simulación, describiendo el significado de cada transacción a nivel de protocolo.

### Convenciones de Visualización

| Color | Significado |
|-------|-------------|
| Verde | Handshake completo (VALID & READY) |
| Amarillo | VALID activo, esperando READY |
| Rojo | Condición de error |
| Azul | Datos válidos |
| Gris | Inactivo |

### Waveform: Transacción AXI-Stream

```
        ┌───────────────────────────────────────────────────────────────────────┐
 aclk   │ ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐   │
        │─┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └───│
        │                                                                       │
 tvalid │      ┌─────────────────────────────────────────────────┐              │
        │──────┘                                                 └──────────────│
        │                                                                       │
 tready │           ┌────┐       ┌───────────────────────────────┐              │
        │───────────┘    └───────┘                               └──────────────│
        │                                                                       │
 tdata  │ XXXX │ D0  │ D0 │XXXXX│ D1  │ D2  │ D3  │ D4  │ D5  │XXXXXXXXXXXXXXXX│
        │──────┴─────┴────┴─────┴─────┴─────┴─────┴─────┴─────┴─────────────────│
        │                                                                       │
 tlast  │                                              ┌──────┐                 │
        │──────────────────────────────────────────────┘      └─────────────────│
        └───────────────────────────────────────────────────────────────────────┘
            T0    T1    T2    T3    T4    T5    T6    T7    T8    T9    T10
        
        Leyenda:
        - T1: D0 válido, pero TREADY=0 (backpressure)
        - T2: Handshake de D0 (TVALID=1, TREADY=1)
        - T3: Backpressure del slave
        - T4-T7: Transferencias consecutivas
        - T8: Último dato con TLAST=1
```

### Waveform: Detección de Trigger

```
        ┌───────────────────────────────────────────────────────────────────────┐
 aclk   │ ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐   │
        │─┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └───│
        │                                                                       │
 tdata  │ 400 │ 450 │ 480 │ 510 │ 530 │ 540 │ 520 │ 490 │ 460 │ 430 │ 400    │
        │──────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┴────────│
        │                                                                       │
 thresh │                      ┈┈┈┈┈┈┈ 500 ┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈│
        │                                                                       │
 armed  │ ─────────────────────┐                    ┌──────────────────────────│
        │                      └────────────────────┘                           │
        │                                                                       │
 trigger│                           ┌──────┐                                    │
        │───────────────────────────┘      └────────────────────────────────────│
        └───────────────────────────────────────────────────────────────────────┘
            T0    T1    T2    T3    T4    T5    T6    T7    T8    T9    T10
        
        Notas:
        - T0-T2: Señal por debajo del umbral, trigger armado
        - T3: Señal cruza umbral (480→510), pipeline delay
        - T4: Trigger se activa, armed=0
        - T5-T6: Señal sobre umbral, pero trigger ya desarmado
        - T7: Señal cae, pero no genera trigger (modo RISING)
        - T8: Re-armado cuando señal cae bajo umbral
```

### Waveform: Transacción AXI4 Write

```
        ┌───────────────────────────────────────────────────────────────────────┐
        │                    WRITE ADDRESS CHANNEL                              │
        │                                                                       │
 awvalid│      ┌──────┐                                                         │
        │──────┘      └─────────────────────────────────────────────────────────│
 awready│           ┌─┐                                                         │
        │───────────┘ └─────────────────────────────────────────────────────────│
 awaddr │XXXXX│ 0x1000│XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX│
 awlen  │XXXXX│  0x0F │XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX│
        │                                                                       │
        │                    WRITE DATA CHANNEL                                 │
        │                                                                       │
 wvalid │                ┌──────────────────────────────────────────────┐       │
        │────────────────┘                                              └───────│
 wready │                     ┌─────────────────────────────────────────┐       │
        │─────────────────────┘                                         └───────│
 wdata  │XXXXXXXXXXXXXXXX│ D0 │ D1 │ D2 │....│ D14│ D15│XXXXXXXXXXXXXXXXXXXXX   │
 wlast  │                                              ┌─────┐                  │
        │──────────────────────────────────────────────┘     └──────────────────│
        │                                                                       │
        │                    WRITE RESPONSE CHANNEL                             │
        │                                                                       │
 bvalid │                                                    ┌──────┐           │
        │────────────────────────────────────────────────────┘      └───────────│
 bready │ ──────────────────────────────────────────────────────────────────────│
 bresp  │XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX│ OKAY │XXXXXXXXXXX│
        └───────────────────────────────────────────────────────────────────────┘
        
        Secuencia:
        1. Master presenta dirección y longitud de burst (AWLEN=15 → 16 beats)
        2. Slave acepta (AWREADY pulse)
        3. Master envía 16 beats de datos
        4. WLAST marca el último beat
        5. Slave responde con BRESP=OKAY
```

### Plantilla para Documentación de Waveforms

Para cada simulación, documentar:

1. **Identificación**
   - Módulo bajo test
   - Escenario de test
   - Timestamp de simulación

2. **Configuración**
   - Parámetros del DUT
   - Estímulos aplicados
   - Condiciones iniciales

3. **Eventos Clave**
   - Tabla de tiempos con eventos significativos
   - Transacciones completadas
   - Errores o anomalías

4. **Análisis**
   - Comportamiento observado vs esperado
   - Latencias medidas
   - Throughput calculado

---

*Documento generado para el proyecto MCPHA - Instituto Balseiro/CNEA*
*Versión: 1.0*
