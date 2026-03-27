/**
 * @file tb_trigger_tlm.cpp
 * @brief Testbench SystemC para el modelo TLM del trigger
 *
 * Este testbench carga los mismos vectores .hex que usa el testbench RTL,
 * ejecuta el modelo TLM-LT y compara los resultados. Esto permite validar
 * que el modelo TLM es funcionalmente equivalente antes de pasar al RTL.
 *
 * @par Flujo de verificación:
 * @verbatim
 *   Vectores .hex ──► TLM Model ──► Comparación ──► PASS/FAIL
 *        │                              │
 *        └──────► RTL Model ────────────┘
 *                 (mismos vectores)
 * @endverbatim
 *
 * @par Compilación:
 * @code
 *   g++ -std=c++17 -I$SYSTEMC_HOME/include -L$SYSTEMC_HOME/lib-linux64 \
 *       tb_trigger_tlm.cpp -lsystemc -o tb_trigger_tlm
 * @endcode
 *
 * @par Ejecución:
 * @code
 *   ./tb_trigger_tlm --vectors=../sim/vectors --test=trigger_rising_ramp
 * @endcode
 */

#include <systemc>
#include <tlm>
#include <fstream>
#include <sstream>
#include <vector>
#include <string>
#include <iomanip>
#include <cstdlib>
#include <getopt.h>

#include "trigger/trigger_tlm.h"

using namespace sc_core;
using namespace mcpha;

/**
 * @brief Clase para cargar vectores de test desde archivos .hex
 */
class VectorLoader {
public:
    /**
     * @brief Carga archivo de estímulos (.hex)
     * @param filename Ruta al archivo
     * @return Vector de muestras (int16_t)
     */
    static std::vector<int16_t> load_stimulus(const std::string& filename) {
        std::vector<int16_t> samples;
        std::ifstream ifs(filename);
        
        if (!ifs.is_open()) {
            SC_REPORT_ERROR("LOADER", 
                ("Cannot open stimulus file: " + filename).c_str());
            return samples;
        }
        
        std::string line;
        while (std::getline(ifs, line)) {
            // Ignorar comentarios y líneas vacías
            if (line.empty() || line[0] == '/' || line[0] == '#') continue;
            
            // Parsear valor hexadecimal
            uint16_t val;
            if (std::sscanf(line.c_str(), "%hx", &val) == 1) {
                samples.push_back(static_cast<int16_t>(val));
            }
        }
        
        SC_REPORT_INFO("LOADER", 
            ("Loaded " + std::to_string(samples.size()) + 
             " samples from " + filename).c_str());
        
        return samples;
    }
    
    /**
     * @brief Carga archivo de triggers esperados (.hex)
     * @param filename Ruta al archivo
     * @return Vector de booleanos (true = trigger esperado)
     */
    static std::vector<bool> load_expected(const std::string& filename) {
        std::vector<bool> expected;
        std::ifstream ifs(filename);
        
        if (!ifs.is_open()) {
            SC_REPORT_ERROR("LOADER", 
                ("Cannot open expected file: " + filename).c_str());
            return expected;
        }
        
        std::string line;
        while (std::getline(ifs, line)) {
            if (line.empty() || line[0] == '/' || line[0] == '#') continue;
            
            int val;
            if (std::sscanf(line.c_str(), "%d", &val) == 1) {
                expected.push_back(val != 0);
            }
        }
        
        SC_REPORT_INFO("LOADER", 
            ("Loaded " + std::to_string(expected.size()) + 
             " expected values from " + filename).c_str());
        
        return expected;
    }
    
    /**
     * @brief Carga archivo de configuración (.txt)
     * @param filename Ruta al archivo
     * @return Estructura de configuración
     */
    static trigger_config_t load_config(const std::string& filename) {
        trigger_config_t cfg;
        std::ifstream ifs(filename);
        
        if (!ifs.is_open()) {
            SC_REPORT_WARNING("LOADER", 
                ("Cannot open config file: " + filename + 
                 ", using defaults").c_str());
            return cfg;
        }
        
        std::string line;
        while (std::getline(ifs, line)) {
            if (line.empty() || line[0] == '/' || line[0] == '#') continue;
            
            char param[64];
            int value;
            if (std::sscanf(line.c_str(), "%s %d", param, &value) == 2) {
                std::string p(param);
                if (p == "ENABLE") cfg.enable = (value != 0);
                else if (p == "THRESHOLD") cfg.threshold = static_cast<int16_t>(value);
                else if (p == "MODE") cfg.mode = static_cast<uint8_t>(value);
            }
        }
        
        SC_REPORT_INFO("LOADER", 
            ("Config: threshold=" + std::to_string(cfg.threshold) + 
             ", mode=" + std::to_string(cfg.mode)).c_str());
        
        return cfg;
    }
};

/**
 * @brief Monitor/Scoreboard que captura y compara resultados
 */
class TriggerScoreboard : public sc_module {
public:
    tlm_utils::simple_target_socket<TriggerScoreboard> socket;
    
    SC_HAS_PROCESS(TriggerScoreboard);
    
    TriggerScoreboard(sc_module_name name)
        : sc_module(name)
        , socket("socket")
        , m_sample_count(0)
        , m_triggers_detected(0)
        , m_triggers_expected(0)
        , m_true_positives(0)
        , m_false_positives(0)
        , m_false_negatives(0)
    {
        socket.register_b_transport(this, &TriggerScoreboard::b_transport);
    }
    
    /**
     * @brief Configura los valores esperados para comparación
     */
    void set_expected(const std::vector<bool>& expected) {
        m_expected = expected;
        // Contar triggers esperados
        m_triggers_expected = 0;
        for (bool e : expected) {
            if (e) m_triggers_expected++;
        }
    }
    
    /**
     * @brief Imprime resumen de resultados
     */
    void print_summary(std::ostream& os) {
        os << "\n";
        os << "+-----------------------------------------------------------+\n";
        os << "|                 RESUMEN DE RESULTADOS (TLM)               |\n";
        os << "+-----------------------------------------------------------+\n";
        os << "|  Muestras procesadas:   " << std::setw(33) << m_sample_count << " |\n";
        os << "+-----------------------------------------------------------+\n";
        os << "|  Triggers esperados:    " << std::setw(33) << m_triggers_expected << " |\n";
        os << "|  Triggers detectados:   " << std::setw(33) << m_triggers_detected << " |\n";
        os << "|  True Positives:        " << std::setw(33) << m_true_positives << " |\n";
        os << "|  False Positives:       " << std::setw(33) << m_false_positives << " |\n";
        os << "|  False Negatives:       " << std::setw(33) << m_false_negatives << " |\n";
        os << "+-----------------------------------------------------------+\n";
        
        int mismatches = m_false_positives + m_false_negatives;
        if (mismatches == 0) {
            os << "|  >>> PASS: Todos los triggers coinciden                  |\n";
        } else {
            os << "|  >>> FAIL: " << std::setw(3) << mismatches 
               << " discrepancias encontradas                   |\n";
        }
        os << "+-----------------------------------------------------------+\n";
        os << "\n";
    }
    
    bool passed() const {
        return (m_false_positives + m_false_negatives) == 0;
    }
    
    int get_mismatches() const {
        return m_false_positives + m_false_negatives;
    }

private:
    std::vector<bool> m_expected;
    uint32_t m_sample_count;
    uint32_t m_triggers_detected;
    uint32_t m_triggers_expected;
    uint32_t m_true_positives;
    uint32_t m_false_positives;
    uint32_t m_false_negatives;
    
    // Pipeline delay buffer para alinear con RTL
    static constexpr int PIPE_DELAY = 2;
    std::deque<bool> m_delay_queue;
    
    void b_transport(tlm::tlm_generic_payload& trans, sc_time& delay) {
        // Extraer información de trigger
        trigger_event_extension* evt = 
            trans.get_extension<trigger_event_extension>();
        
        bool trigger_detected = (evt && evt->trigger_detected);
        
        if (trigger_detected) {
            m_triggers_detected++;
        }
        
        // Comparar con esperado (considerando delay del pipeline)
        // El modelo TLM ya incluye el delay, así que comparamos directo
        if (m_sample_count < m_expected.size()) {
            bool expected = m_expected[m_sample_count];
            
            if (trigger_detected && expected) {
                m_true_positives++;
            } else if (trigger_detected && !expected) {
                m_false_positives++;
                std::cout << "[" << sc_time_stamp() << "] FALSE POSITIVE: "
                          << "Trigger en muestra " << m_sample_count << std::endl;
            } else if (!trigger_detected && expected) {
                m_false_negatives++;
                std::cout << "[" << sc_time_stamp() << "] FALSE NEGATIVE: "
                          << "Esperado trigger en muestra " << m_sample_count << std::endl;
            }
        }
        
        m_sample_count++;
        trans.set_response_status(tlm::TLM_OK_RESPONSE);
    }
};

/**
 * @brief Generador de estímulos desde vectores cargados
 */
class StimulusDriver : public sc_module {
public:
    tlm_utils::simple_initiator_socket<StimulusDriver> socket;
    
    SC_HAS_PROCESS(StimulusDriver);
    
    StimulusDriver(sc_module_name name)
        : sc_module(name)
        , socket("socket")
        , m_done(false)
    {
        SC_THREAD(driver_thread);
    }
    
    void set_samples(const std::vector<int16_t>& samples) {
        m_samples = samples;
    }
    
    void start() { m_start_event.notify(); }
    void wait_done() { wait(m_done_event); }
    bool is_done() const { return m_done; }
    
private:
    std::vector<int16_t> m_samples;
    sc_event m_start_event;
    sc_event m_done_event;
    bool m_done;
    
    void driver_thread() {
        wait(m_start_event);
        
        SC_REPORT_INFO("DRIVER", 
            ("Starting to send " + std::to_string(m_samples.size()) + 
             " samples").c_str());
        
        for (size_t i = 0; i < m_samples.size(); i++) {
            // Crear transacción
            bool is_last = (i == m_samples.size() - 1);
            tlm::tlm_generic_payload* trans = 
                create_axis_transaction(m_samples[i], is_last, i);
            
            // Enviar con timing LT
            sc_time delay = SC_ZERO_TIME;
            socket->b_transport(*trans, delay);
            
            // Avanzar tiempo simulado
            wait(delay);
            
            // Liberar
            free_axis_transaction(trans);
        }
        
        SC_REPORT_INFO("DRIVER", "All samples sent");
        m_done = true;
        m_done_event.notify();
    }
};

/**
 * @brief Top-level del testbench
 */
class TriggerTestbench : public sc_module {
public:
    // Componentes
    StimulusDriver*     driver;
    trigger_tlm*        dut;
    TriggerScoreboard*  scoreboard;
    
    TriggerTestbench(sc_module_name name)
        : sc_module(name)
    {
        // Instanciar componentes
        driver     = new StimulusDriver("driver");
        dut        = new trigger_tlm("trigger_dut");
        scoreboard = new TriggerScoreboard("scoreboard");
        
        // Conectar sockets
        driver->socket.bind(dut->input_socket);
        dut->output_socket.bind(scoreboard->socket);
    }
    
    ~TriggerTestbench() {
        delete driver;
        delete dut;
        delete scoreboard;
    }
    
    void configure(const trigger_config_t& cfg) {
        dut->configure(cfg);
    }
    
    void load_vectors(const std::vector<int16_t>& stimulus,
                     const std::vector<bool>& expected) {
        driver->set_samples(stimulus);
        scoreboard->set_expected(expected);
    }
    
    void run() {
        driver->start();
        driver->wait_done();
    }
    
    void print_results(std::ostream& os) {
        scoreboard->print_summary(os);
    }
    
    bool passed() const {
        return scoreboard->passed();
    }
};

/**
 * @brief Información de uso
 */
void print_usage(const char* prog) {
    std::cout << "Uso: " << prog << " [opciones]\n"
              << "Opciones:\n"
              << "  --vectors=DIR    Directorio de vectores (default: ../sim/vectors)\n"
              << "  --test=NAME      Nombre del test (default: trigger_rising_ramp)\n"
              << "  --log=FILE       Archivo de log (default: stdout)\n"
              << "  --all            Ejecutar todos los tests de trigger\n"
              << "  --help           Mostrar esta ayuda\n";
}

/**
 * @brief Ejecuta un test individual
 */
bool run_single_test(const std::string& vectors_dir, 
                     const std::string& test_name,
                     std::ostream& log) {
    log << "\n========== Test: " << test_name << " ==========\n";
    
    // Construir paths
    std::string stim_file = vectors_dir + "/" + test_name + "_stimulus.hex";
    std::string exp_file  = vectors_dir + "/" + test_name + "_expected.hex";
    std::string cfg_file  = vectors_dir + "/" + test_name + "_config.txt";
    
    // Cargar vectores
    auto stimulus = VectorLoader::load_stimulus(stim_file);
    auto expected = VectorLoader::load_expected(exp_file);
    auto config   = VectorLoader::load_config(cfg_file);
    
    if (stimulus.empty()) {
        log << "[ERROR] No se pudo cargar estímulo\n";
        return false;
    }
    
    // El expected puede tener diferente tamaño por el pipeline delay
    // Ajustar si es necesario
    if (expected.size() < stimulus.size()) {
        expected.resize(stimulus.size(), false);
    }
    
    // Crear testbench
    std::string tb_name = "tb_" + test_name;
    TriggerTestbench tb(tb_name.c_str());
    
    // Configurar y cargar
    tb.configure(config);
    tb.load_vectors(stimulus, expected);
    
    // Ejecutar
    log << "[TEST] Ejecutando " << stimulus.size() << " muestras...\n";
    tb.run();
    
    // Resultados
    tb.print_results(log);
    
    return tb.passed();
}

/**
 * @brief Punto de entrada principal
 */
int sc_main(int argc, char* argv[]) {
    // Opciones por defecto
    std::string vectors_dir = "../sim/vectors";
    std::string test_name = "trigger_rising_ramp";
    std::string log_file = "";
    bool run_all = false;
    
    // Parsear argumentos
    static struct option long_options[] = {
        {"vectors", required_argument, 0, 'v'},
        {"test",    required_argument, 0, 't'},
        {"log",     required_argument, 0, 'l'},
        {"all",     no_argument,       0, 'a'},
        {"help",    no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "v:t:l:ah", long_options, nullptr)) != -1) {
        switch (opt) {
            case 'v': vectors_dir = optarg; break;
            case 't': test_name = optarg; break;
            case 'l': log_file = optarg; break;
            case 'a': run_all = true; break;
            case 'h': print_usage(argv[0]); return 0;
            default:  print_usage(argv[0]); return 1;
        }
    }
    
    // Configurar salida de log
    std::ofstream log_stream;
    std::ostream* log = &std::cout;
    
    if (!log_file.empty()) {
        log_stream.open(log_file);
        if (log_stream.is_open()) {
            log = &log_stream;
        } else {
            std::cerr << "Warning: Cannot open log file, using stdout\n";
        }
    }
    
    // Header
    *log << "\n";
    *log << "+-----------------------------------------------------------+\n";
    *log << "|     TESTBENCH TLM: trigger (SystemC TLM 2.0 LT)          |\n";
    *log << "+-----------------------------------------------------------+\n";
    *log << "Vectors directory: " << vectors_dir << "\n";
    
    // Lista de tests
    std::vector<std::string> tests;
    if (run_all) {
        tests = {
            "trigger_rising_ramp",
            "trigger_falling_ramp", 
            "trigger_both_sine",
            "trigger_rising_pulse",
            "trigger_level_random"
        };
    } else {
        tests = {test_name};
    }
    
    // Ejecutar tests
    int passed = 0;
    int failed = 0;
    
    for (const auto& t : tests) {
        // Crear nuevo contexto de simulación para cada test
        // (SystemC no soporta múltiples sc_start fácilmente,
        //  así que ejecutamos un test por invocación en modo --all
        //  o usamos un workaround)
        
        if (run_single_test(vectors_dir, t, *log)) {
            passed++;
        } else {
            failed++;
        }
        
        // Avanzar un poco de tiempo entre tests
        sc_start(100, SC_NS);
    }
    
    // Resumen final
    *log << "\n";
    *log << "+-----------------------------------------------------------+\n";
    *log << "|                    RESUMEN FINAL                          |\n";
    *log << "+-----------------------------------------------------------+\n";
    *log << "|  Tests ejecutados: " << std::setw(37) << (passed + failed) << " |\n";
    *log << "|  Tests PASSED:     " << std::setw(37) << passed << " |\n";
    *log << "|  Tests FAILED:     " << std::setw(37) << failed << " |\n";
    *log << "+-----------------------------------------------------------+\n";
    
    if (failed == 0) {
        *log << "|  >>> REGRESSION PASSED                                   |\n";
    } else {
        *log << "|  >>> REGRESSION FAILED                                   |\n";
    }
    *log << "+-----------------------------------------------------------+\n";
    
    return (failed == 0) ? 0 : 1;
}
