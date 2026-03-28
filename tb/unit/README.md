# Testbenches Unitarios RTL

Este directorio contiene los testbenches unitarios para verificar los módulos RTL del sistema MCPHA con QuestaSim.

## Ejecución

Desde el directorio `scripts/`:

```bash
# Trigger
make sim_trigger

# Scope  
make sim_scope

# RAM Writer
make sim_rw

# Todos
make regression
```

## Archivos

| Archivo | Módulo | Descripción |
|---------|--------|-------------|
| `tb_axis_trigger.sv` | axis_trigger | Compara RTL con vectores Python |
| `tb_axis_scope.sv` | axis_scope | Pruebas de captura pre/post trigger |
| `tb_axis_ram_writer.sv` | axis_ram_writer | Verificación de bursts AXI4 |

## Vectores de Test

Los testbenches cargan vectores desde `sim/vectors/`. El generador de vectores está en `scripts/generate_vectors.py`.

```bash
cd scripts
python3 generate_vectors.py
```

## Notas de Implementación

### Trigger: Compensación de Pipeline

El RTL tiene un pipeline de 2 ciclos. El modelo Python genera `expected[i-1] = 1` cuando detecta un cruce entre la muestra `i-1` y la muestra `i`. El testbench usa un pipeline de índices para atribuir cada trigger al índice correcto:

```systemverilog
// Cuando trigger_out=1, corresponde a la muestra que entró
// hace PIPE_DELAY ciclos, menos 1 por la semántica de transición
int trigger_idx = index_pipeline[PIPE_DELAY-1] - 1;
```

### RAM Writer: Escritura en Memoria

La memoria simulada se inicializa en un bloque `initial` y se actualiza en `always @(posedge aclk)` para evitar conflictos de múltiples drivers que QuestaSim reporta con `always_ff`:

```systemverilog
// Inicialización (una sola vez)
initial begin
    for (int i = 0; i < MEMORY_SIZE; i++)
        memory[i] = 8'h00;
end

// Actualización (en cada ciclo)
always @(posedge aclk) begin
    if (m_axi_wvalid && m_axi_wready)
        memory[offset] <= m_axi_wdata[i*8 +: 8];
end
```

### Scope: Secuencia de Trigger

El trigger debe mantenerse activo durante al menos un ciclo para que el scope lo detecte. El testbench genera un pulso de trigger de un ciclo:

```systemverilog
if (i == trig_at) begin
    trigger_in = 1;
    @(posedge aclk);
    trigger_in = 0;
end
```

## Watchdog

Cada testbench tiene un watchdog que termina la simulación si excede un tiempo máximo:

| Testbench | Timeout |
|-----------|---------|
| trigger | 16 ms (2M ciclos) |
| scope | 4 ms (500K ciclos) |
| ram_writer | 4 ms (500K ciclos) |

Si el watchdog se dispara, revisar:
1. Que los vectores de test existan
2. Que el DUT no esté en deadlock por backpressure
3. Que las señales de handshake estén conectadas

## Errores Comunes

### `FALSE NEGATIVE` / `FALSE POSITIVE` en Trigger

El índice del trigger esperado no coincide con el detectado. Verificar que el modelo Python y el RTL usen la misma semántica para la latencia del pipeline.

### `Watchdog timeout` en Scope

La captura no se completó. Verificar que:
- El trigger se generó después de que el scope se armó
- Hay suficientes muestras para completar pre + post
- TREADY está activo

### `Variable driven in always_ff` en RAM Writer

QuestaSim no permite que una variable sea escrita desde múltiples procesos si se usa `always_ff`. Usar `always` sin el sufijo `_ff`.
