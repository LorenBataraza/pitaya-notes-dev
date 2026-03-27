#!/usr/bin/env python3
"""
@file ram_writer_model.py
@brief Modelo funcional (ESL) del módulo RAM Writer

Este módulo implementa un modelo de referencia para el módulo axis_ram_writer.
Permite verificar el comportamiento esperado de las transacciones AXI4 y
la escritura a memoria, facilitando el debugging del bug conocido donde
el buffer queda sin escribir toda la salida.

@par Arquitectura modelada:
    AXI-Stream input → FIFO interno → Burst builder → AXI4 Master

@par Bug conocido:
    El buffer no escribe todos los datos esperados. Este modelo ayuda a
    identificar la causa raíz comparando con el RTL.
"""

from enum import IntEnum, auto
from dataclasses import dataclass, field
from typing import List, Optional, Tuple, Dict
from collections import deque
import numpy as np


class WriterState(IntEnum):
    """
    @brief Estados de la FSM del RAM Writer
    
    Replica los estados de writer_state_e en RTL.
    """
    WR_IDLE   = 0  ##< Esperando datos
    WR_CALC   = 1  ##< Calculando parámetros de burst
    WR_ADDR   = 2  ##< Enviando dirección (AW channel)
    WR_DATA   = 3  ##< Enviando datos (W channel)
    WR_RESP   = 4  ##< Esperando respuesta (B channel)
    WR_ERROR  = 5  ##< Estado de error


@dataclass
class Axi4WriteTransaction:
    """
    @brief Representa una transacción de escritura AXI4
    
    @param address      Dirección base de la transacción
    @param data         Lista de datos a escribir
    @param burst_len    Longitud del burst (AWLEN + 1)
    @param burst_size   Tamaño del beat (AWSIZE)
    @param burst_type   Tipo de burst (INCR=1)
    @param response     Respuesta recibida (BRESP)
    """
    address: int
    data: List[int]
    burst_len: int
    burst_size: int = 2  # 4 bytes por beat
    burst_type: int = 1  # INCR
    response: Optional[int] = None
    
    @property
    def total_bytes(self) -> int:
        """Bytes totales de la transacción"""
        return self.burst_len * (1 << self.burst_size)
    
    @property
    def end_address(self) -> int:
        """Dirección final de la transacción"""
        return self.address + self.total_bytes


@dataclass
class RamWriterConfig:
    """
    @brief Configuración del módulo RAM Writer
    
    @param enable         Habilita el módulo
    @param base_addr      Dirección base en DDR
    @param buffer_size    Tamaño del buffer en bytes
    @param max_burst_len  Longitud máxima de burst (1-256)
    """
    enable: bool = True
    base_addr: int = 0x1000_0000
    buffer_size: int = 0x0010_0000  # 1 MB
    max_burst_len: int = 256


@dataclass
class RamWriterStatus:
    """
    @brief Estado del módulo RAM Writer
    """
    busy: bool = False
    error: bool = False
    bytes_written: int = 0
    current_address: int = 0
    transactions_completed: int = 0
    state: WriterState = WriterState.WR_IDLE
    fifo_level: int = 0


class FifoModel:
    """
    @brief Modelo de FIFO interno
    
    Simula el comportamiento del FIFO entre la interfaz AXI-Stream
    y el generador de bursts AXI4.
    """
    
    def __init__(self, depth: int = 512, width: int = 32):
        """
        @brief Constructor del FIFO
        
        @param depth Profundidad en palabras
        @param width Ancho en bits
        """
        self._depth = depth
        self._width = width
        self._data: deque = deque(maxlen=depth)
        self._tlast_positions: List[int] = []  # Índices donde llegó TLAST
        self._write_count = 0
    
    def reset(self):
        """Reinicia el FIFO"""
        self._data.clear()
        self._tlast_positions.clear()
        self._write_count = 0
    
    def write(self, data: int, tlast: bool = False) -> bool:
        """
        @brief Escribe un dato al FIFO
        
        @param data  Dato a escribir
        @param tlast Indica fin de paquete
        @return True si fue exitoso
        """
        if self.is_full:
            return False
        
        self._data.append(data)
        self._write_count += 1
        
        if tlast:
            self._tlast_positions.append(len(self._data) - 1)
        
        return True
    
    def read(self) -> Optional[int]:
        """
        @brief Lee un dato del FIFO
        
        @return Dato leído o None si está vacío
        """
        if self.is_empty:
            return None
        
        data = self._data.popleft()
        
        # Actualizar posiciones de TLAST
        self._tlast_positions = [p - 1 for p in self._tlast_positions if p > 0]
        
        return data
    
    def read_burst(self, count: int) -> List[int]:
        """
        @brief Lee múltiples datos para un burst
        
        @param count Número de datos a leer
        @return Lista de datos
        """
        result = []
        for _ in range(min(count, len(self._data))):
            data = self.read()
            if data is not None:
                result.append(data)
        return result
    
    @property
    def is_full(self) -> bool:
        """FIFO está lleno"""
        return len(self._data) >= self._depth
    
    @property
    def is_empty(self) -> bool:
        """FIFO está vacío"""
        return len(self._data) == 0
    
    @property
    def level(self) -> int:
        """Nivel actual del FIFO"""
        return len(self._data)
    
    @property
    def has_complete_packet(self) -> bool:
        """Hay al menos un paquete completo (terminado con TLAST)"""
        return len(self._tlast_positions) > 0
    
    @property
    def space_available(self) -> int:
        """Espacio disponible"""
        return self._depth - len(self._data)


class RamWriterModel:
    """
    @brief Modelo funcional del módulo RAM Writer
    
    Simula el comportamiento del escritor de memoria, incluyendo:
    - Recepción de datos via AXI-Stream
    - Empaquetamiento en bursts AXI4
    - Manejo de límites de 4KB
    - Generación de transacciones
    
    @par Ejemplo de uso:
    @code{.py}
    writer = RamWriterModel()
    writer.configure(RamWriterConfig(base_addr=0x10000000))
    
    # Recibir datos desde AXI-Stream
    for i, sample in enumerate(samples):
        is_last = (i == len(samples) - 1)
        writer.axis_write(sample, tlast=is_last)
    
    # Procesar y generar transacciones
    writer.process_pending()
    
    # Verificar resultado
    print(f"Bytes escritos: {writer.status.bytes_written}")
    @endcode
    """
    
    # Constantes AXI4
    AXI4_4KB_BOUNDARY = 0x1000
    AXI4_MAX_BURST_LEN = 256
    
    def __init__(self, fifo_depth: int = 512, data_width: int = 32):
        """
        @brief Constructor del modelo
        
        @param fifo_depth  Profundidad del FIFO interno
        @param data_width  Ancho de datos en bits
        """
        self._fifo_depth = fifo_depth
        self._data_width = data_width
        self._bytes_per_beat = data_width // 8
        
        self._config = RamWriterConfig()
        self._status = RamWriterStatus()
        self._fifo = FifoModel(depth=fifo_depth, width=data_width)
        
        # Memoria simulada (para verificación)
        self._memory: Dict[int, int] = {}
        
        # Log de transacciones
        self._transactions: List[Axi4WriteTransaction] = []
        
        self.reset()
    
    def reset(self):
        """
        @brief Reinicia el estado del modelo
        """
        self._fifo.reset()
        self._memory.clear()
        self._transactions.clear()
        
        self._current_address = self._config.base_addr
        self._state = WriterState.WR_IDLE
        self._pending_samples: List[int] = []
        self._packet_complete = False
        
        self._update_status()
    
    def configure(self, config: RamWriterConfig):
        """
        @brief Aplica nueva configuración
        
        @param config Nueva configuración
        """
        self._config = config
        self._current_address = config.base_addr
        self._update_status()
    
    def axis_write(self, data: int, tlast: bool = False) -> bool:
        """
        @brief Escribe un dato desde la interfaz AXI-Stream
        
        Simula la recepción de un dato en el puerto AXI-Stream Slave.
        
        @param data  Dato de entrada
        @param tlast Señal TLAST (fin de paquete)
        @return True si el dato fue aceptado (TREADY alto)
        """
        if not self._config.enable:
            return False
        
        # Intentar escribir al FIFO
        success = self._fifo.write(data, tlast)
        
        if success and tlast:
            self._packet_complete = True
        
        return success
    
    def process_pending(self) -> List[Axi4WriteTransaction]:
        """
        @brief Procesa datos pendientes y genera transacciones AXI4
        
        Esta función simula el procesamiento que haría la FSM del RTL.
        
        @return Lista de transacciones generadas
        """
        new_transactions = []
        
        while self._fifo.level > 0 or self._pending_samples:
            # Determinar cuántos datos hay para el siguiente burst
            available = self._fifo.level + len(self._pending_samples)
            
            if available == 0:
                break
            
            # Calcular longitud del burst respetando límites
            burst_len = self._calculate_burst_length(available)
            
            if burst_len == 0:
                break
            
            # Leer datos para el burst
            burst_data = self._pending_samples[:burst_len]
            self._pending_samples = self._pending_samples[burst_len:]
            
            # Completar con datos del FIFO si es necesario
            remaining = burst_len - len(burst_data)
            if remaining > 0:
                burst_data.extend(self._fifo.read_burst(remaining))
            
            # Crear transacción
            txn = Axi4WriteTransaction(
                address=self._current_address,
                data=burst_data,
                burst_len=len(burst_data),
                burst_size=2,  # 4 bytes
                response=0  # OKAY
            )
            
            # Escribir a memoria simulada
            self._write_to_memory(txn)
            
            # Actualizar dirección
            self._current_address += txn.total_bytes
            
            # Verificar wrap-around del buffer
            if self._current_address >= (self._config.base_addr + 
                                         self._config.buffer_size):
                self._current_address = self._config.base_addr
            
            new_transactions.append(txn)
            self._transactions.append(txn)
        
        self._update_status()
        return new_transactions
    
    def _calculate_burst_length(self, available_samples: int) -> int:
        """
        @brief Calcula la longitud óptima del burst
        
        Considera:
        - Máximo burst de 256 beats
        - Límite de 4KB
        - Datos disponibles
        
        @param available_samples Muestras disponibles
        @return Longitud del burst (0 si no se puede hacer)
        """
        if available_samples == 0:
            return 0
        
        # Límite por configuración
        max_len = min(available_samples, self._config.max_burst_len)
        
        # Límite de 4KB
        addr_in_4kb = self._current_address & (self.AXI4_4KB_BOUNDARY - 1)
        bytes_to_boundary = self.AXI4_4KB_BOUNDARY - addr_in_4kb
        beats_to_boundary = bytes_to_boundary // self._bytes_per_beat
        
        burst_len = min(max_len, beats_to_boundary)
        
        return burst_len
    
    def _write_to_memory(self, txn: Axi4WriteTransaction):
        """
        @brief Escribe una transacción a la memoria simulada
        
        @param txn Transacción a escribir
        """
        addr = txn.address
        for data in txn.data:
            self._memory[addr] = data
            addr += self._bytes_per_beat
            self._status.bytes_written += self._bytes_per_beat
    
    def _update_status(self):
        """
        @brief Actualiza la estructura de status
        """
        self._status.state = self._state
        self._status.current_address = self._current_address
        self._status.transactions_completed = len(self._transactions)
        self._status.fifo_level = self._fifo.level
        self._status.busy = (self._fifo.level > 0 or 
                            len(self._pending_samples) > 0)
    
    def get_memory_contents(self, start: int, length: int) -> List[int]:
        """
        @brief Lee contenido de la memoria simulada
        
        @param start  Dirección inicial
        @param length Número de bytes
        @return Lista de datos
        """
        result = []
        for addr in range(start, start + length, self._bytes_per_beat):
            result.append(self._memory.get(addr, 0))
        return result
    
    def verify_data(self, expected: List[int]) -> Tuple[bool, str]:
        """
        @brief Verifica los datos escritos contra los esperados
        
        @param expected Lista de datos esperados
        @return Tupla (éxito, mensaje)
        """
        actual = self.get_memory_contents(
            self._config.base_addr,
            len(expected) * self._bytes_per_beat
        )
        
        if len(actual) != len(expected):
            return False, (f"Longitud incorrecta: esperado {len(expected)}, "
                          f"actual {len(actual)}")
        
        mismatches = []
        for i, (exp, act) in enumerate(zip(expected, actual)):
            if exp != act:
                mismatches.append((i, exp, act))
        
        if mismatches:
            msg = f"Encontradas {len(mismatches)} diferencias:\n"
            for idx, exp, act in mismatches[:10]:  # Mostrar primeras 10
                msg += f"  [{idx}]: esperado 0x{exp:08X}, actual 0x{act:08X}\n"
            if len(mismatches) > 10:
                msg += f"  ... y {len(mismatches) - 10} más\n"
            return False, msg
        
        return True, "Verificación exitosa"
    
    @property
    def status(self) -> RamWriterStatus:
        """Status actual"""
        return self._status
    
    @property
    def config(self) -> RamWriterConfig:
        """Configuración actual"""
        return self._config
    
    @property
    def transactions(self) -> List[Axi4WriteTransaction]:
        """Lista de transacciones completadas"""
        return self._transactions


def simulate_ram_writer(
    samples: List[int],
    base_addr: int = 0x1000_0000,
    buffer_size: int = 0x0010_0000,
    fifo_depth: int = 512,
    packet_sizes: Optional[List[int]] = None
) -> Tuple[RamWriterModel, bool, str]:
    """
    @brief Simula una secuencia de escritura completa
    
    @param samples       Lista de muestras a escribir
    @param base_addr     Dirección base
    @param buffer_size   Tamaño del buffer
    @param fifo_depth    Profundidad del FIFO
    @param packet_sizes  Tamaños de paquetes (None = un solo paquete)
    @return Tupla (modelo, éxito, mensaje)
    """
    writer = RamWriterModel(fifo_depth=fifo_depth)
    writer.configure(RamWriterConfig(
        enable=True,
        base_addr=base_addr,
        buffer_size=buffer_size
    ))
    
    # Determinar paquetes
    if packet_sizes is None:
        packet_sizes = [len(samples)]
    
    # Verificar que los tamaños suman correctamente
    total = sum(packet_sizes)
    if total != len(samples):
        return writer, False, f"Tamaños de paquete ({total}) != muestras ({len(samples)})"
    
    # Enviar datos
    sample_idx = 0
    for pkt_size in packet_sizes:
        for i in range(pkt_size):
            is_last = (i == pkt_size - 1)
            sample = samples[sample_idx]
            
            success = writer.axis_write(sample, tlast=is_last)
            if not success:
                return writer, False, f"FIFO overflow en muestra {sample_idx}"
            
            sample_idx += 1
        
        # Procesar paquete
        writer.process_pending()
    
    # Verificar
    success, msg = writer.verify_data(samples)
    
    return writer, success, msg


def generate_ram_writer_stimulus(
    filename: str,
    num_samples: int = 1000,
    packet_size: int = 256
):
    """
    @brief Genera archivos de estímulo para simulación RTL
    
    @param filename    Nombre base del archivo
    @param num_samples Número de muestras
    @param packet_size Tamaño de cada paquete
    """
    # Generar datos de prueba
    samples = list(range(num_samples))
    
    # Calcular paquetes
    num_packets = (num_samples + packet_size - 1) // packet_size
    packet_sizes = [packet_size] * (num_packets - 1)
    packet_sizes.append(num_samples - sum(packet_sizes))
    
    # Simular
    writer, success, msg = simulate_ram_writer(
        samples, packet_sizes=packet_sizes
    )
    
    # Escribir estímulo
    with open(filename, 'w') as f:
        f.write("// RAM Writer stimulus file\n")
        f.write(f"// {num_samples} samples, packet_size={packet_size}\n\n")
        
        sample_idx = 0
        for pkt_idx, pkt_size in enumerate(packet_sizes):
            f.write(f"// Packet {pkt_idx}: {pkt_size} samples\n")
            for i in range(pkt_size):
                tlast = 1 if (i == pkt_size - 1) else 0
                f.write(f"{samples[sample_idx]:08X} {tlast}\n")
                sample_idx += 1
            f.write("\n")
    
    # Escribir transacciones esperadas
    txn_filename = filename.replace('.hex', '_transactions.txt')
    with open(txn_filename, 'w') as f:
        f.write("// Expected AXI4 transactions\n\n")
        for i, txn in enumerate(writer.transactions):
            f.write(f"// Transaction {i}:\n")
            f.write(f"//   Address: 0x{txn.address:08X}\n")
            f.write(f"//   Length:  {txn.burst_len}\n")
            f.write(f"//   Bytes:   {txn.total_bytes}\n\n")
    
    print(f"Generated: {filename}")
    print(f"Generated: {txn_filename}")
    print(f"Simulation result: {msg}")
    print(f"Total transactions: {len(writer.transactions)}")
    print(f"Total bytes written: {writer.status.bytes_written}")


def analyze_potential_bugs():
    """
    @brief Análisis de posibles causas del bug conocido
    
    Ejecuta varios escenarios de prueba para identificar
    condiciones que podrían causar escrituras incompletas.
    """
    print("=" * 60)
    print("ANÁLISIS DE POSIBLES BUGS EN RAM WRITER")
    print("=" * 60)
    
    test_cases = [
        {
            "name": "Caso 1: Paquete que no llena un burst completo",
            "samples": list(range(100)),
            "packet_sizes": [100],
            "expected_issue": "¿Se vacía el FIFO con datos pendientes?"
        },
        {
            "name": "Caso 2: Paquete que cruza límite de 4KB",
            "samples": list(range(2048)),
            "packet_sizes": [2048],
            "base_addr": 0x10000F00,  # Cerca del límite
            "expected_issue": "¿Se maneja correctamente el split?"
        },
        {
            "name": "Caso 3: Múltiples paquetes pequeños",
            "samples": list(range(300)),
            "packet_sizes": [50, 100, 150],
            "expected_issue": "¿Se procesa cada TLAST correctamente?"
        },
        {
            "name": "Caso 4: FIFO casi lleno",
            "samples": list(range(500)),
            "packet_sizes": [500],
            "fifo_depth": 512,
            "expected_issue": "¿Hay race condition con FIFO lleno?"
        },
        {
            "name": "Caso 5: Último burst no múltiplo de ancho",
            "samples": list(range(257)),  # 256 + 1
            "packet_sizes": [257],
            "expected_issue": "¿Se escribe el beat final?"
        },
    ]
    
    for tc in test_cases:
        print(f"\n{tc['name']}")
        print("-" * 40)
        print(f"Hipótesis: {tc['expected_issue']}")
        
        kwargs = {
            "samples": tc["samples"],
            "packet_sizes": tc["packet_sizes"]
        }
        if "base_addr" in tc:
            kwargs["base_addr"] = tc["base_addr"]
        if "fifo_depth" in tc:
            kwargs["fifo_depth"] = tc["fifo_depth"]
        
        writer, success, msg = simulate_ram_writer(**kwargs)
        
        print(f"Resultado: {'PASS' if success else 'FAIL'}")
        print(f"  Muestras enviadas: {len(tc['samples'])}")
        print(f"  Bytes escritos: {writer.status.bytes_written}")
        print(f"  Bytes esperados: {len(tc['samples']) * 4}")
        print(f"  Transacciones: {len(writer.transactions)}")
        
        if not success:
            print(f"  Error: {msg}")


def main():
    """
    @brief Función principal
    """
    print("RAM Writer Model - Herramienta de debugging\n")
    
    # Ejecutar análisis de bugs
    analyze_potential_bugs()
    
    print("\n" + "=" * 60)
    print("GENERANDO ESTÍMULOS")
    print("=" * 60)
    
    # Generar estímulos
    generate_ram_writer_stimulus(
        'ram_writer_stimulus.hex',
        num_samples=1000,
        packet_size=256
    )


if __name__ == "__main__":
    main()
