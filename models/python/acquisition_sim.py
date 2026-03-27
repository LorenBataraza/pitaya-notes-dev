#!/usr/bin/env python3
"""
@file acquisition_sim.py
@brief Simulador de sistema completo de adquisición

Este módulo integra los modelos de trigger, scope y RAM writer para
simular el comportamiento completo de la cadena de adquisición.

@par Flujo de datos modelado:
    ADC → DSP → Broadcaster → Trigger → Scope → RAM Writer → DDR

@par Funcionalidades:
    - Simulación de señales de entrada (pulsos, ruido, etc.)
    - Detección de eventos con múltiples triggers
    - Captura de ventanas pre/post trigger
    - Verificación de integridad de datos
"""

from dataclasses import dataclass, field
from typing import List, Optional, Tuple, Dict, Callable
from enum import IntEnum, auto
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

# Importar modelos locales
from trigger_model import TriggerModel, TriggerConfig, TriggerMode, TriggerEvent
from scope_model import ScopeModel, ScopeConfig, ScopeState, CapturedWindow
from ram_writer_model import (RamWriterModel, RamWriterConfig, 
                               Axi4WriteTransaction)


class ChannelId(IntEnum):
    """
    @brief Identificadores de canal
    """
    CH1 = 0
    CH2 = 1


@dataclass
class SystemConfig:
    """
    @brief Configuración del sistema completo
    
    @param sample_rate       Frecuencia de muestreo en Hz
    @param adc_bits          Resolución del ADC
    @param dsp_decimation    Factor de decimación del DSP
    @param trigger_ch1       Configuración del trigger CH1
    @param trigger_ch2       Configuración del trigger CH2
    @param trigger_or_mode   True para OR entre triggers, False para AND
    @param scope_pre         Muestras pre-trigger
    @param scope_post        Muestras post-trigger
    @param scope_buffer      Profundidad del buffer del scope
    @param ram_base_addr     Dirección base en DDR
    @param ram_buffer_size   Tamaño del buffer en DDR
    """
    sample_rate: float = 125e6
    adc_bits: int = 14
    dsp_decimation: int = 1
    
    # Triggers
    trigger_ch1: TriggerConfig = field(default_factory=TriggerConfig)
    trigger_ch2: TriggerConfig = field(default_factory=TriggerConfig)
    trigger_or_mode: bool = True
    
    # Scope
    scope_pre: int = 100
    scope_post: int = 200
    scope_buffer: int = 4096
    
    # RAM Writer
    ram_base_addr: int = 0x1000_0000
    ram_buffer_size: int = 0x0010_0000


@dataclass
class AcquisitionResult:
    """
    @brief Resultado de una adquisición
    
    @param windows           Lista de ventanas capturadas
    @param trigger_events    Lista de eventos de trigger
    @param total_samples     Muestras totales procesadas
    @param bytes_written     Bytes escritos a memoria
    @param axi_transactions  Transacciones AXI4 generadas
    """
    windows: List[CapturedWindow]
    trigger_events: List[TriggerEvent]
    total_samples: int
    bytes_written: int
    axi_transactions: List[Axi4WriteTransaction]


class SignalGenerator:
    """
    @brief Generador de señales de prueba
    
    Genera diferentes tipos de señales para simular entradas del ADC.
    """
    
    @staticmethod
    def gaussian_pulse(
        num_samples: int,
        pulse_positions: List[int],
        amplitude: int = 500,
        width: int = 20,
        baseline: int = 512,
        noise_std: float = 10.0
    ) -> np.ndarray:
        """
        @brief Genera señal con pulsos gaussianos
        
        Simula señales típicas de detectores nucleares.
        
        @param num_samples     Número de muestras
        @param pulse_positions Posiciones de los pulsos
        @param amplitude       Amplitud de los pulsos
        @param width          Ancho (sigma) de los pulsos
        @param baseline       Nivel de línea base
        @param noise_std      Desviación estándar del ruido
        @return Array de muestras
        """
        signal = np.ones(num_samples) * baseline
        
        # Añadir pulsos gaussianos
        for pos in pulse_positions:
            x = np.arange(num_samples)
            pulse = amplitude * np.exp(-0.5 * ((x - pos) / width) ** 2)
            signal += pulse
        
        # Añadir ruido
        signal += np.random.normal(0, noise_std, num_samples)
        
        # Limitar a rango del ADC
        signal = np.clip(signal, 0, 2**14 - 1).astype(np.int16)
        
        return signal
    
    @staticmethod
    def exponential_decay(
        num_samples: int,
        pulse_positions: List[int],
        amplitude: int = 800,
        rise_time: int = 5,
        decay_time: int = 50,
        baseline: int = 512,
        noise_std: float = 10.0
    ) -> np.ndarray:
        """
        @brief Genera señal con pulsos de decaimiento exponencial
        
        Simula señales de scintilladores o PMTs.
        
        @param num_samples     Número de muestras
        @param pulse_positions Posiciones de los pulsos
        @param amplitude       Amplitud máxima
        @param rise_time       Tiempo de subida en muestras
        @param decay_time      Constante de tiempo de decay
        @param baseline       Nivel de línea base
        @param noise_std      Desviación estándar del ruido
        @return Array de muestras
        """
        signal = np.ones(num_samples) * baseline
        
        for pos in pulse_positions:
            for i in range(num_samples):
                if i >= pos:
                    t = i - pos
                    if t < rise_time:
                        # Subida lineal
                        signal[i] += amplitude * (t / rise_time)
                    else:
                        # Decaimiento exponencial
                        signal[i] += amplitude * np.exp(-(t - rise_time) / decay_time)
        
        # Añadir ruido
        signal += np.random.normal(0, noise_std, num_samples)
        signal = np.clip(signal, 0, 2**14 - 1).astype(np.int16)
        
        return signal
    
    @staticmethod
    def sine_wave(
        num_samples: int,
        frequency: float,
        sample_rate: float = 125e6,
        amplitude: int = 500,
        offset: int = 512,
        noise_std: float = 5.0
    ) -> np.ndarray:
        """
        @brief Genera señal sinusoidal
        
        @param num_samples Número de muestras
        @param frequency   Frecuencia de la onda
        @param sample_rate Frecuencia de muestreo
        @param amplitude   Amplitud
        @param offset      Offset DC
        @param noise_std   Ruido
        @return Array de muestras
        """
        t = np.arange(num_samples) / sample_rate
        signal = offset + amplitude * np.sin(2 * np.pi * frequency * t)
        signal += np.random.normal(0, noise_std, num_samples)
        signal = np.clip(signal, 0, 2**14 - 1).astype(np.int16)
        
        return signal


class AcquisitionSystem:
    """
    @brief Sistema de adquisición completo
    
    Integra todos los módulos de la cadena de adquisición y permite
    simular el comportamiento del sistema hardware.
    
    @par Ejemplo de uso:
    @code{.py}
    # Configurar sistema
    config = SystemConfig(
        trigger_ch1=TriggerConfig(enable=True, threshold=600, mode=TriggerMode.RISING),
        scope_pre=100,
        scope_post=200
    )
    
    system = AcquisitionSystem(config)
    
    # Generar señal de prueba
    signal = SignalGenerator.gaussian_pulse(10000, [2000, 5000, 8000])
    
    # Ejecutar adquisición
    result = system.run_acquisition(signal)
    
    # Visualizar resultados
    system.plot_results(signal, result)
    @endcode
    """
    
    def __init__(self, config: SystemConfig):
        """
        @brief Constructor del sistema
        
        @param config Configuración del sistema
        """
        self._config = config
        
        # Crear módulos
        self._trigger_ch1 = TriggerModel()
        self._trigger_ch2 = TriggerModel()
        self._scope = ScopeModel(buffer_depth=config.scope_buffer)
        self._ram_writer = RamWriterModel()
        
        # Configurar módulos
        self._configure_modules()
    
    def _configure_modules(self):
        """
        @brief Configura todos los módulos según la configuración del sistema
        """
        # Triggers
        self._trigger_ch1.configure(self._config.trigger_ch1)
        self._trigger_ch2.configure(self._config.trigger_ch2)
        
        # Scope
        self._scope.configure(ScopeConfig(
            enable=True,
            arm=True,
            pre_samples=self._config.scope_pre,
            post_samples=self._config.scope_post
        ))
        
        # RAM Writer
        self._ram_writer.configure(RamWriterConfig(
            enable=True,
            base_addr=self._config.ram_base_addr,
            buffer_size=self._config.ram_buffer_size
        ))
    
    def reset(self):
        """
        @brief Reinicia el sistema completo
        """
        self._trigger_ch1.reset()
        self._trigger_ch2.reset()
        self._scope.reset()
        self._ram_writer.reset()
        self._configure_modules()
    
    def run_acquisition(
        self,
        signal_ch1: np.ndarray,
        signal_ch2: Optional[np.ndarray] = None,
        max_triggers: int = 10
    ) -> AcquisitionResult:
        """
        @brief Ejecuta una adquisición completa
        
        Procesa las señales de entrada, detecta triggers, captura ventanas
        y simula la escritura a memoria.
        
        @param signal_ch1   Señal del canal 1
        @param signal_ch2   Señal del canal 2 (opcional)
        @param max_triggers Número máximo de triggers a procesar
        @return Resultado de la adquisición
        """
        if signal_ch2 is None:
            signal_ch2 = np.zeros_like(signal_ch1)
        
        # Resultados
        windows: List[CapturedWindow] = []
        all_trigger_events: List[TriggerEvent] = []
        
        num_samples = len(signal_ch1)
        triggers_processed = 0
        
        # Procesar muestra por muestra
        for i in range(num_samples):
            sample_ch1 = int(signal_ch1[i])
            sample_ch2 = int(signal_ch2[i])
            
            # Procesar triggers (retorna bool, no TriggerEvent)
            trig_ch1 = self._trigger_ch1.process_sample(sample_ch1)
            trig_ch2 = self._trigger_ch2.process_sample(sample_ch2)
            
            # Combinar triggers según modo
            trigger_fired = False
            if self._config.trigger_or_mode:
                trigger_fired = (trig_ch1 == True) or (trig_ch2 == True)
            else:
                trigger_fired = (trig_ch1 == True) and (trig_ch2 == True)
            
            # Crear TriggerEvent si hubo trigger
            if trig_ch1 == True:
                event = TriggerEvent(
                    sample_index=i,
                    sample_value=sample_ch1,
                    prev_value=int(signal_ch1[i-1]) if i > 0 else 0,
                    mode=self._config.trigger_ch1.mode
                )
                all_trigger_events.append(event)
            if trig_ch2 == True:
                event = TriggerEvent(
                    sample_index=i,
                    sample_value=sample_ch2,
                    prev_value=int(signal_ch2[i-1]) if i > 0 else 0,
                    mode=self._config.trigger_ch2.mode
                )
                all_trigger_events.append(event)
            
            # Alimentar scope
            if self._scope.state == ScopeState.ARMED:
                self._scope.process_sample(sample_ch1)
                
                if trigger_fired and triggers_processed < max_triggers:
                    self._scope.trigger()
                    
            elif self._scope.state == ScopeState.TRIGGERED:
                self._scope.process_sample(sample_ch1)
                
                if self._scope.state == ScopeState.TRANSFER:
                    # Captura completada, obtener datos
                    window = self._scope.get_captured_data()
                    if window is not None:
                        windows.append(window)
                        
                        # Enviar a RAM Writer
                        for j, sample in enumerate(window.samples):
                            is_last = (j == len(window.samples) - 1)
                            self._ram_writer.axis_write(int(sample), tlast=is_last)
                        
                        self._ram_writer.process_pending()
                        triggers_processed += 1
                    
                    # Re-armar scope para siguiente trigger
                    if triggers_processed < max_triggers:
                        self._scope.arm()
        
        return AcquisitionResult(
            windows=windows,
            trigger_events=all_trigger_events,
            total_samples=num_samples,
            bytes_written=self._ram_writer.status.bytes_written,
            axi_transactions=self._ram_writer.transactions
        )
    
    def plot_results(
        self,
        signal: np.ndarray,
        result: AcquisitionResult,
        output_file: Optional[str] = None
    ):
        """
        @brief Visualiza los resultados de la adquisición
        
        @param signal      Señal de entrada
        @param result      Resultado de la adquisición
        @param output_file Archivo de salida (None para mostrar)
        """
        fig, axes = plt.subplots(3, 1, figsize=(14, 10))
        
        # Panel 1: Señal completa con triggers
        ax1 = axes[0]
        ax1.plot(signal, 'b-', linewidth=0.5, label='Señal')
        ax1.axhline(y=self._config.trigger_ch1.threshold, color='r', 
                   linestyle='--', alpha=0.7, label='Umbral')
        
        for event in result.trigger_events:
            ax1.axvline(x=event.sample_index, color='g', alpha=0.5, linewidth=1)
        
        ax1.set_xlabel('Índice de muestra')
        ax1.set_ylabel('Amplitud')
        ax1.set_title(f'Señal completa - {len(result.trigger_events)} triggers detectados')
        ax1.legend()
        ax1.grid(True, alpha=0.3)
        
        # Panel 2: Ventanas capturadas
        ax2 = axes[1]
        colors = plt.cm.tab10(np.linspace(0, 1, max(len(result.windows), 1)))
        
        for i, window in enumerate(result.windows):
            x = np.arange(len(window.samples))
            ax2.plot(x, window.samples, color=colors[i], 
                    linewidth=0.8, label=f'Ventana {i+1}')
            ax2.axvline(x=window.trigger_index, color=colors[i], 
                       linestyle=':', alpha=0.7)
        
        ax2.set_xlabel('Índice dentro de ventana')
        ax2.set_ylabel('Amplitud')
        ax2.set_title(f'Ventanas capturadas (pre={self._config.scope_pre}, '
                     f'post={self._config.scope_post})')
        if result.windows:
            ax2.legend(loc='upper right')
        ax2.grid(True, alpha=0.3)
        
        # Panel 3: Estadísticas de transacciones AXI4
        ax3 = axes[2]
        
        if result.axi_transactions:
            addrs = [txn.address for txn in result.axi_transactions]
            lengths = [txn.burst_len for txn in result.axi_transactions]
            
            ax3.bar(range(len(addrs)), lengths, color='steelblue', alpha=0.7)
            ax3.set_xlabel('Número de transacción')
            ax3.set_ylabel('Longitud de burst')
            ax3.set_title(f'Transacciones AXI4 - {len(result.axi_transactions)} total, '
                         f'{result.bytes_written} bytes escritos')
        else:
            ax3.text(0.5, 0.5, 'Sin transacciones AXI4', 
                    ha='center', va='center', transform=ax3.transAxes)
        
        ax3.grid(True, alpha=0.3)
        
        plt.tight_layout()
        
        if output_file:
            plt.savefig(output_file, dpi=150)
            print(f"Gráfico guardado en {output_file}")
        else:
            plt.show()
    
    @property
    def config(self) -> SystemConfig:
        """Configuración actual"""
        return self._config


def generate_test_vectors(
    output_dir: str = ".",
    num_samples: int = 10000,
    num_pulses: int = 5
):
    """
    @brief Genera vectores de test para simulación RTL
    
    Crea archivos de estímulo y respuesta esperada para verificación.
    
    @param output_dir  Directorio de salida
    @param num_samples Número de muestras
    @param num_pulses  Número de pulsos en la señal
    """
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    # Configurar sistema
    config = SystemConfig(
        trigger_ch1=TriggerConfig(
            enable=True,
            threshold=600,
            mode=TriggerMode.RISING
        ),
        scope_pre=50,
        scope_post=100
    )
    
    system = AcquisitionSystem(config)
    
    # Generar señal
    pulse_positions = np.linspace(1000, num_samples - 1000, num_pulses).astype(int)
    signal = SignalGenerator.exponential_decay(
        num_samples,
        pulse_positions.tolist(),
        amplitude=600,
        baseline=512,
        noise_std=15
    )
    
    # Ejecutar adquisición
    result = system.run_acquisition(signal, max_triggers=num_pulses)
    
    # Escribir señal de entrada
    input_file = output_path / "acquisition_input.hex"
    with open(input_file, 'w') as f:
        f.write(f"// Acquisition stimulus - {num_samples} samples\n")
        f.write(f"// Pulses at: {pulse_positions.tolist()}\n\n")
        for sample in signal:
            f.write(f"{int(sample):04X}\n")
    
    # Escribir triggers esperados
    trigger_file = output_path / "expected_triggers.txt"
    with open(trigger_file, 'w') as f:
        f.write("// Expected trigger events\n\n")
        for i, event in enumerate(result.trigger_events):
            f.write(f"Trigger {i}: sample={event.sample_index}, "
                   f"value={event.sample_value}, mode={event.mode.name}\n")
    
    # Escribir ventanas esperadas
    window_file = output_path / "expected_windows.hex"
    with open(window_file, 'w') as f:
        f.write("// Expected capture windows\n\n")
        for i, window in enumerate(result.windows):
            f.write(f"// Window {i}: {len(window.samples)} samples, "
                   f"trigger at {window.trigger_index}\n")
            for sample in window.samples:
                f.write(f"{int(sample):04X}\n")
            f.write("\n")
    
    # Generar gráfico
    system.plot_results(signal, result, str(output_path / "acquisition_result.png"))
    
    # Resumen
    print(f"\nVectores de test generados en: {output_path}")
    print(f"  Señal de entrada: {input_file}")
    print(f"  Triggers esperados: {trigger_file}")
    print(f"  Ventanas esperadas: {window_file}")
    print(f"\nEstadísticas:")
    print(f"  Muestras totales: {num_samples}")
    print(f"  Pulsos generados: {num_pulses}")
    print(f"  Triggers detectados: {len(result.trigger_events)}")
    print(f"  Ventanas capturadas: {len(result.windows)}")
    print(f"  Bytes a memoria: {result.bytes_written}")


def main():
    """
    @brief Función principal de demostración
    """
    print("=" * 60)
    print("SIMULADOR DE SISTEMA DE ADQUISICIÓN")
    print("=" * 60)
    
    # Configurar sistema
    config = SystemConfig(
        trigger_ch1=TriggerConfig(
            enable=True,
            threshold=600,
            mode=TriggerMode.RISING
        ),
        trigger_ch2=TriggerConfig(
            enable=False  # Solo CH1
        ),
        trigger_or_mode=True,
        scope_pre=100,
        scope_post=200
    )
    
    system = AcquisitionSystem(config)
    
    # Test 1: Pulsos gaussianos
    print("\n--- Test 1: Pulsos Gaussianos ---")
    pulse_positions = [2000, 5000, 8000, 12000, 16000]
    signal = SignalGenerator.gaussian_pulse(
        20000, pulse_positions, amplitude=400, width=30
    )
    
    result = system.run_acquisition(signal)
    
    print(f"Triggers detectados: {len(result.trigger_events)}")
    print(f"Ventanas capturadas: {len(result.windows)}")
    print(f"Bytes escritos: {result.bytes_written}")
    
    system.plot_results(signal, result, "test1_gaussian.png")
    
    # Test 2: Pulsos de decaimiento exponencial
    print("\n--- Test 2: Decaimiento Exponencial ---")
    system.reset()
    
    signal = SignalGenerator.exponential_decay(
        20000, [3000, 7000, 11000], amplitude=500
    )
    
    result = system.run_acquisition(signal)
    
    print(f"Triggers detectados: {len(result.trigger_events)}")
    print(f"Ventanas capturadas: {len(result.windows)}")
    print(f"Bytes escritos: {result.bytes_written}")
    
    system.plot_results(signal, result, "test2_exponential.png")
    
    # Generar vectores para RTL
    print("\n--- Generando vectores de test para RTL ---")
    generate_test_vectors("test_vectors", num_samples=10000, num_pulses=4)
    
    print("\n" + "=" * 60)
    print("SIMULACIÓN COMPLETADA")
    print("=" * 60)


if __name__ == "__main__":
    main()
