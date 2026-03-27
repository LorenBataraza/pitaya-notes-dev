#!/usr/bin/env python3
"""
@file scope_model.py
@brief Modelo funcional (ESL) del módulo de captura (scope)

Este módulo implementa un modelo de referencia en Python para el módulo
axis_scope. Simula el comportamiento del buffer circular y la captura
de ventanas de pre/post-trigger.

@par Arquitectura interna modelada:
    Buffer circular → Trigger capture → Transfer FSM
"""

from enum import IntEnum, auto
from dataclasses import dataclass, field
from typing import List, Optional, Tuple
import numpy as np
from collections import deque


class ScopeState(IntEnum):
    """
    @brief Estados de la máquina de estados del Scope
    
    Replica los estados de scope_state_e en RTL.
    """
    IDLE      = 0  ##< Inactivo
    ARMED     = 1  ##< Armado, esperando trigger
    TRIGGERED = 2  ##< Capturando post-trigger
    TRANSFER  = 3  ##< Transfiriendo datos
    DONE      = 4  ##< Captura completa


@dataclass
class ScopeConfig:
    """
    @brief Configuración del módulo Scope
    
    @param enable       Habilita/deshabilita el módulo
    @param arm          Arma el trigger para comenzar captura
    @param pre_samples  Número de muestras a capturar antes del trigger
    @param post_samples Número de muestras a capturar después del trigger
    """
    enable: bool = True
    arm: bool = False
    pre_samples: int = 100
    post_samples: int = 100


@dataclass
class ScopeStatus:
    """
    @brief Estado del módulo Scope
    """
    armed: bool = False
    triggered: bool = False
    done: bool = False
    sample_count: int = 0
    state: ScopeState = ScopeState.IDLE


@dataclass
class CapturedWindow:
    """
    @brief Representa una ventana de datos capturada
    
    @param samples         Array de muestras capturadas
    @param trigger_index   Índice del trigger dentro de la ventana
    @param pre_samples     Muestras antes del trigger
    @param post_samples    Muestras después del trigger
    """
    samples: np.ndarray
    trigger_index: int
    pre_samples: int
    post_samples: int
    
    @property
    def total_samples(self) -> int:
        """Número total de muestras en la ventana"""
        return len(self.samples)
    
    def get_pre_trigger_data(self) -> np.ndarray:
        """Retorna solo las muestras de pre-trigger"""
        return self.samples[:self.trigger_index]
    
    def get_post_trigger_data(self) -> np.ndarray:
        """Retorna solo las muestras de post-trigger"""
        return self.samples[self.trigger_index:]


class ScopeModel:
    """
    @brief Modelo funcional del módulo de captura (scope)
    
    Implementa un buffer circular para almacenar muestras de pre-trigger
    y una máquina de estados para coordinar la captura.
    
    @par Ejemplo de uso:
    @code{.py}
    scope = ScopeModel(buffer_depth=4096)
    scope.configure(ScopeConfig(pre_samples=100, post_samples=200, arm=True))
    
    # Simular llegada de muestras
    for sample in samples:
        scope.process_sample(sample)
        if trigger_detected:
            scope.trigger()
    
    # Obtener datos capturados
    window = scope.get_captured_data()
    @endcode
    """
    
    def __init__(self, buffer_depth: int = 4096):
        """
        @brief Constructor del modelo de scope
        
        @param buffer_depth Profundidad del buffer circular
        """
        self._buffer_depth = buffer_depth
        self._config = ScopeConfig()
        self._status = ScopeStatus()
        self.reset()
    
    def reset(self):
        """
        @brief Reinicia completamente el estado del modelo
        """
        self._circular_buffer = deque(maxlen=self._buffer_depth)
        self._post_buffer: List[int] = []
        self._trigger_position = 0
        self._post_count = 0
        self._state = ScopeState.IDLE
        self._update_status()
    
    def configure(self, config: ScopeConfig):
        """
        @brief Aplica nueva configuración al scope
        
        @param config Nueva configuración
        """
        self._config = config
        
        # Validar configuración
        if config.pre_samples > self._buffer_depth:
            raise ValueError(
                f"pre_samples ({config.pre_samples}) excede "
                f"buffer_depth ({self._buffer_depth})"
            )
        
        # Transición de estados según configuración
        if config.enable and config.arm and self._state == ScopeState.IDLE:
            self._state = ScopeState.ARMED
            self._circular_buffer.clear()
            self._post_buffer.clear()
            self._post_count = 0
        elif not config.enable:
            self._state = ScopeState.IDLE
        
        self._update_status()
    
    def process_sample(self, sample: int) -> bool:
        """
        @brief Procesa una nueva muestra de entrada
        
        @param sample Valor de la muestra (entero)
        @return True si la muestra fue aceptada
        """
        if self._state == ScopeState.ARMED:
            # En estado ARMED: llenar buffer circular
            self._circular_buffer.append(sample)
            return True
            
        elif self._state == ScopeState.TRIGGERED:
            # En estado TRIGGERED: capturar post-trigger
            self._post_buffer.append(sample)
            self._post_count += 1
            
            # Verificar si completamos post-trigger
            if self._post_count >= self._config.post_samples:
                self._state = ScopeState.TRANSFER
                self._update_status()
            
            return True
        
        return False
    
    def trigger(self) -> bool:
        """
        @brief Procesa un evento de trigger
        
        Marca la posición actual del buffer y transiciona al estado
        TRIGGERED para comenzar a capturar post-trigger.
        
        @return True si el trigger fue aceptado
        """
        if self._state != ScopeState.ARMED:
            return False
        
        # Registrar posición del trigger
        self._trigger_position = len(self._circular_buffer)
        
        # Transicionar a TRIGGERED
        self._state = ScopeState.TRIGGERED
        self._post_count = 0
        self._post_buffer.clear()
        
        self._update_status()
        return True
    
    def get_captured_data(self) -> Optional[CapturedWindow]:
        """
        @brief Obtiene los datos capturados
        
        Solo disponible cuando el estado es TRANSFER o DONE.
        
        @return CapturedWindow con los datos, o None si no hay datos
        """
        if self._state not in [ScopeState.TRANSFER, ScopeState.DONE]:
            return None
        
        # Calcular cuántas muestras de pre-trigger tenemos
        available_pre = min(self._config.pre_samples, 
                          len(self._circular_buffer))
        
        # Extraer pre-trigger del buffer circular
        pre_data = list(self._circular_buffer)[-available_pre:] if available_pre > 0 else []
        
        # Combinar pre + post
        all_samples = np.array(pre_data + self._post_buffer, dtype=np.int16)
        
        # Transicionar a DONE
        self._state = ScopeState.DONE
        self._update_status()
        
        return CapturedWindow(
            samples=all_samples,
            trigger_index=available_pre,
            pre_samples=available_pre,
            post_samples=len(self._post_buffer)
        )
    
    def arm(self):
        """
        @brief Arma el scope para una nueva captura
        """
        if self._config.enable and self._state in [ScopeState.IDLE, ScopeState.DONE]:
            self._config.arm = True
            self._state = ScopeState.ARMED
            self._circular_buffer.clear()
            self._post_buffer.clear()
            self._post_count = 0
            self._update_status()
    
    def _update_status(self):
        """
        @brief Actualiza la estructura de status
        """
        self._status.armed = (self._state == ScopeState.ARMED)
        self._status.triggered = (self._state in [ScopeState.TRIGGERED, 
                                                   ScopeState.TRANSFER,
                                                   ScopeState.DONE])
        self._status.done = (self._state == ScopeState.DONE)
        self._status.state = self._state
        self._status.sample_count = self._post_count
    
    @property
    def state(self) -> ScopeState:
        """Estado actual"""
        return self._state
    
    @property
    def status(self) -> ScopeStatus:
        """Status completo"""
        return self._status
    
    @property
    def config(self) -> ScopeConfig:
        """Configuración actual"""
        return self._config


def simulate_acquisition(
    signal: np.ndarray,
    trigger_indices: List[int],
    pre_samples: int = 100,
    post_samples: int = 200,
    buffer_depth: int = 4096
) -> List[CapturedWindow]:
    """
    @brief Simula una adquisición completa
    
    Procesa una señal completa y captura ventanas para cada trigger.
    
    @param signal          Array de muestras de entrada
    @param trigger_indices Índices donde ocurren los triggers
    @param pre_samples     Muestras de pre-trigger
    @param post_samples    Muestras de post-trigger
    @param buffer_depth    Profundidad del buffer circular
    @return Lista de ventanas capturadas
    """
    windows = []
    
    for trig_idx in trigger_indices:
        scope = ScopeModel(buffer_depth=buffer_depth)
        config = ScopeConfig(
            enable=True,
            arm=True,
            pre_samples=pre_samples,
            post_samples=post_samples
        )
        scope.configure(config)
        
        # Alimentar muestras
        # Primero, las muestras de pre-trigger
        start_idx = max(0, trig_idx - buffer_depth)
        
        for i in range(start_idx, len(signal)):
            sample = int(signal[i])
            
            if scope.state == ScopeState.ARMED:
                scope.process_sample(sample)
                
                # Trigger en el índice correcto
                if i == trig_idx:
                    scope.trigger()
                    
            elif scope.state == ScopeState.TRIGGERED:
                scope.process_sample(sample)
                
                if scope.state == ScopeState.TRANSFER:
                    break
        
        # Obtener datos capturados
        window = scope.get_captured_data()
        if window is not None:
            windows.append(window)
    
    return windows


def generate_scope_stimulus(
    filename: str,
    num_samples: int = 1000,
    num_triggers: int = 3,
    pre_samples: int = 50,
    post_samples: int = 100
):
    """
    @brief Genera archivo de estímulo para simulación RTL del scope
    
    @param filename      Nombre del archivo de salida
    @param num_samples   Número total de muestras
    @param num_triggers  Número de eventos de trigger
    @param pre_samples   Muestras de pre-trigger
    @param post_samples  Muestras de post-trigger
    """
    # Generar señal de prueba
    t = np.linspace(0, 4*np.pi, num_samples)
    signal = 512 + 300 * np.sin(t) + 50 * np.random.randn(num_samples)
    signal = np.clip(signal, 0, 1023).astype(np.int16)
    
    # Generar triggers distribuidos
    trigger_spacing = num_samples // (num_triggers + 1)
    trigger_indices = [trigger_spacing * (i + 1) for i in range(num_triggers)]
    
    # Simular captura
    windows = simulate_acquisition(
        signal, trigger_indices, pre_samples, post_samples
    )
    
    # Escribir archivo de estímulo
    with open(filename, 'w') as f:
        f.write(f"// Scope stimulus file\n")
        f.write(f"// pre_samples={pre_samples}, post_samples={post_samples}\n")
        f.write(f"// Triggers at: {trigger_indices}\n\n")
        
        for i, sample in enumerate(signal):
            trig_mark = " // TRIGGER" if i in trigger_indices else ""
            f.write(f"{int(sample):04X}{trig_mark}\n")
    
    # Escribir archivo de respuesta esperada
    resp_filename = filename.replace('.hex', '_expected.hex')
    with open(resp_filename, 'w') as f:
        f.write(f"// Expected capture windows\n\n")
        
        for w_idx, window in enumerate(windows):
            f.write(f"// Window {w_idx}: {len(window.samples)} samples\n")
            f.write(f"// Trigger at index {window.trigger_index}\n")
            
            for i, sample in enumerate(window.samples):
                marker = " // <-- TRIGGER" if i == window.trigger_index else ""
                f.write(f"{int(sample):04X}{marker}\n")
            
            f.write("\n")
    
    print(f"Generated: {filename}")
    print(f"Generated: {resp_filename}")
    print(f"Captured {len(windows)} windows")


def main():
    """
    @brief Función principal para demostración
    """
    import matplotlib.pyplot as plt
    
    # Configuración
    buffer_depth = 1024
    pre_samples = 100
    post_samples = 200
    
    # Generar señal de prueba
    num_samples = 2000
    t = np.linspace(0, 6*np.pi, num_samples)
    signal = 512 + 300 * np.sin(t) + 30 * np.random.randn(num_samples)
    signal = np.clip(signal, 0, 1023).astype(np.int16)
    
    # Definir triggers
    trigger_indices = [300, 800, 1400]
    
    # Simular
    windows = simulate_acquisition(
        signal, trigger_indices, pre_samples, post_samples, buffer_depth
    )
    
    # Visualizar
    fig, axes = plt.subplots(2, 1, figsize=(14, 8))
    
    # Señal completa con triggers marcados
    ax1 = axes[0]
    ax1.plot(signal, 'b-', linewidth=0.8, label='Señal')
    for idx in trigger_indices:
        ax1.axvline(x=idx, color='r', linestyle='--', alpha=0.7, 
                   label='Trigger' if idx == trigger_indices[0] else '')
    ax1.set_xlabel('Índice de muestra')
    ax1.set_ylabel('Amplitud')
    ax1.set_title('Señal completa con triggers')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    
    # Ventanas capturadas
    ax2 = axes[1]
    colors = ['green', 'orange', 'purple']
    for i, window in enumerate(windows):
        x = np.arange(len(window.samples))
        ax2.plot(x, window.samples, color=colors[i % len(colors)], 
                linewidth=0.8, label=f'Ventana {i+1}')
        ax2.axvline(x=window.trigger_index, color=colors[i % len(colors)], 
                   linestyle=':', alpha=0.7)
    
    ax2.set_xlabel('Índice dentro de ventana')
    ax2.set_ylabel('Amplitud')
    ax2.set_title(f'Ventanas capturadas (pre={pre_samples}, post={post_samples})')
    ax2.legend()
    ax2.grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig('scope_model_output.png', dpi=150)
    print("Gráfico guardado en scope_model_output.png")
    
    # Generar estímulos
    generate_scope_stimulus('scope_stimulus.hex', 1000, 2, 50, 100)


if __name__ == "__main__":
    main()
