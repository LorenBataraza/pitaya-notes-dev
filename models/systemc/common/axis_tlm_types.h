/**
 * @file axis_tlm_types.h
 * @brief Tipos y transacciones TLM 2.0 para interfaces AXI-Stream
 *
 * Define las estructuras de transacción compatibles con TLM 2.0 para
 * modelar interfaces AXI-Stream. Soporta tanto Loosely-Timed (LT) como
 * Approximately-Timed (AT) coding styles.
 *
 * @par Uso con TLM 2.0:
 * Las transacciones usan tlm_generic_payload con extensiones personalizadas
 * para los campos específicos de AXI-Stream (TLAST, TKEEP, etc.)
 */

#ifndef AXIS_TLM_TYPES_H
#define AXIS_TLM_TYPES_H

#include <systemc>
#include <tlm>
#include <tlm_utils/simple_initiator_socket.h>
#include <tlm_utils/simple_target_socket.h>

namespace mcpha {

/**
 * @brief Extensión TLM para señales AXI-Stream
 *
 * Agrega campos específicos de AXI-Stream al payload genérico de TLM.
 * Usa el mecanismo de extensiones de TLM 2.0 para mantener compatibilidad.
 */
class axis_extension : public tlm::tlm_extension<axis_extension> {
public:
    /// Indica fin de paquete (TLAST)
    bool tlast;
    
    /// Indica datos válidos (para modelar bubbles)
    bool tvalid;
    
    /// Índice de la muestra dentro de la secuencia
    uint32_t sample_index;
    
    /// ID del paquete (para trazabilidad)
    uint32_t packet_id;
    
    /// Constructor por defecto
    axis_extension() : tlast(false), tvalid(true), sample_index(0), packet_id(0) {}
    
    /// Clonar la extensión (requerido por TLM 2.0)
    virtual tlm_extension_base* clone() const override {
        axis_extension* ext = new axis_extension();
        ext->tlast = this->tlast;
        ext->tvalid = this->tvalid;
        ext->sample_index = this->sample_index;
        ext->packet_id = this->packet_id;
        return ext;
    }
    
    /// Copiar desde otra extensión (requerido por TLM 2.0)
    virtual void copy_from(const tlm_extension_base& ext) override {
        const axis_extension& other = static_cast<const axis_extension&>(ext);
        this->tlast = other.tlast;
        this->tvalid = other.tvalid;
        this->sample_index = other.sample_index;
        this->packet_id = other.packet_id;
    }
};

/**
 * @brief Estructura de configuración para el trigger
 *
 * Replica la estructura trigger_config_t del RTL.
 */
struct trigger_config_t {
    bool enable;
    uint8_t mode;       // 0=RISING, 1=FALLING, 2=BOTH, 3=LEVEL
    int16_t threshold;
    uint8_t ch_mask;
    
    trigger_config_t() : enable(true), mode(0), threshold(0), ch_mask(0x03) {}
};

/**
 * @brief Extensión TLM para eventos de trigger
 *
 * Contiene información sobre eventos de trigger detectados.
 */
class trigger_event_extension : public tlm::tlm_extension<trigger_event_extension> {
public:
    /// Indica si se detectó un trigger
    bool trigger_detected;
    
    /// Índice de la muestra donde ocurrió el trigger
    uint32_t trigger_index;
    
    /// Valor de la muestra que causó el trigger
    int16_t trigger_value;
    
    /// Valor de la muestra anterior
    int16_t prev_value;
    
    trigger_event_extension() 
        : trigger_detected(false), trigger_index(0), trigger_value(0), prev_value(0) {}
    
    virtual tlm_extension_base* clone() const override {
        trigger_event_extension* ext = new trigger_event_extension();
        ext->trigger_detected = this->trigger_detected;
        ext->trigger_index = this->trigger_index;
        ext->trigger_value = this->trigger_value;
        ext->prev_value = this->prev_value;
        return ext;
    }
    
    virtual void copy_from(const tlm_extension_base& ext) override {
        const trigger_event_extension& other = 
            static_cast<const trigger_event_extension&>(ext);
        this->trigger_detected = other.trigger_detected;
        this->trigger_index = other.trigger_index;
        this->trigger_value = other.trigger_value;
        this->prev_value = other.prev_value;
    }
};

/**
 * @brief Modos de detección del trigger
 */
enum class TriggerMode : uint8_t {
    RISING  = 0,  ///< Flanco ascendente
    FALLING = 1,  ///< Flanco descendente
    BOTH    = 2,  ///< Ambos flancos
    LEVEL   = 3   ///< Por nivel
};

/**
 * @brief Constantes del sistema
 */
namespace constants {
    constexpr double CLK_PERIOD_NS = 8.0;           // 125 MHz
    constexpr uint32_t DATA_WIDTH = 16;              // bits
    constexpr uint32_t SAMPLE_RATE_HZ = 125000000;   // 125 MSa/s
    constexpr uint32_t PIPE_STAGES = 2;              // Pipeline del trigger
}

/**
 * @brief Helper para crear transacciones AXI-Stream
 *
 * @param data Valor de la muestra
 * @param tlast Indica fin de paquete
 * @param index Índice de la muestra
 * @return Puntero a la transacción (caller debe liberar)
 */
inline tlm::tlm_generic_payload* create_axis_transaction(
    int16_t data, 
    bool tlast = false,
    uint32_t index = 0
) {
    // Crear payload
    tlm::tlm_generic_payload* trans = new tlm::tlm_generic_payload();
    
    // Configurar datos
    int16_t* data_ptr = new int16_t;
    *data_ptr = data;
    trans->set_data_ptr(reinterpret_cast<unsigned char*>(data_ptr));
    trans->set_data_length(sizeof(int16_t));
    trans->set_streaming_width(sizeof(int16_t));
    trans->set_command(tlm::TLM_WRITE_COMMAND);
    trans->set_response_status(tlm::TLM_INCOMPLETE_RESPONSE);
    
    // Agregar extensión AXI-Stream
    axis_extension* ext = new axis_extension();
    ext->tlast = tlast;
    ext->tvalid = true;
    ext->sample_index = index;
    trans->set_extension(ext);
    
    return trans;
}

/**
 * @brief Liberar una transacción creada con create_axis_transaction
 */
inline void free_axis_transaction(tlm::tlm_generic_payload* trans) {
    if (trans) {
        // Liberar datos
        int16_t* data_ptr = reinterpret_cast<int16_t*>(trans->get_data_ptr());
        delete data_ptr;
        
        // Liberar extensiones
        axis_extension* ext = trans->get_extension<axis_extension>();
        if (ext) {
            trans->clear_extension(ext);
            delete ext;
        }
        
        trigger_event_extension* trig_ext = 
            trans->get_extension<trigger_event_extension>();
        if (trig_ext) {
            trans->clear_extension(trig_ext);
            delete trig_ext;
        }
        
        delete trans;
    }
}

} // namespace mcpha

#endif // AXIS_TLM_TYPES_H
