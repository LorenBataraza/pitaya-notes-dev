/**
 * @file ram_writer_tlm.h
 * @brief Modelo TLM 2.0 Loosely-Timed del módulo RAM Writer
 *
 * El RAM Writer recibe datos por AXI-Stream y los escribe en memoria
 * via AXI4 usando bursts. Maneja el empaquetado de datos y la
 * generación de transacciones AXI4.
 */

#ifndef RAM_WRITER_TLM_H
#define RAM_WRITER_TLM_H

#include <systemc>
#include <tlm>
#include <vector>
#include <deque>
#include <cstdint>
#include "common/axis_tlm_types.h"

namespace mcpha {

/**
 * @brief Configuración del RAM Writer
 */
struct ram_writer_config_t {
    uint64_t base_addr;      ///< Dirección base en memoria
    uint64_t buffer_size;    ///< Tamaño del buffer en bytes
    uint32_t burst_len;      ///< Longitud máxima de burst (beats)
    uint32_t data_width;     ///< Ancho de datos AXI (bits)
    
    ram_writer_config_t()
        : base_addr(0x10000000)
        , buffer_size(0x00100000)  // 1 MB
        , burst_len(16)
        , data_width(64)
    {}
};

/**
 * @brief Transacción AXI4 Write
 */
struct Axi4WriteTransaction {
    uint64_t address;
    std::vector<uint64_t> data;
    uint32_t burst_len;
    bool completed;
    
    Axi4WriteTransaction() : address(0), burst_len(0), completed(false) {}
    
    /**
     * @brief Verifica si el burst cruza límite de 4KB
     */
    bool crosses_4kb() const {
        uint64_t end_addr = address + burst_len * 8 - 1;
        return (address & ~0xFFFULL) != (end_addr & ~0xFFFULL);
    }
};

/**
 * @brief Estados de la FSM
 */
enum class RamWriterState {
    IDLE,
    COLLECTING,
    BURST_WRITE,
    FLUSH
};

/**
 * @brief Modelo TLM del RAM Writer
 */
class ram_writer_tlm : public sc_core::sc_module {
public:
    SC_HAS_PROCESS(ram_writer_tlm);

    ram_writer_tlm(sc_core::sc_module_name name)
        : sc_module(name)
        , m_state(RamWriterState::IDLE)
        , m_write_ptr(0)
        , m_total_bytes(0)
        , m_burst_count(0)
    {
    }

    /**
     * @brief Configura el RAM Writer
     */
    void configure(const ram_writer_config_t& cfg) {
        m_config = cfg;
        m_write_ptr = cfg.base_addr;
        std::cout << "Info: RAM_WRITER: Configured: base=0x" << std::hex 
                  << cfg.base_addr << ", burst_len=" << std::dec 
                  << cfg.burst_len << std::endl;
    }

    /**
     * @brief Reinicia el estado
     */
    void reset() {
        m_state = RamWriterState::IDLE;
        m_write_ptr = m_config.base_addr;
        m_fifo.clear();
        m_total_bytes = 0;
        m_burst_count = 0;
        m_transactions.clear();
    }

    /**
     * @brief Habilita el escritor
     */
    void enable() {
        if (m_state == RamWriterState::IDLE) {
            m_state = RamWriterState::COLLECTING;
            std::cout << "Info: RAM_WRITER: Enabled" << std::endl;
        }
    }

    /**
     * @brief Recibe una muestra por AXI-Stream
     * @param data Datos (16 bits por muestra, empaquetados a 64 bits)
     * @param tlast Indica fin de paquete
     * @return true si se aceptó la muestra
     */
    bool write_sample(int16_t data, bool tlast) {
        if (m_state == RamWriterState::IDLE) {
            return false;
        }

        // Acumular en FIFO
        m_fifo.push_back(data);

        // Empaquetar 4 muestras de 16 bits en 64 bits
        if (m_fifo.size() >= 4) {
            pack_and_queue();
        }

        // Verificar si hay que generar burst
        if (m_packed_data.size() >= m_config.burst_len) {
            generate_burst(false);
        }

        // TLAST fuerza flush
        if (tlast) {
            flush();
        }

        return true;
    }

    /**
     * @brief Fuerza flush de datos pendientes
     */
    void flush() {
        // Empaquetar datos restantes en FIFO
        while (m_fifo.size() >= 4) {
            pack_and_queue();
        }
        
        // Padding si quedan muestras sueltas
        if (!m_fifo.empty()) {
            while (m_fifo.size() < 4) {
                m_fifo.push_back(0);
            }
            pack_and_queue();
        }

        // Generar burst con lo que quede
        if (!m_packed_data.empty()) {
            generate_burst(true);
        }

        std::cout << "Info: RAM_WRITER: Flushed" << std::endl;
    }

    /**
     * @brief Obtiene las transacciones generadas
     */
    const std::vector<Axi4WriteTransaction>& get_transactions() const {
        return m_transactions;
    }

    /**
     * @brief Obtiene el total de bytes escritos
     */
    uint64_t get_total_bytes() const {
        return m_total_bytes;
    }

    /**
     * @brief Obtiene el número de bursts generados
     */
    uint32_t get_burst_count() const {
        return m_burst_count;
    }

    /**
     * @brief Simula la memoria para verificación
     */
    const std::vector<uint64_t>& get_memory() const {
        return m_memory;
    }

private:
    ram_writer_config_t m_config;
    RamWriterState m_state;
    
    std::deque<int16_t> m_fifo;           ///< FIFO de entrada
    std::vector<uint64_t> m_packed_data;  ///< Datos empaquetados
    
    uint64_t m_write_ptr;
    uint64_t m_total_bytes;
    uint32_t m_burst_count;
    
    std::vector<Axi4WriteTransaction> m_transactions;
    std::vector<uint64_t> m_memory;  ///< Memoria simulada

    /**
     * @brief Empaqueta 4 muestras de 16 bits en 64 bits
     */
    void pack_and_queue() {
        if (m_fifo.size() < 4) return;

        uint64_t packed = 0;
        for (int i = 0; i < 4; i++) {
            uint16_t sample = static_cast<uint16_t>(m_fifo.front());
            m_fifo.pop_front();
            packed |= (static_cast<uint64_t>(sample) << (i * 16));
        }
        
        m_packed_data.push_back(packed);
    }

    /**
     * @brief Genera una transacción de burst
     */
    void generate_burst(bool is_flush) {
        if (m_packed_data.empty()) return;

        uint32_t burst_len = std::min(
            static_cast<uint32_t>(m_packed_data.size()),
            m_config.burst_len
        );

        // Verificar límite de 4KB
        uint64_t end_addr = m_write_ptr + burst_len * 8;
        uint64_t boundary = (m_write_ptr & ~0xFFFULL) + 0x1000;
        
        if (end_addr > boundary) {
            // Dividir el burst en el límite de 4KB
            uint32_t first_burst = (boundary - m_write_ptr) / 8;
            if (first_burst > 0) {
                create_transaction(first_burst);
            }
            // El resto se hará en el siguiente ciclo
        } else {
            create_transaction(burst_len);
        }
    }

    /**
     * @brief Crea una transacción
     */
    void create_transaction(uint32_t burst_len) {
        Axi4WriteTransaction txn;
        txn.address = m_write_ptr;
        txn.burst_len = burst_len;
        
        for (uint32_t i = 0; i < burst_len && !m_packed_data.empty(); i++) {
            txn.data.push_back(m_packed_data.front());
            m_memory.push_back(m_packed_data.front());
            m_packed_data.erase(m_packed_data.begin());
        }
        
        txn.completed = true;
        m_transactions.push_back(txn);
        
        m_write_ptr += burst_len * 8;
        m_total_bytes += burst_len * 8;
        m_burst_count++;
    }
};

} // namespace mcpha

#endif // RAM_WRITER_TLM_H
