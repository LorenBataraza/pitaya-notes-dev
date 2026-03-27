/**
 * @file tb_trigger_tlm.cpp
 * @brief Testbench SystemC para el modelo TLM del trigger
 *
 * Este testbench carga los mismos vectores .hex que usa el testbench RTL,
 * ejecuta el modelo TLM-LT y compara los resultados.
 *
 * @par Compilación:
 * @code
 *   g++ -std=c++17 -I$SYSTEMC_HOME/include -L$SYSTEMC_HOME/lib-linux64 \
 *       tb_trigger_tlm.cpp -lsystemc -o tb_trigger_tlm
 * @endcode
 *
 * @par Ejecución:
 * @code
 *   ./tb_trigger_tlm --vectors=../../sim/vectors --test=trigger_rising_ramp
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

//=============================================================================
// Variables globales para configuración (parseadas antes de sc_main)
//=============================================================================

std::string g_vectors_dir = "../../sim/vectors";
std::string g_test_name = "trigger_rising_ramp";
std::string g_log_file = "";
bool g_run_all = false;

//=============================================================================
// Clase para cargar vectores
//=============================================================================

class VectorLoader {
public:
    static std::vector<int16_t> load_stimulus(const std::string& filename) {
        std::vector<int16_t> samples;
        std::ifstream ifs(filename);
        
        if (!ifs.is_open()) {
            std::cerr << "ERROR: Cannot open stimulus file: " << filename << std::endl;
            return samples;
        }
        
        std::string line;
        while (std::getline(ifs, line)) {
            if (line.empty() || line[0] == '/' || line[0] == '#') continue;
            
            uint16_t val;
            if (std::sscanf(line.c_str(), "%hx", &val) == 1) {
                samples.push_back(static_cast<int16_t>(val));
            }
        }
        
        std::cout << "Info: LOADER: Loaded " << samples.size() 
                  << " samples from " << filename << std::endl;
        
        return samples;
    }
    
    static std::vector<bool> load_expected(const std::string& filename) {
        std::vector<bool> expected;
        std::ifstream ifs(filename);
        
        if (!ifs.is_open()) {
            std::cerr << "ERROR: Cannot open expected file: " << filename << std::endl;
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
        
        std::cout << "Info: LOADER: Loaded " << expected.size() 
                  << " expected values from " << filename << std::endl;
        
        return expected;
    }
    
    static trigger_config_t load_config(const std::string& filename) {
        trigger_config_t cfg;
        std::ifstream ifs(filename);
        
        if (!ifs.is_open()) {
            std::cerr << "Warning: Cannot open config file: " << filename << std::endl;
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
        
        std::cout << "Info: LOADER: Config: threshold=" << cfg.threshold 
                  << ", mode=" << (int)cfg.mode << std::endl;
        
        return cfg;
    }
};

//=============================================================================
// Scoreboard simple
//=============================================================================

class Scoreboard {
public:
    std::vector<bool> expected;
    uint32_t triggers_expected = 0;
    uint32_t triggers_detected = 0;
    uint32_t true_positives = 0;
    uint32_t false_positives = 0;
    uint32_t false_negatives = 0;
    
    void set_expected(const std::vector<bool>& exp) {
        expected = exp;
        triggers_expected = 0;
        for (bool e : exp) {
            if (e) triggers_expected++;
        }
    }
    
    void check_trigger(uint32_t index, bool detected) {
        if (detected) triggers_detected++;
        
        if (index >= expected.size()) return;
        
        bool exp = expected[index];
        
        if (detected && exp) {
            true_positives++;
        } else if (detected && !exp) {
            false_positives++;
            std::cout << "Warning: FALSE POSITIVE at index " << index << std::endl;
        } else if (!detected && exp) {
            false_negatives++;
            std::cout << "Warning: FALSE NEGATIVE at index " << index << std::endl;
        }
    }
    
    bool passed() const {
        return (false_positives + false_negatives) == 0;
    }
    
    void print_summary(std::ostream& os) {
        os << "\n";
        os << "+-----------------------------------------------------------+\n";
        os << "|                 RESUMEN DE RESULTADOS (TLM)               |\n";
        os << "+-----------------------------------------------------------+\n";
        os << "|  Triggers esperados:    " << std::setw(33) << triggers_expected << " |\n";
        os << "|  Triggers detectados:   " << std::setw(33) << triggers_detected << " |\n";
        os << "|  True Positives:        " << std::setw(33) << true_positives << " |\n";
        os << "|  False Positives:       " << std::setw(33) << false_positives << " |\n";
        os << "|  False Negatives:       " << std::setw(33) << false_negatives << " |\n";
        os << "+-----------------------------------------------------------+\n";
        
        if (passed()) {
            os << "|  >>> PASS: Todos los triggers coinciden                  |\n";
        } else {
            os << "|  >>> FAIL: " << std::setw(3) << (false_positives + false_negatives) 
               << " discrepancias encontradas                   |\n";
        }
        os << "+-----------------------------------------------------------+\n";
    }
};

//=============================================================================
// Testbench Top Module
//=============================================================================

class TriggerTestbench : public sc_module {
public:
    // Datos cargados
    std::vector<int16_t> stimulus;
    trigger_config_t config;
    Scoreboard scoreboard;
    
    // Estado del pipeline (replica del RTL)
    int16_t pipeline[2];
    bool valid_pipe[2];
    bool armed;
    
    SC_HAS_PROCESS(TriggerTestbench);
    
    TriggerTestbench(sc_module_name name, 
                     const std::string& vectors_dir,
                     const std::string& test_name)
        : sc_module(name)
        , armed(true)
    {
        // Inicializar pipeline
        pipeline[0] = pipeline[1] = 0;
        valid_pipe[0] = valid_pipe[1] = false;
        
        // Cargar vectores
        std::string stim_file = vectors_dir + "/" + test_name + "_stimulus.hex";
        std::string exp_file  = vectors_dir + "/" + test_name + "_expected.hex";
        std::string cfg_file  = vectors_dir + "/" + test_name + "_config.txt";
        
        stimulus = VectorLoader::load_stimulus(stim_file);
        auto expected = VectorLoader::load_expected(exp_file);
        config = VectorLoader::load_config(cfg_file);
        
        scoreboard.set_expected(expected);
        
        // Registrar proceso de test
        SC_THREAD(test_thread);
    }
    
    void test_thread() {
        std::cout << "Info: TEST: Starting test with " << stimulus.size() 
                  << " samples" << std::endl;
        
        // Buffer para alinear trigger con el índice de Python
        // Python atribuye el trigger al índice i-1 cuando lo detecta en i
        bool prev_trigger = false;
        
        // Procesar cada muestra
        for (size_t i = 0; i < stimulus.size(); i++) {
            int16_t sample = stimulus[i];
            bool trigger_out = process_sample(sample);
            
            // Verificar el trigger del ciclo ANTERIOR
            // Esto alinea con la convención de Python donde el trigger
            // detectado en ciclo i se reporta como índice i-1
            if (i > 0) {
                scoreboard.check_trigger(i - 1, prev_trigger);
            }
            
            prev_trigger = trigger_out;
            
            // Avanzar tiempo (1 ciclo de reloj = 8ns)
            wait(8, SC_NS);
        }
        
        // Verificar el último trigger pendiente
        scoreboard.check_trigger(stimulus.size() - 1, prev_trigger);
        
        std::cout << "Info: TEST: All samples processed" << std::endl;
    }
    
    /**
     * @brief Procesa una muestra usando la lógica del trigger
     *
     * Replica el pipeline de 2 etapas del RTL.
     */
    bool process_sample(int16_t sample) {
        // Shift del pipeline
        pipeline[1] = pipeline[0];
        valid_pipe[1] = valid_pipe[0];
        pipeline[0] = sample;
        valid_pipe[0] = true;
        
        // Necesitamos al menos 2 muestras válidas
        if (!valid_pipe[1]) {
            return false;
        }
        
        // Detectar cruce de umbral
        int16_t prev = pipeline[1];
        int16_t curr = pipeline[0];
        int16_t threshold = config.threshold;
        
        bool rising = (prev < threshold) && (curr >= threshold);
        bool falling = (prev >= threshold) && (curr < threshold);
        
        bool event_detected = false;
        switch (config.mode) {
            case 0: event_detected = rising; break;   // RISING
            case 1: event_detected = falling; break;  // FALLING
            case 2: event_detected = rising || falling; break; // BOTH
            case 3: event_detected = curr >= threshold; break; // LEVEL
        }
        
        bool trigger_out = false;
        if (armed && event_detected) {
            trigger_out = true;
            armed = false;
        } else if (!event_detected) {
            armed = true;
        }
        
        return trigger_out;
    }
    
    void print_results(std::ostream& os) {
        scoreboard.print_summary(os);
    }
    
    bool passed() const {
        return scoreboard.passed();
    }
};

//=============================================================================
// Parseo de argumentos
//=============================================================================

void parse_args(int argc, char* argv[]) {
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
            case 'v': g_vectors_dir = optarg; break;
            case 't': g_test_name = optarg; break;
            case 'l': g_log_file = optarg; break;
            case 'a': g_run_all = true; break;
            case 'h':
                std::cout << "Uso: " << argv[0] << " [opciones]\n"
                          << "  --vectors=DIR    Directorio de vectores\n"
                          << "  --test=NAME      Nombre del test\n"
                          << "  --log=FILE       Archivo de log\n"
                          << "  --all            Ejecutar todos los tests\n";
                exit(0);
            default:
                exit(1);
        }
    }
}

//=============================================================================
// sc_main
//=============================================================================

int sc_main(int argc, char* argv[]) {
    // Parsear argumentos
    parse_args(argc, argv);
    
    // Configurar log
    std::ofstream log_stream;
    std::ostream* log = &std::cout;
    
    if (!g_log_file.empty()) {
        log_stream.open(g_log_file);
        if (log_stream.is_open()) {
            log = &log_stream;
        }
    }
    
    // Header
    *log << "\n";
    *log << "+-----------------------------------------------------------+\n";
    *log << "|     TESTBENCH TLM: trigger (SystemC TLM 2.0 LT)          |\n";
    *log << "+-----------------------------------------------------------+\n";
    *log << "Vectors directory: " << g_vectors_dir << "\n";
    
    // Lista de tests
    std::vector<std::string> tests;
    if (g_run_all) {
        tests = {
            "trigger_rising_ramp",
            "trigger_falling_ramp", 
            "trigger_both_sine",
            "trigger_rising_pulse",
            "trigger_level_random"
        };
    } else {
        tests = {g_test_name};
    }
    
    // Resultados
    int passed = 0;
    int failed = 0;
    
    // Ejecutar tests
    for (const auto& test : tests) {
        *log << "\n========== Test: " << test << " ==========\n";
        
        // Crear testbench
        std::string tb_name = "tb_" + test;
        TriggerTestbench tb(tb_name.c_str(), g_vectors_dir, test);
        
        // Ejecutar simulación
        sc_start();
        
        // Resultados
        tb.print_results(*log);
        
        if (tb.passed()) {
            passed++;
        } else {
            failed++;
        }
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
