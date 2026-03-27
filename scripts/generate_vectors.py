#!/usr/bin/env python3
"""
@file generate_vectors.py
@brief Generador de vectores de test para simulación RTL con QuestaSim

Genera archivos .hex y .txt compatibles con $readmemh y $readmemb
de SystemVerilog para comparación automática entre modelo y RTL.

@par Archivos generados:
    - *_stimulus.hex: Datos de entrada ($readmemh)
    - *_expected.hex: Respuesta esperada del modelo
    - *_config.txt: Configuración del test
    - *_report.txt: Resumen de la simulación del modelo
"""

import sys
import os
import argparse
from pathlib import Path
from dataclasses import dataclass
from typing import List, Tuple, Optional
import numpy as np

# Agregar path del proyecto
sys.path.insert(0, str(Path(__file__).parent.parent / "models" / "python"))

from trigger_model import TriggerModel, TriggerConfig, TriggerMode, TriggerEvent
from scope_model import ScopeModel, ScopeConfig, ScopeState, CapturedWindow
from ram_writer_model import RamWriterModel, RamWriterConfig


@dataclass
class TestVector:
    """
    @brief Contenedor de vectores de test
    """
    name: str
    stimulus: np.ndarray
    expected: np.ndarray
    config: dict
    metadata: dict


class VectorGenerator:
    """
    @brief Generador de vectores de test
    
    Crea archivos compatibles con QuestaSim para verificación RTL.
    """
    
    def __init__(self, output_dir: str = "vectors"):
        """
        @brief Constructor
        
        @param output_dir Directorio de salida para los vectores
        """
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
    
    def _write_hex_file(self, filename: str, data: np.ndarray, 
                        width: int = 16, comments: List[str] = None):
        """
        @brief Escribe archivo .hex compatible con $readmemh
        
        @param filename Nombre del archivo
        @param data     Array de datos
        @param width    Ancho en bits de cada dato
        @param comments Comentarios opcionales al inicio
        """
        filepath = self.output_dir / filename
        hex_width = (width + 3) // 4  # Caracteres hex necesarios
        
        with open(filepath, 'w') as f:
            if comments:
                for comment in comments:
                    f.write(f"// {comment}\n")
                f.write("\n")
            
            for i, val in enumerate(data):
                # Convertir a entero sin signo si es negativo
                if val < 0:
                    val = val + (1 << width)
                f.write(f"{int(val):0{hex_width}X}\n")
        
        return filepath
    
    def _write_config_file(self, filename: str, config: dict):
        """
        @brief Escribe archivo de configuración
        
        @param filename Nombre del archivo
        @param config   Diccionario de configuración
        """
        filepath = self.output_dir / filename
        
        with open(filepath, 'w') as f:
            f.write("// Test configuration file\n")
            f.write("// Format: PARAMETER VALUE\n\n")
            
            for key, value in config.items():
                if isinstance(value, bool):
                    f.write(f"{key} {1 if value else 0}\n")
                elif isinstance(value, (int, float)):
                    f.write(f"{key} {value}\n")
                else:
                    f.write(f"{key} {value}\n")
        
        return filepath
    
    def _write_report(self, filename: str, metadata: dict):
        """
        @brief Escribe reporte de simulación del modelo
        
        @param filename Nombre del archivo
        @param metadata Metadatos del test
        """
        filepath = self.output_dir / filename
        
        with open(filepath, 'w') as f:
            f.write("=" * 60 + "\n")
            f.write("TEST VECTOR GENERATION REPORT\n")
            f.write("=" * 60 + "\n\n")
            
            for key, value in metadata.items():
                f.write(f"{key}: {value}\n")
        
        return filepath

    # =========================================================================
    # Generadores de vectores para cada módulo
    # =========================================================================
    
    def generate_trigger_vectors(
        self,
        test_name: str = "trigger_basic",
        num_samples: int = 1000,
        threshold: int = 500,
        mode: TriggerMode = TriggerMode.RISING,
        signal_type: str = "ramp"
    ) -> TestVector:
        """
        @brief Genera vectores de test para el módulo trigger
        
        @param test_name    Nombre del test
        @param num_samples  Número de muestras
        @param threshold    Umbral de detección
        @param mode         Modo de trigger
        @param signal_type  Tipo de señal: "ramp", "pulse", "sine", "random"
        @return TestVector con estímulos y respuestas esperadas
        """
        # Generar señal de entrada según tipo
        if signal_type == "ramp":
            # Rampa que cruza el umbral
            signal = np.linspace(0, 1023, num_samples).astype(np.int16)
        elif signal_type == "pulse":
            # Pulsos gaussianos
            signal = np.ones(num_samples, dtype=np.int16) * 300
            pulse_pos = [num_samples // 4, num_samples // 2, 3 * num_samples // 4]
            for pos in pulse_pos:
                x = np.arange(num_samples)
                pulse = 500 * np.exp(-0.5 * ((x - pos) / 20) ** 2)
                signal = signal + pulse.astype(np.int16)
            signal = np.clip(signal, 0, 1023).astype(np.int16)
        elif signal_type == "sine":
            # Sinusoide
            t = np.linspace(0, 4 * np.pi, num_samples)
            signal = (512 + 400 * np.sin(t)).astype(np.int16)
        else:  # random
            signal = np.random.randint(0, 1024, num_samples, dtype=np.int16)
        
        # Configurar y ejecutar modelo
        trigger = TriggerModel()
        config = TriggerConfig(enable=True, threshold=threshold, mode=mode)
        trigger.configure(config)
        
        # Procesar y generar respuesta esperada
        # expected[i] = 1 si hay trigger en muestra i, 0 si no
        expected = np.zeros(num_samples, dtype=np.int16)
        events = trigger.process_samples(signal)
        
        for event in events:
            if 0 <= event.sample_index < num_samples:
                expected[event.sample_index] = 1
        
        # Escribir archivos
        comments = [
            f"Test: {test_name}",
            f"Samples: {num_samples}",
            f"Threshold: {threshold}",
            f"Mode: {mode.name}",
            f"Signal type: {signal_type}"
        ]
        
        self._write_hex_file(f"{test_name}_stimulus.hex", signal, 16, comments)
        self._write_hex_file(f"{test_name}_expected.hex", expected, 1, 
                            [f"Expected triggers: {len(events)}"])
        
        # Archivo de índices de trigger (más legible)
        trigger_indices = [e.sample_index for e in events]
        with open(self.output_dir / f"{test_name}_triggers.txt", 'w') as f:
            f.write(f"// Trigger events detected: {len(events)}\n")
            f.write("// Format: INDEX VALUE PREV_VALUE\n\n")
            for e in events:
                f.write(f"{e.sample_index} {e.sample_value} {e.prev_value}\n")
        
        # Configuración
        config_dict = {
            "ENABLE": True,
            "THRESHOLD": threshold,
            "MODE": mode.value,
            "NUM_SAMPLES": num_samples
        }
        self._write_config_file(f"{test_name}_config.txt", config_dict)
        
        # Reporte
        metadata = {
            "Test name": test_name,
            "Signal type": signal_type,
            "Number of samples": num_samples,
            "Threshold": threshold,
            "Mode": mode.name,
            "Triggers detected": len(events),
            "Min signal value": int(signal.min()),
            "Max signal value": int(signal.max())
        }
        self._write_report(f"{test_name}_report.txt", metadata)
        
        return TestVector(
            name=test_name,
            stimulus=signal,
            expected=expected,
            config=config_dict,
            metadata=metadata
        )
    
    def generate_scope_vectors(
        self,
        test_name: str = "scope_basic",
        num_samples: int = 2000,
        trigger_positions: List[int] = None,
        pre_samples: int = 50,
        post_samples: int = 100
    ) -> TestVector:
        """
        @brief Genera vectores de test para el módulo scope
        
        @param test_name         Nombre del test
        @param num_samples       Número total de muestras
        @param trigger_positions Posiciones de los triggers
        @param pre_samples       Muestras pre-trigger
        @param post_samples      Muestras post-trigger
        @return TestVector
        """
        if trigger_positions is None:
            trigger_positions = [500, 1200]
        
        # Generar señal
        t = np.linspace(0, 6 * np.pi, num_samples)
        signal = (512 + 300 * np.sin(t) + 30 * np.random.randn(num_samples))
        signal = np.clip(signal, 0, 1023).astype(np.int16)
        
        # Simular scope para cada trigger
        all_windows = []
        window_size = pre_samples + post_samples
        
        for trig_pos in trigger_positions:
            start = max(0, trig_pos - pre_samples)
            end = min(num_samples, trig_pos + post_samples)
            
            window = signal[start:end]
            
            # Pad si es necesario
            if len(window) < window_size:
                window = np.pad(window, (0, window_size - len(window)), 
                               mode='constant', constant_values=0)
            
            all_windows.append(window)
        
        # Concatenar todas las ventanas como salida esperada
        if all_windows:
            expected = np.concatenate(all_windows)
        else:
            expected = np.array([], dtype=np.int16)
        
        # Escribir archivos
        comments = [
            f"Test: {test_name}",
            f"Total samples: {num_samples}",
            f"Pre-trigger: {pre_samples}",
            f"Post-trigger: {post_samples}",
            f"Trigger positions: {trigger_positions}"
        ]
        
        self._write_hex_file(f"{test_name}_stimulus.hex", signal, 16, comments)
        self._write_hex_file(f"{test_name}_expected.hex", expected, 16,
                            [f"Expected windows: {len(all_windows)}"])
        
        # Archivo de triggers
        with open(self.output_dir / f"{test_name}_triggers.txt", 'w') as f:
            f.write("// Trigger positions (one per line)\n")
            for pos in trigger_positions:
                f.write(f"{pos}\n")
        
        # Configuración
        config_dict = {
            "PRE_SAMPLES": pre_samples,
            "POST_SAMPLES": post_samples,
            "NUM_TRIGGERS": len(trigger_positions),
            "WINDOW_SIZE": window_size,
            "NUM_SAMPLES": num_samples
        }
        self._write_config_file(f"{test_name}_config.txt", config_dict)
        
        # Reporte
        metadata = {
            "Test name": test_name,
            "Total samples": num_samples,
            "Pre-trigger samples": pre_samples,
            "Post-trigger samples": post_samples,
            "Window size": window_size,
            "Number of triggers": len(trigger_positions),
            "Trigger positions": trigger_positions,
            "Total output samples": len(expected)
        }
        self._write_report(f"{test_name}_report.txt", metadata)
        
        return TestVector(
            name=test_name,
            stimulus=signal,
            expected=expected,
            config=config_dict,
            metadata=metadata
        )
    
    def generate_ram_writer_vectors(
        self,
        test_name: str = "ram_writer_basic",
        num_samples: int = 500,
        packet_sizes: List[int] = None
    ) -> TestVector:
        """
        @brief Genera vectores de test para el módulo ram_writer
        
        @param test_name    Nombre del test
        @param num_samples  Número total de muestras
        @param packet_sizes Tamaños de los paquetes (None = un solo paquete)
        @return TestVector
        """
        if packet_sizes is None:
            packet_sizes = [num_samples]
        
        # Generar datos de prueba (patrón reconocible)
        data = np.arange(num_samples, dtype=np.int32)
        
        # Generar archivo con marcas TLAST
        # Formato: DATA TLAST
        tlast_marks = np.zeros(num_samples, dtype=np.int8)
        
        idx = 0
        for pkt_size in packet_sizes:
            idx += pkt_size
            if idx <= num_samples:
                tlast_marks[idx - 1] = 1
        
        # Escribir estímulo con TLAST
        with open(self.output_dir / f"{test_name}_stimulus.hex", 'w') as f:
            f.write(f"// Test: {test_name}\n")
            f.write(f"// Format: DATA[31:0] TLAST[0]\n")
            f.write(f"// Packets: {packet_sizes}\n\n")
            
            for i in range(num_samples):
                f.write(f"{int(data[i]):08X} {tlast_marks[i]}\n")
        
        # Expected: mismos datos (verificar que todos lleguen a memoria)
        self._write_hex_file(f"{test_name}_expected.hex", data, 32,
                            [f"Expected: {num_samples} words written"])
        
        # Configuración
        config_dict = {
            "NUM_SAMPLES": num_samples,
            "NUM_PACKETS": len(packet_sizes),
            "PACKET_SIZES": str(packet_sizes),
            "BASE_ADDR": "0x10000000",
            "BUFFER_SIZE": "0x00100000"
        }
        self._write_config_file(f"{test_name}_config.txt", config_dict)
        
        # Reporte
        expected_bytes = num_samples * 4
        expected_bursts = (num_samples + 255) // 256  # Aprox
        
        metadata = {
            "Test name": test_name,
            "Total samples": num_samples,
            "Packet sizes": packet_sizes,
            "Expected bytes": expected_bytes,
            "Estimated bursts": expected_bursts
        }
        self._write_report(f"{test_name}_report.txt", metadata)
        
        return TestVector(
            name=test_name,
            stimulus=data,
            expected=data,  # Mismo dato
            config=config_dict,
            metadata=metadata
        )


def generate_all_vectors(output_dir: str = "sim/vectors"):
    """
    @brief Genera todos los vectores de test para regresión completa
    
    @param output_dir Directorio de salida
    """
    gen = VectorGenerator(output_dir)
    
    print("=" * 60)
    print("GENERACIÓN DE VECTORES DE TEST")
    print("=" * 60)
    
    # =========================================================================
    # Vectores del Trigger
    # =========================================================================
    print("\n--- Vectores del Trigger ---")
    
    tests = [
        ("trigger_rising_ramp", 1000, 500, TriggerMode.RISING, "ramp"),
        ("trigger_falling_ramp", 1000, 500, TriggerMode.FALLING, "ramp"),
        ("trigger_both_sine", 2000, 512, TriggerMode.BOTH, "sine"),
        ("trigger_rising_pulse", 3000, 600, TriggerMode.RISING, "pulse"),
        ("trigger_level_random", 1000, 400, TriggerMode.LEVEL, "random"),
    ]
    
    for name, samples, thresh, mode, sig in tests:
        vec = gen.generate_trigger_vectors(name, samples, thresh, mode, sig)
        print(f"  {name}: {vec.metadata['Triggers detected']} triggers")
    
    # =========================================================================
    # Vectores del Scope
    # =========================================================================
    print("\n--- Vectores del Scope ---")
    
    scope_tests = [
        ("scope_single", 2000, [1000], 50, 100),
        ("scope_multiple", 5000, [1000, 2500, 4000], 100, 200),
        ("scope_edge_start", 1000, [50], 100, 100),  # Trigger cerca del inicio
        ("scope_edge_end", 1000, [950], 100, 100),   # Trigger cerca del final
        ("scope_large_pre", 2000, [1500], 500, 100), # Pre-trigger grande
    ]
    
    for name, samples, trigs, pre, post in scope_tests:
        vec = gen.generate_scope_vectors(name, samples, trigs, pre, post)
        print(f"  {name}: {vec.metadata['Number of triggers']} windows, "
              f"{vec.metadata['Total output samples']} samples")
    
    # =========================================================================
    # Vectores del RAM Writer (casos de debugging)
    # =========================================================================
    print("\n--- Vectores del RAM Writer ---")
    
    rw_tests = [
        ("rw_basic_256", 256, [256]),           # Un burst exacto
        ("rw_partial_100", 100, [100]),          # Burst parcial
        ("rw_partial_257", 257, [257]),          # 256 + 1 (H2: último beat)
        ("rw_multi_packet", 500, [100, 150, 250]), # Múltiples TLAST
        ("rw_near_4kb", 1024, [1024]),           # Cerca de límite 4KB
        ("rw_stress", 2000, [2000]),             # Muchos bursts
    ]
    
    for name, samples, packets in rw_tests:
        vec = gen.generate_ram_writer_vectors(name, samples, packets)
        print(f"  {name}: {samples} samples, packets={packets}")
    
    print("\n" + "=" * 60)
    print(f"Vectores generados en: {output_dir}")
    print("=" * 60)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generador de vectores de test")
    parser.add_argument("-o", "--output", default="sim/vectors",
                       help="Directorio de salida")
    parser.add_argument("-m", "--module", choices=["trigger", "scope", "ram_writer", "all"],
                       default="all", help="Módulo para generar vectores")
    
    args = parser.parse_args()
    
    generate_all_vectors(args.output)
