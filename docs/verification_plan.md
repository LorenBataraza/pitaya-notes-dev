# Plan de Verificación - Sistema de Adquisición Multi-Canal

## 1. Introducción

Este documento define el plan de verificación para el sistema de adquisición
asíncrona multi-canal basado en la arquitectura MCPHA de Pavel Demin.

### 1.1 Objetivo

Verificar que el diseño RTL cumple con los requisitos funcionales y de
rendimiento especificados, utilizando una metodología híbrida que combina:

- Modelos de referencia en Python (ESL)
- Testbenches dirigidos en SystemVerilog
- Verificación basada en assertions (SVA)
- Cobertura funcional y de código

### 1.2 Alcance

| Módulo | Prioridad | Criticidad | Estado |
|--------|-----------|------------|--------|
| axis_trigger | Alta | Alta | En desarrollo |
| axis_scope | Alta | Crítica | En desarrollo |
| axis_ram_writer | Alta | Crítica | Problema conocido |
| axi_hub | Media | Media | Pendiente |
| axis_pha | Media | Baja | Pendiente |
| axis_histogram | Baja | Baja | Pendiente |

---

## 2. Identificación de Subsistemas

### 2.1 Subsistema: Cadena DSP (CIC + FIR)

**Descripción**: Filtra y decima la señal del ADC.

**Interfaces**:
- Entrada: 14 bits @ 125 MSa/s
- Salida: 16 bits @ tasa reducida

**Verificación**:
- [ ] Respuesta en frecuencia vs modelo MATLAB/Python
- [ ] Latencia de grupo
- [ ] Overflow/saturation handling

### 2.2 Subsistema: Trigger

**Descripción**: Detecta eventos basados en umbral y polaridad.

**Interfaces**:
- Entrada: AXI-Stream (16 bits)
- Salida: AXI-Stream pass-through + trigger pulse

**Parámetros configurables**:
| Parámetro | Rango | Unidad |
|-----------|-------|--------|
| threshold | -32768 a 32767 | LSB |
| mode | RISING, FALLING, BOTH, LEVEL | - |
| ch_mask | 0x00 a 0x03 | bitmask |

**Casos de test**:
1. Flanco ascendente con señal limpia
2. Flanco descendente con señal limpia
3. Ambos flancos
4. Modo nivel
5. No-retriggering (hysteresis)
6. Señal con ruido cerca del umbral
7. Triggers consecutivos rápidos
8. Backpressure handling

### 2.3 Subsistema: Scope

**Descripción**: Captura ventana de datos alrededor del trigger.

**Interfaces**:
- Entrada: AXI-Stream + trigger
- Salida: AXI-Stream con TLAST

**Parámetros configurables**:
| Parámetro | Rango | Unidad |
|-----------|-------|--------|
| pre_samples | 0 a BUFFER_DEPTH | muestras |
| post_samples | 1 a BUFFER_DEPTH | muestras |
| arm | 0, 1 | bool |

**Casos de test**:
1. Captura básica con pre+post trigger
2. Solo post-trigger (pre=0)
3. Máximo pre-trigger (pre=BUFFER_DEPTH-1)
4. Re-arm después de captura
5. Trigger durante transferencia (debe ignorar)
6. Overflow de buffer (pre > BUFFER_DEPTH)

### 2.4 Subsistema: RAM Writer (CRÍTICO)

**Descripción**: Escribe datos capturados a DDR via AXI4.

**Interfaces**:
- Entrada: AXI-Stream con TLAST
- Salida: AXI4 Master

**Problema conocido**: El buffer queda sin escribir toda la salida.

**Hipótesis de falla**:
1. TLAST no se procesa correctamente
2. El FIFO interno tiene bug de lectura
3. El burst AXI4 no completa todos los beats
4. Backpressure de AXI4 no se maneja correctamente

**Casos de test (alta prioridad)**:
1. [ ] Escritura básica de un burst
2. [ ] Múltiples bursts consecutivos
3. [ ] Manejo de AWREADY deasserted
4. [ ] Manejo de WREADY deasserted
5. [ ] Verificación de TLAST → flush
6. [ ] Buffer circular wrap-around
7. [ ] Verificación de bytes_written vs expected
8. [ ] Stress test con backpressure aleatorio

---

## 3. Metodología de Verificación

### 3.1 Estrategia por capas

```
┌─────────────────────────────────────────────────────────────┐
│ Capa 4: Verificación HW/SW (FPGA-in-the-loop)              │
├─────────────────────────────────────────────────────────────┤
│ Capa 3: Verificación de integración (cadena completa)       │
├─────────────────────────────────────────────────────────────┤
│ Capa 2: Verificación unitaria RTL (testbenches SV)         │
├─────────────────────────────────────────────────────────────┤
│ Capa 1: Modelos de referencia ESL (Python)                  │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Capa 1: Modelos ESL (Python)

**Objetivo**: Definir comportamiento esperado ("golden reference")

**Archivos**:
- `models/python/trigger_model.py` - Modelo del trigger
- `models/python/scope_model.py` - Modelo del scope
- `models/python/acquisition_sim.py` - Simulación completa

**Entregables**:
- Archivos de estímulo (.hex para $readmemh)
- Archivos de respuesta esperada
- Gráficos de referencia

### 3.3 Capa 2: Verificación unitaria RTL

**Objetivo**: Verificar cada módulo aisladamente

**Estructura del testbench**:
```
┌──────────────────────────────────────────────────────┐
│                    TESTBENCH                         │
│  ┌─────────────┐  ┌─────────┐  ┌────────────────┐   │
│  │   Driver    │──│   DUT   │──│   Monitor      │   │
│  │ (estímulos) │  │         │  │ (observación)  │   │
│  └─────────────┘  └─────────┘  └───────┬────────┘   │
│                                        │            │
│  ┌─────────────────────────────────────▼──────────┐ │
│  │              Scoreboard                        │ │
│  │   (comparación con modelo de referencia)       │ │
│  └────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

### 3.4 Capa 3: Verificación de integración

**Objetivo**: Verificar interacción entre módulos

**Cadenas a verificar**:
1. `trigger → scope → ram_writer`
2. `broadcaster → trigger(OR) → scope`
3. `dsp → pha → histogram`

### 3.5 Capa 4: Verificación HW/SW

**Objetivo**: Verificar en hardware real (Red Pitaya)

**Herramientas**:
- Scripts Python para control via SSH
- Comparación de datos adquiridos vs esperados

---

## 4. Assertions (SVA)

### 4.1 Protocolo AXI-Stream

```systemverilog
// TVALID estable hasta handshake
property p_tvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (tvalid && !tready) |=> tvalid;
endproperty

// TDATA estable mientras TVALID sin TREADY
property p_tdata_stable;
    @(posedge clk) disable iff (!rst_n)
    (tvalid && !tready) |=> $stable(tdata);
endproperty

// TLAST solo con TVALID
property p_tlast_with_valid;
    @(posedge clk) disable iff (!rst_n)
    tlast |-> tvalid;
endproperty
```

### 4.2 Protocolo AXI4 (RAM Writer)

```systemverilog
// AWVALID estable hasta handshake
property p_awvalid_stable;
    @(posedge clk) disable iff (!rst_n)
    (awvalid && !awready) |=> awvalid;
endproperty

// Número correcto de beats en burst
property p_burst_length;
    @(posedge clk) disable iff (!rst_n)
    (awvalid && awready) |-> 
        ##[1:256] (wvalid && wready && wlast);
endproperty

// WLAST solo en último beat
property p_wlast_correct;
    @(posedge clk) disable iff (!rst_n)
    (wvalid && wready && wlast) |-> (beat_count == awlen);
endproperty
```

---

## 5. Plan de Cobertura

### 5.1 Cobertura funcional (covergroups)

```systemverilog
covergroup cg_trigger_config @(posedge clk);
    cp_mode: coverpoint config.mode {
        bins rising  = {TRIG_RISING};
        bins falling = {TRIG_FALLING};
        bins both    = {TRIG_BOTH};
        bins level   = {TRIG_LEVEL};
    }
    
    cp_threshold: coverpoint config.threshold {
        bins low    = {[0:100]};
        bins mid    = {[101:900]};
        bins high   = {[901:1023]};
        bins neg    = {[-1:-32768]};
    }
    
    cross_mode_thresh: cross cp_mode, cp_threshold;
endgroup

covergroup cg_trigger_events @(posedge clk);
    cp_trigger: coverpoint trigger_out {
        bins no_trig  = {0};
        bins trig     = {1};
    }
    
    cp_consecutive: coverpoint trigger_count {
        bins single   = {1};
        bins few      = {[2:5]};
        bins many     = {[6:$]};
    }
endgroup
```

### 5.2 Métricas de cobertura objetivo

| Tipo | Objetivo | Notas |
|------|----------|-------|
| Línea | >95% | Código sintetizable |
| Branch | >90% | Todas las ramas de FSM |
| FSM | 100% | Todos los estados y transiciones |
| Funcional | >85% | Covergroups definidos |
| Assertion | 0 fallos | Todas las assertions pasan |

---

## 6. Cronograma recomendado

### Fase 1: Modelos de referencia (1-2 semanas)
- [ ] Completar trigger_model.py
- [ ] Crear scope_model.py
- [ ] Crear ram_writer_model.py
- [ ] Validar modelos con datos sintéticos

### Fase 2: Verificación unitaria (2-3 semanas)
- [ ] tb_axis_trigger completo
- [ ] tb_axis_scope
- [ ] tb_axis_ram_writer (PRIORIDAD)
- [ ] Assertions en todos los módulos

### Fase 3: Verificación de integración (1-2 semanas)
- [ ] tb_acquisition_chain
- [ ] Test de stress (triggers rápidos)
- [ ] Test de larga duración

### Fase 4: Debugging del RAM Writer (paralelo)
- [ ] Identificar causa raíz del bug
- [ ] Implementar fix
- [ ] Regression testing

---

## 7. Herramientas

### Simulación
- **Vivado XSim**: Incluido con Vivado
- **ModelSim/QuestaSim**: Si está disponible (mejor debugging)
- **Verilator**: Para simulación rápida de modelos

### Análisis de cobertura
- Vivado coverage analysis
- Scripts Python para reportes

### Debug
- Vivado Logic Analyzer (ILA)
- Virtual I/O (VIO) para control runtime

---

## 8. Riesgos identificados

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|--------------|---------|------------|
| Bug en RAM Writer no resuelto | Alta | Crítico | Priorizar investigación |
| Incompatibilidad con Pitaya OS | Media | Alto | Verificar drivers temprano |
| Recursos FPGA insuficientes | Baja | Alto | Estimar recursos al inicio |
| Cobertura insuficiente | Media | Medio | Definir covergroups temprano |

---

## 9. Criterios de aceptación

El diseño se considera verificado cuando:

1. ✅ Todos los tests unitarios pasan
2. ✅ Todos los tests de integración pasan
3. ✅ Cobertura de línea > 95%
4. ✅ Cobertura funcional > 85%
5. ✅ Cero assertions fallidas en regresión
6. ✅ Verificación HW/SW exitosa en Red Pitaya
7. ✅ Datos adquiridos coinciden con modelo de referencia
