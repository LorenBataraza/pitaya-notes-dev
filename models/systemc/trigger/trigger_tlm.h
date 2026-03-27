/**
 * @file trigger_tlm.h
 * @brief Modelo TLM 2.0 Loosely-Timed del detector de eventos (trigger)
 *
 * Este módulo implementa el modelo funcional del trigger usando TLM 2.0
 * con estilo Loosely-Timed (LT). El modelo puede usarse para:
 * - Validación funcional rápida (más rápido que RTL)
 * - Generación de transacciones de referencia
 * - Co-simulación con RTL via DPI
 *
 * @par Arquitectura TLM:
 * @verbatim
 *   Initiator          Target             Initiator
 *   (Stimulus) ------> (Trigger) -------> (Monitor)
 *     socket            model              socket
 * @endverbatim
 *
 * @par Estilo de codificación:
 * Loosely-Timed (LT): Las transacciones completan en un quantum de tiempo.
 * El timing se anota con sc_time pero no se modela ciclo a ciclo.
 *
 * @par Hipótesis de refinamiento Python -> TLM:
 * - H1: El pipeline de 2 etapas se modela como latencia de 2 ciclos
 * - H2: El re-armado automático se mantiene como en Python
 * - H3: La comparación signed se implementa igual
 */

#ifndef TRIGGER_TLM_H
#define TRIGGER_TLM_H

#include <systemc>
#include <tlm>
#include <tlm_utils/simple_target_socket.h>
#include <tlm_utils/simple_initiator_socket.h>
#include <queue>
#include <fstream>
#include "axis_tlm_types.h"

namespace mcpha {

/**
 * @brief Modelo TLM del detector de eventos (trigger)
 *
 * Implementa la lógica de detección de trigger con interfaz TLM 2.0.
 * Recibe muestras por el socket de entrada y genera eventos de trigger
 * por el socket de salida.
 *
 * @par Ejemplo de uso:
 * @code
 * trigger_tlm trigger("trigger");
 * trigger.configure(config);
 * stimulus_gen.socket.bind(trigger.input_socket);
 * trigger.output_socket.bind(monitor.socket);
 * @endcode
 */
class trigger_tlm : public sc_core::sc_module {
public:
    /// Socket de entrada (recibe muestras)
    tlm_utils::simple_target_socket<trigger_tlm> input_socket;
    
    /// Socket de salida (passthrough + eventos)
    tlm_utils::simple_initiator_socket<trigger_tlm> output_socket;

    SC_HAS_PROCESS(trigger_tlm);

    /**
     * @brief Constructor del módulo
     * @param name Nombre de la instancia SystemC
     */
    trigger_tlm(sc_core::sc_module_name name)
        : sc_module(name)
        , input_socket("input_socket")
        , output_socket("output_socket")
        , m_armed(true)
        , m_sample_count(0)
        , m_trigger_count(0)
    {
        // Registrar callback para transacciones entrantes
        input_socket.register_b_transport(this, &trigger_tlm::b_transport);
        
        // Inicializar pipeline
        for (int i = 0; i < PIPE_STAGES; i++) {
            m_pipeline[i] = 0;
            m_valid_pipe[i] = false;
        }
    }

    /**
     * @brief Configura el trigger
     * @param cfg Estructura de configuración
     */
    void configure(const trigger_config_t& cfg) {
        m_config = cfg;
        SC_REPORT_INFO("TRIGGER", 
            (std::string("Configured: enable=") + std::to_string(cfg.enable) +
             ", mode=" + std::to_string(cfg.mode) +
             ", threshold=" + std::to_string(cfg.threshold)).c_str());
    }

    /**
     * @brief Reinicia el estado interno
     */
    void reset() {
        m_armed = true;
        m_sample_count = 0;
        for (int i = 0; i < PIPE_STAGES; i++) {
            m_pipeline[i] = 0;
            m_valid_pipe[i] = false;
        }
        m_trigger_events.clear();
        SC_REPORT_INFO("TRIGGER", "Reset completed");
    }

    /**
     * @brief Obtiene la lista de eventos de trigger detectados
     * @return Vector con información de cada evento
     */
    const std::vector<trigger_event_extension>& get_trigger_events() const {
        return m_trigger_events;
    }

    /**
     * @brief Obtiene el número de triggers detectados
     */
    uint32_t get_trigger_count() const {
        return m_trigger_count;
    }

    /**
     * @brief Exporta eventos a archivo para comparación con RTL
     * @param filename Nombre del archivo de salida
     */
    void export_events(const std::string& filename) {
        std::ofstream ofs(filename);
        ofs << "# Trigger events from TLM model\n";
        ofs << "# sample_index trigger_value prev_value\n";
        for (const auto& evt : m_trigger_events) {
            ofs << evt.trigger_index << " " 
                << evt.trigger_value << " "
                << evt.prev_value << "\n";
        }
        ofs.close();
        SC_REPORT_INFO("TRIGGER", 
            (std::string("Exported ") + std::to_string(m_trigger_events.size()) + 
             " events to " + filename).c_str());
    }

private:
    /// Constante: etapas de pipeline
    static constexpr int PIPE_STAGES = 2;
    
    /// Configuración actual
    trigger_config_t m_config;
    
    /// Pipeline de muestras (modela registros RTL)
    int16_t m_pipeline[PIPE_STAGES];
    bool m_valid_pipe[PIPE_STAGES];
    
    /// Estado de armado
    bool m_armed;
    
    /// Contadores
    uint32_t m_sample_count;
    uint32_t m_trigger_count;
    
    /// Registro de eventos
    std::vector<trigger_event_extension> m_trigger_events;

    /**
     * @brief Blocking transport (LT style)
     *
     * Procesa una transacción de muestra y genera el resultado.
     * La latencia se anota en el delay de retorno.
     *
     * @param trans Transacción entrante
     * @param delay Anotación de tiempo (se actualiza con latencia)
     */
    void b_transport(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay) {
        // Extraer datos de la transacción
        int16_t* data_ptr = reinterpret_cast<int16_t*>(trans.get_data_ptr());
        if (!data_ptr) {
            trans.set_response_status(tlm::TLM_GENERIC_ERROR_RESPONSE);
            return;
        }
        
        int16_t sample = *data_ptr;
        
        // Extraer extensión AXI-Stream
        axis_extension* ext = trans.get_extension<axis_extension>();
        bool tlast = ext ? ext->tlast : false;
        uint32_t idx = ext ? ext->sample_index : m_sample_count;
        
        // Procesar la muestra
        bool trigger_out = process_sample(sample, true, idx);
        
        // Anotar latencia del pipeline
        delay += sc_core::sc_time(PIPE_STAGES * constants::CLK_PERIOD_NS, sc_core::SC_NS);
        
        // Si hay trigger, agregar extensión de evento
        if (trigger_out) {
            trigger_event_extension* trig_ext = new trigger_event_extension();
            trig_ext->trigger_detected = true;
            trig_ext->trigger_index = idx;
            trig_ext->trigger_value = sample;
            trig_ext->prev_value = m_pipeline[PIPE_STAGES - 1];
            trans.set_extension(trig_ext);
        }
        
        // Forward la transacción al socket de salida (passthrough)
        output_socket->b_transport(trans, delay);
        
        // Marcar respuesta OK
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
        
        m_sample_count++;
    }

    /**
     * @brief Procesa una muestra a través del pipeline
     *
     * Replica la lógica del modelo Python process_sample().
     *
     * @param sample Valor de la muestra
     * @param valid Indica si la muestra es válida
     * @param index Índice de la muestra
     * @return true si se detectó un trigger
     */
    bool process_sample(int16_t sample, bool valid, uint32_t index) {
        if (!m_config.enable) {
            return false;
        }
        
        // Shift del pipeline (como en RTL)
        for (int i = PIPE_STAGES - 1; i > 0; i--) {
            m_pipeline[i] = m_pipeline[i - 1];
            m_valid_pipe[i] = m_valid_pipe[i - 1];
        }
        m_pipeline[0] = sample;
        m_valid_pipe[0] = valid;
        
        // Verificar si tenemos datos válidos para comparar
        if (!m_valid_pipe[PIPE_STAGES - 2]) {
            return false;
        }
        
        // Obtener muestras para comparación
        int16_t prev_sample = m_pipeline[PIPE_STAGES - 1];
        int16_t curr_sample = m_pipeline[PIPE_STAGES - 2];
        
        // Detectar evento
        bool event_detected = detect_threshold_crossing(prev_sample, curr_sample);
        
        bool trigger_out = false;
        
        if (m_armed && event_detected) {
            trigger_out = true;
            m_armed = false;
            m_trigger_count++;
            
            // Registrar evento
            trigger_event_extension evt;
            evt.trigger_detected = true;
            evt.trigger_index = index;
            evt.trigger_value = curr_sample;
            evt.prev_value = prev_sample;
            m_trigger_events.push_back(evt);
            
            SC_REPORT_INFO("TRIGGER", 
                (std::string("Event detected at index ") + std::to_string(index) +
                 ": prev=" + std::to_string(prev_sample) + 
                 ", curr=" + std::to_string(curr_sample)).c_str());
        } else if (!event_detected) {
            m_armed = true;  // Re-armar
        }
        
        return trigger_out;
    }

    /**
     * @brief Detecta cruce de umbral según el modo configurado
     *
     * Replica la lógica del modelo Python _detect_threshold_crossing().
     *
     * @param prev Muestra anterior
     * @param curr Muestra actual
     * @return true si se detectó cruce
     */
    bool detect_threshold_crossing(int16_t prev, int16_t curr) {
        int16_t threshold = m_config.threshold;
        
        bool rising_edge = (prev < threshold) && (curr >= threshold);
        bool falling_edge = (prev >= threshold) && (curr < threshold);
        
        switch (static_cast<TriggerMode>(m_config.mode)) {
            case TriggerMode::RISING:
                return rising_edge;
            case TriggerMode::FALLING:
                return falling_edge;
            case TriggerMode::BOTH:
                return rising_edge || falling_edge;
            case TriggerMode::LEVEL:
                return curr >= threshold;
            default:
                return false;
        }
    }
};

/**
 * @brief Generador de estímulos para el trigger
 *
 * Módulo initiator que genera transacciones de muestra para testing.
 */
class trigger_stimulus_gen : public sc_core::sc_module {
public:
    tlm_utils::simple_initiator_socket<trigger_stimulus_gen> socket;

    SC_HAS_PROCESS(trigger_stimulus_gen);

    trigger_stimulus_gen(sc_core::sc_module_name name)
        : sc_module(name)
        , socket("socket")
    {
        SC_THREAD(generate_thread);
    }

    /**
     * @brief Carga muestras desde archivo
     * @param filename Archivo con muestras (una por línea, hex)
     */
    void load_samples(const std::string& filename) {
        std::ifstream ifs(filename);
        std::string line;
        m_samples.clear();
        
        while (std::getline(ifs, line)) {
            if (line.empty() || line[0] == '#' || line[0] == '/') continue;
            int16_t sample;
            std::sscanf(line.c_str(), "%hx", (unsigned short*)&sample);
            m_samples.push_back(sample);
        }
        
        SC_REPORT_INFO("STIMULUS", 
            (std::string("Loaded ") + std::to_string(m_samples.size()) + 
             " samples from " + filename).c_str());
    }

    /**
     * @brief Genera rampa de muestras
     * @param start Valor inicial
     * @param end Valor final
     * @param count Número de muestras
     */
    void generate_ramp(int16_t start, int16_t end, uint32_t count) {
        m_samples.clear();
        double step = static_cast<double>(end - start) / (count - 1);
        for (uint32_t i = 0; i < count; i++) {
            m_samples.push_back(static_cast<int16_t>(start + i * step));
        }
    }

    /**
     * @brief Genera señal senoidal
     * @param amplitude Amplitud
     * @param offset Offset DC
     * @param periods Número de períodos
     * @param samples_per_period Muestras por período
     */
    void generate_sine(int16_t amplitude, int16_t offset, 
                       uint32_t periods, uint32_t samples_per_period) {
        m_samples.clear();
        uint32_t total = periods * samples_per_period;
        for (uint32_t i = 0; i < total; i++) {
            double angle = 2.0 * M_PI * i / samples_per_period;
            int16_t value = static_cast<int16_t>(
                offset + amplitude * std::sin(angle)
            );
            m_samples.push_back(value);
        }
    }

    /// Inicia la generación
    void start() { m_start_event.notify(); }
    
    /// Espera a que termine
    void wait_done() { sc_core::wait(m_done_event); }

private:
    std::vector<int16_t> m_samples;
    sc_core::sc_event m_start_event;
    sc_core::sc_event m_done_event;

    void generate_thread() {
        while (true) {
            sc_core::wait(m_start_event);
            
            for (uint32_t i = 0; i < m_samples.size(); i++) {
                // Crear transacción
                bool is_last = (i == m_samples.size() - 1);
                tlm::tlm_generic_payload* trans = 
                    create_axis_transaction(m_samples[i], is_last, i);
                
                // Enviar
                sc_core::sc_time delay = sc_core::SC_ZERO_TIME;
                socket->b_transport(*trans, delay);
                
                // Avanzar tiempo
                sc_core::wait(delay);
                
                // Liberar transacción
                free_axis_transaction(trans);
            }
            
            m_done_event.notify();
        }
    }
};

/**
 * @brief Monitor para capturar transacciones de salida
 */
class trigger_monitor : public sc_core::sc_module {
public:
    tlm_utils::simple_target_socket<trigger_monitor> socket;

    trigger_monitor(sc_core::sc_module_name name)
        : sc_module(name)
        , socket("socket")
        , m_trigger_count(0)
    {
        socket.register_b_transport(this, &trigger_monitor::b_transport);
    }

    uint32_t get_trigger_count() const { return m_trigger_count; }
    
    const std::vector<int16_t>& get_samples() const { return m_samples; }

private:
    uint32_t m_trigger_count;
    std::vector<int16_t> m_samples;

    void b_transport(tlm::tlm_generic_payload& trans, sc_core::sc_time& delay) {
        int16_t* data = reinterpret_cast<int16_t*>(trans.get_data_ptr());
        if (data) {
            m_samples.push_back(*data);
        }
        
        trigger_event_extension* evt = 
            trans.get_extension<trigger_event_extension>();
        if (evt && evt->trigger_detected) {
            m_trigger_count++;
        }
        
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
    }
};

} // namespace mcpha

#endif // TRIGGER_TLM_H
