# MCPHA Verification - Instrucciones de Ejecución

## Estructura del Proyecto

```
mcpha_verification/
├── models/
│   ├── python/           # Modelos ESL de referencia
│   │   ├── trigger_model.py
│   │   ├── scope_model.py
│   │   └── ram_writer_model.py
│   └── systemc/          # Modelos TLM 2.0 (en desarrollo)
│       └── trigger/trigger_tlm.h
├── rtl/                  # Diseño RTL
├── tb/unit/              # Testbenches unitarios
├── sim/
│   ├── vectors/          # Vectores de test generados
│   └── logs/             # Salidas de simulación
└── scripts/
    ├── Makefile
    └── generate_vectors.py
```

## Flujo de Verificación

### 1. Generar Vectores de Test (Python)

Antes de simular, generar los vectores con el modelo Python:

```bash
cd mcpha_verification
python3 scripts/generate_vectors.py -o sim/vectors
```

Esto genera archivos `.hex` y `.txt` para cada módulo:
- `*_stimulus.hex`: Datos de entrada
- `*_expected.hex`: Respuesta esperada del modelo
- `*_config.txt`: Configuración del test

### 2. Compilar RTL y Testbenches

```bash
cd scripts
make clean
make compile
```

### 3. Ejecutar Simulación

**Modo batch (regresión):**
```bash
make sim_trigger      # Solo trigger
make sim_scope        # Solo scope
make sim_rw           # Solo RAM writer
make regression       # Todos
```

**Modo GUI (debug con waveforms):**
```bash
make gui_trigger
```

### 4. Ver Resultados

Los logs se guardan en `sim/logs/`:
```bash
cat ../sim/logs/trigger_sim.log | grep -E "PASS|FAIL|Error"
```

## Formato de Archivos de Vectores

### Estímulos (`*_stimulus.hex`)
```
// Comentarios
0000    # Muestra 0 en hex (16 bits)
0001    # Muestra 1
...
```

### Esperados (`*_expected.hex`)
Para el trigger: 0 = no trigger, 1 = trigger
```
0
0
1       # Trigger esperado aquí
0
```

### Configuración (`*_config.txt`)
```
ENABLE 1
THRESHOLD 500
MODE 0
NUM_SAMPLES 1000
```

## Troubleshooting

### Simulación no avanza
1. Verificar que existen los vectores: `ls sim/vectors/`
2. Regenerar vectores: `python3 scripts/generate_vectors.py -o sim/vectors`

### Caracteres extraños en terminal
El proyecto usa solo ASCII en los displays. Si ves caracteres raros,
recompilar el testbench:
```bash
make clean
make compile
```

### Test falla
1. Revisar el log: `cat sim/logs/trigger_sim.log`
2. Ejecutar en modo GUI para ver waveforms: `make gui_trigger`
3. Verificar que el modelo Python genera los esperados correctos

## Tests Disponibles

### Trigger
| Test | Descripción |
|------|-------------|
| `trigger_rising_ramp` | Rampa ascendente, flanco subida |
| `trigger_falling_ramp` | Rampa descendente, flanco bajada |
| `trigger_both_sine` | Senoidal, ambos flancos |
| `trigger_rising_pulse` | Pulsos gaussianos |
| `trigger_level_random` | Señal random, modo nivel |

### Scope
| Test | Descripción |
|------|-------------|
| `scope_single` | Un trigger, ventana básica |
| `scope_multiple` | Múltiples triggers |
| `scope_edge_start` | Trigger cerca del inicio |
| `scope_edge_end` | Trigger cerca del final |

### RAM Writer
| Test | Descripción |
|------|-------------|
| `rw_basic_256` | Un burst exacto (256 beats) |
| `rw_partial_100` | Burst parcial |
| `rw_multi_packet` | Múltiples paquetes con TLAST |

## Arquitectura del Testbench Híbrido

```
Python Model          Vectores .hex          RTL Testbench
(Golden Reference) --> (Estímulos/Expected) --> (QuestaSim)
                                                    |
                                               Scoreboard
                                               (Compare)
                                                    |
                                               PASS/FAIL
```

El modelo Python genera las respuestas esperadas. El testbench RTL
aplica los mismos estímulos al DUT y compara con las respuestas
esperadas usando un scoreboard.
