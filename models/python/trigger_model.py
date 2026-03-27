#!/usr/bin/env python3
"""
@file trigger_model.py
@brief Modelo funcional (ESL) del detector de eventos (trigger)

Este módulo implementa un modelo de referencia en Python para el módulo
axis_trigger. Se utiliza para:
1. Validar el comportamiento esperado del diseño RTL
2. Generar vectores de test con respuestas esperadas
3. Debugging rápido de algoritmos antes de síntesis

@par Uso básico:
    >>> from trigger_model import TriggerModel, TriggerMode
    >>> trigger = TriggerModel(threshold=1000, mode=TriggerMode.RISING)
    >>> events = trigger.process_samples(samples)
"""

from enum import IntEnum
from dataclasses import dataclass
from typing import List, Tuple, Optional
import numpy as np


class TriggerMode(IntEnum):
    """
    @brief Enumeración de modos de detección del trigger
    
    Define los diferentes modos de operación del detector de eventos,
    correspondientes a los valores del tipo trigger_mode_e en RTL.
    """
    RISING  = 0  ##< Dispara en flanco ascendente
    FALLING = 1  ##< Dispara en flanco descendente
    BOTH    = 2  ##< Dispara en ambos flancos
    LEVEL   = 3  ##< Dispara mientras supera el umbral


@dataclass
class TriggerConfig:
    """
    @brief Estructura de configuración del trigger
    
    Contiene todos los parámetros necesarios para configurar el
    comportamiento del detector de eventos.
    
    @param enable     Habilita/deshabilita el trigger
    @param mode       Modo de detección (ver TriggerMode)
    @param threshold  Valor de umbral para la detección
    @param ch_mask    Máscara de bits para canales habilitados
    """
    enable: bool = True
    mode: TriggerMode = TriggerMode.RISING
    threshold: int = 0
    ch_mask: int = 0x03  # Ambos canales por defecto


@dataclass
class TriggerEvent:
    """
    @brief Representa un evento de trigger detectado
    
    @param sample_index  Índice de la muestra donde ocurrió el evento
    @param sample_value  Valor de la muestra en el momento del trigger
    @param prev_value    Valor de la muestra anterior
    @param mode          Modo de detección que lo activó
    """
    sample_index: int
    sample_value: int
    prev_value: int
    mode: TriggerMode


class TriggerModel:
    """
    @brief Modelo funcional del detector de eventos
    
    Implementa la lógica de detección de eventos (trigger) de forma
    bit-accurate con respecto al diseño RTL. Incluye el pipeline
    de 2 etapas para comparación de muestras consecutivas.
    
    @par Ejemplo de uso:
    @code{.py}
    # Crear trigger con umbral de 500 en modo flanco ascendente
    config = TriggerConfig(threshold=500, mode=TriggerMode.RISING)
    trigger = TriggerModel(config)
    
    # Procesar un array de muestras
    samples = np.array([100, 200, 400, 600, 800, 600, 400])
    events = trigger.process_samples(samples)
    
    # events contendrá un TriggerEvent en el índice donde 
    # la señal cruza 500 de abajo hacia arriba
    @endcode
    """
    
    ## Número de etapas de pipeline (debe coincidir con RTL)
    PIPE_STAGES = 2
    
    def __init__(self, config: TriggerConfig = None):
        """
        @brief Constructor del modelo de trigger
        
        @param config Configuración inicial del trigger
        """
        self.config = config if config else TriggerConfig()
        self.reset()
    
    def reset(self):
        """
        @brief Reinicia el estado interno del modelo
        
        Limpia el pipeline y el estado de armado.
        """
        self._pipeline: List[int] = [0] * self.PIPE_STAGES
        self._valid_pipe: List[bool] = [False] * self.PIPE_STAGES
        self._armed: bool = True
        self._events: List[TriggerEvent] = []
    
    def configure(self, config: TriggerConfig):
        """
        @brief Actualiza la configuración del trigger
        
        @param config Nueva configuración a aplicar
        """
        self.config = config
    
    def _detect_threshold_crossing(self, prev: int, curr: int) -> bool:
        """
        @brief Detecta si hay cruce de umbral según el modo configurado
        
        Esta función implementa la misma lógica que la función
        threshold_crossed en axi_stream_pkg.sv.
        
        @param prev Valor de la muestra anterior
        @param curr Valor de la muestra actual
        @return True si se detecta un evento según el modo
        
        @note Los valores se tratan como signed para manejar
              señales bipolares correctamente.
        """
        threshold = self.config.threshold
        
        # Convertir a signed si es necesario (asumiendo 16 bits)
        def to_signed(val):
            if val >= 32768:
                return val - 65536
            return val
        
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
        else:
            return False
    
    def process_sample(self, sample: int, valid: bool = True) -> Optional[bool]:
        """
        @brief Procesa una única muestra a través del pipeline
        
        Implementa el comportamiento ciclo-a-ciclo del módulo RTL.
        
        @param sample Valor de la muestra de entrada
        @param valid  Indica si la muestra es válida
        @return True si se genera un trigger, False si no, None si datos no válidos
        """
        if not self.config.enable:
            return None
        
        # Shift del pipeline (equivalente al always_ff en RTL)
        for i in range(self.PIPE_STAGES - 1, 0, -1):
            self._pipeline[i] = self._pipeline[i-1]
            self._valid_pipe[i] = self._valid_pipe[i-1]
        
        self._pipeline[0] = sample
        self._valid_pipe[0] = valid
        
        # Verificar si tenemos datos válidos para comparar
        if not self._valid_pipe[self.PIPE_STAGES - 2]:
            return None
        
        # Obtener muestras para comparación
        prev_sample = self._pipeline[self.PIPE_STAGES - 1]
        curr_sample = self._pipeline[self.PIPE_STAGES - 2]
        
        # Detectar evento
        event_detected = self._detect_threshold_crossing(prev_sample, curr_sample)
        
        trigger_out = False
        
        if self._armed and event_detected:
            trigger_out = True
            self._armed = False  # Desarmar
        elif not event_detected:
            self._armed = True   # Re-armar
        
        return trigger_out
    
    def process_samples(self, samples: np.ndarray) -> List[TriggerEvent]:
        """
        @brief Procesa un array completo de muestras
        
        Útil para simulación batch de grandes cantidades de datos.
        
        @param samples Array numpy de muestras a procesar
        @return Lista de eventos detectados
        """
        self.reset()
        events = []
        
        for i, sample in enumerate(samples):
            trigger = self.process_sample(int(sample))
            
            if trigger:
                # Compensar latencia del pipeline para índice real
                real_index = i - (self.PIPE_STAGES - 1)
                if real_index >= 0:
                    event = TriggerEvent(
                        sample_index=real_index,
                        sample_value=int(samples[real_index]) if real_index < len(samples) else 0,
                        prev_value=int(samples[real_index-1]) if real_index > 0 else 0,
                        mode=self.config.mode
                    )
                    events.append(event)
        
        return events
    
    def generate_test_vectors(self, num_samples: int = 1000, 
                              seed: int = 42) -> Tuple[np.ndarray, List[int]]:
        """
        @brief Genera vectores de test con resultados esperados
        
        Crea un conjunto de muestras de prueba y calcula los índices
        donde debería ocurrir un trigger según la configuración actual.
        
        @param num_samples Número de muestras a generar
        @param seed        Semilla para reproducibilidad
        @return Tupla (muestras, lista de índices con trigger)
        
        @par Ejemplo:
        @code{.py}
        trigger = TriggerModel(TriggerConfig(threshold=512, mode=TriggerMode.RISING))
        samples, expected_triggers = trigger.generate_test_vectors(1000)
        
        # Ahora podemos usar samples como estímulo para RTL
        # y expected_triggers como referencia para verificación
        @endcode
        """
        np.random.seed(seed)
        
        # Generar señal sintética con ruido y pulsos
        t = np.linspace(0, 10*np.pi, num_samples)
        
        # Señal base: senoidal con offset
        signal = 512 + 400 * np.sin(t)
        
        # Añadir ruido gaussiano
        noise = np.random.normal(0, 20, num_samples)
        signal = signal + noise
        
        # Añadir algunos pulsos agudos
        pulse_positions = np.random.choice(num_samples, size=5, replace=False)
        for pos in pulse_positions:
            if pos + 10 < num_samples:
                signal[pos:pos+10] += 300
        
        # Cuantizar a enteros (simular ADC)
        samples = np.clip(signal, 0, 1023).astype(np.int16)
        
        # Calcular triggers esperados
        events = self.process_samples(samples)
        expected_indices = [e.sample_index for e in events]
        
        return samples, expected_indices


def generate_stimulus_file(filename: str, config: TriggerConfig, 
                          num_samples: int = 1000):
    """
    @brief Genera archivo de estímulo para simulación RTL
    
    Crea un archivo de texto con formato compatible con $readmemh
    de Verilog/SystemVerilog.
    
    @param filename    Nombre del archivo de salida
    @param config      Configuración del trigger
    @param num_samples Número de muestras a generar
    
    @par Formato del archivo:
    El archivo contiene una muestra por línea en formato hexadecimal,
    seguida de un comentario con el valor decimal.
    """
    trigger = TriggerModel(config)
    samples, expected = trigger.generate_test_vectors(num_samples)
    
    with open(filename, 'w') as f:
        f.write(f"// Stimulus file generated by trigger_model.py\n")
        f.write(f"// Config: threshold={config.threshold}, mode={config.mode.name}\n")
        f.write(f"// Expected trigger indices: {expected}\n")
        f.write(f"//\n")
        
        for i, sample in enumerate(samples):
            trigger_mark = " <-- TRIGGER" if i in expected else ""
            f.write(f"{sample:04X}  // {sample:5d}{trigger_mark}\n")
    
    print(f"Generated {filename} with {num_samples} samples")
    print(f"Expected {len(expected)} trigger events")


def main():
    """
    @brief Función principal para pruebas standalone
    """
    import matplotlib.pyplot as plt
    
    # Configurar trigger
    config = TriggerConfig(
        enable=True,
        mode=TriggerMode.RISING,
        threshold=600
    )
    
    trigger = TriggerModel(config)
    
    # Generar datos de prueba
    samples, expected_triggers = trigger.generate_test_vectors(500)
    
    print(f"Configuración: threshold={config.threshold}, mode={config.mode.name}")
    print(f"Triggers detectados en índices: {expected_triggers}")
    
    # Visualizar
    plt.figure(figsize=(12, 6))
    plt.plot(samples, 'b-', label='Señal', linewidth=0.8)
    plt.axhline(y=config.threshold, color='r', linestyle='--', 
                label=f'Umbral ({config.threshold})')
    
    # Marcar triggers
    for idx in expected_triggers:
        plt.axvline(x=idx, color='g', alpha=0.5, linewidth=2)
    
    plt.xlabel('Índice de muestra')
    plt.ylabel('Amplitud')
    plt.title('Modelo de Trigger - Detección de Eventos')
    plt.legend()
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig('trigger_model_output.png', dpi=150)
    print("Gráfico guardado en trigger_model_output.png")
    
    # Generar archivo de estímulo
    generate_stimulus_file('trigger_stimulus.hex', config, 500)


if __name__ == "__main__":
    main()
