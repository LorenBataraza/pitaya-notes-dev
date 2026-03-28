/**
 * @file scope_tlm.h
 * @brief Modelo TLM 2.0 Loosely-Timed del módulo Scope
 *
 * El Scope captura ventanas de datos alrededor de eventos de trigger.
 * Mantiene un buffer circular de pre-trigger y captura post-trigger
 * samples después de recibir la señal de trigger.
 */

#ifndef SCOPE_TLM_H
#define SCOPE_TLM_H

#include <systemc>
#include <tlm>
#include <deque>
#include <vector>
#include "common/axis_tlm_types.h"

namespace mcpha {

/**
 * @brief Configuración del Scope
 */
struct scope_config_t {
    bool enable;
    uint32_t pre_samples;   ///< Muestras antes del trigger
    uint32_t post_samples;  ///< Muestras después del trigger
    uint32_t buffer_depth;  ///< Profundidad total del buffer
    
    scope_config_t() 
        : enable(true)
        , pre_samples(100)
        , post_samples(100)
        , buffer_depth(4096) 
    {}
};

/**
 * @brief Estados de la FSM del Scope
 */
enum class ScopeState {
    IDLE,       ///< Esperando habilitación
    FILLING,    ///< Llenando buffer circular de pre-trigger
    ARMED,      ///< Buffer lleno, esperando trigger
    CAPTURING,  ///< Capturando post-trigger
    OUTPUTTING  ///< Enviando ventana capturada
};

/**
 * @brief Ventana capturada
 */
struct CapturedWindow {
    std::vector<int16_t> samples;
    uint32_t trigger_index;
    uint32_t pre_samples;
    uint32_t post_samples;
};

/**
 * @brief Modelo TLM del Scope
 */
class scope_tlm : public sc_core::sc_module {
public:
    SC_HAS_PROCESS(scope_tlm);

    scope_tlm(sc_core::sc_module_name name)
        : sc_module(name)
        , m_state(ScopeState::IDLE)
        , m_post_counter(0)
        , m_sample_count(0)
    {
    }

    /**
     * @brief Configura el scope
     */
    void configure(const scope_config_t& cfg) {
        m_config = cfg;
        std::cout << "Info: SCOPE: Configured: pre=" << cfg.pre_samples 
                  << ", post=" << cfg.post_samples << std::endl;
    }

    /**
     * @brief Reinicia el estado
     */
    void reset() {
        m_state = ScopeState::IDLE;
        m_circular_buffer.clear();
        m_capture_buffer.clear();
        m_post_counter = 0;
        m_sample_count = 0;
        m_windows.clear();
    }

    /**
     * @brief Habilita el scope (transición IDLE -> FILLING)
     */
    void enable() {
        if (m_state == ScopeState::IDLE) {
            m_state = ScopeState::FILLING;
            m_circular_buffer.clear();
            std::cout << "Info: SCOPE: Enabled, filling pre-trigger buffer" << std::endl;
        }
    }

    /**
     * @brief Procesa una muestra
     * @param sample Valor de la muestra
     * @param trigger Señal de trigger
     * @return Muestra de salida si hay datos disponibles
     */
    std::pair<bool, int16_t> process_sample(int16_t sample, bool trigger) {
        if (!m_config.enable) {
            return {false, 0};
        }

        m_sample_count++;
        
        switch (m_state) {
            case ScopeState::IDLE:
                return {false, 0};

            case ScopeState::FILLING:
                // Llenar buffer circular
                m_circular_buffer.push_back(sample);
                if (m_circular_buffer.size() > m_config.pre_samples) {
                    m_circular_buffer.pop_front();
                }
                // Transición a ARMED cuando el buffer está lleno
                if (m_circular_buffer.size() >= m_config.pre_samples) {
                    m_state = ScopeState::ARMED;
                    std::cout << "Info: SCOPE: Armed, waiting for trigger" << std::endl;
                }
                return {false, 0};

            case ScopeState::ARMED:
                // Mantener buffer circular actualizado
                m_circular_buffer.push_back(sample);
                if (m_circular_buffer.size() > m_config.pre_samples) {
                    m_circular_buffer.pop_front();
                }
                // Detectar trigger
                if (trigger) {
                    m_state = ScopeState::CAPTURING;
                    m_post_counter = 0;
                    // Copiar pre-trigger al buffer de captura
                    m_capture_buffer.clear();
                    for (auto s : m_circular_buffer) {
                        m_capture_buffer.push_back(s);
                    }
                    // La muestra actual es la primera post-trigger
                    m_capture_buffer.push_back(sample);
                    m_post_counter = 1;
                    std::cout << "Info: SCOPE: Trigger! Capturing post-trigger" << std::endl;
                }
                return {false, 0};

            case ScopeState::CAPTURING:
                m_capture_buffer.push_back(sample);
                m_post_counter++;
                if (m_post_counter >= m_config.post_samples) {
                    // Captura completa
                    CapturedWindow window;
                    window.samples = std::vector<int16_t>(
                        m_capture_buffer.begin(), m_capture_buffer.end());
                    window.trigger_index = m_config.pre_samples;
                    window.pre_samples = m_config.pre_samples;
                    window.post_samples = m_config.post_samples;
                    m_windows.push_back(window);
                    
                    m_state = ScopeState::OUTPUTTING;
                    m_output_index = 0;
                    std::cout << "Info: SCOPE: Capture complete, " 
                              << m_capture_buffer.size() << " samples" << std::endl;
                }
                return {false, 0};

            case ScopeState::OUTPUTTING:
                // Enviar muestras capturadas
                if (m_output_index < m_capture_buffer.size()) {
                    int16_t out = m_capture_buffer[m_output_index++];
                    bool last = (m_output_index >= m_capture_buffer.size());
                    if (last) {
                        // Volver a ARMED para siguiente trigger
                        m_state = ScopeState::ARMED;
                        m_circular_buffer.clear();
                        std::cout << "Info: SCOPE: Output complete, re-armed" << std::endl;
                    }
                    return {true, out};
                }
                return {false, 0};
        }
        
        return {false, 0};
    }

    /**
     * @brief Obtiene las ventanas capturadas
     */
    const std::vector<CapturedWindow>& get_windows() const {
        return m_windows;
    }

    /**
     * @brief Obtiene el estado actual
     */
    ScopeState get_state() const {
        return m_state;
    }

private:
    scope_config_t m_config;
    ScopeState m_state;
    
    std::deque<int16_t> m_circular_buffer;  ///< Buffer circular pre-trigger
    std::deque<int16_t> m_capture_buffer;   ///< Buffer de captura completa
    
    uint32_t m_post_counter;
    uint32_t m_sample_count;
    size_t m_output_index;
    
    std::vector<CapturedWindow> m_windows;
};

} // namespace mcpha

#endif // SCOPE_TLM_H
