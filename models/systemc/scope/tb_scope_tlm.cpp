/**
 * @file tb_scope_tlm.cpp
 * @brief Testbench SystemC para el modelo TLM del Scope
 */

#include <systemc>
#include <fstream>
#include <vector>
#include <string>
#include <iomanip>
#include <getopt.h>

#include "scope/scope_tlm.h"

using namespace sc_core;
using namespace mcpha;

//=============================================================================
// Variables globales
//=============================================================================

std::string g_vectors_dir = "../../sim/vectors";
std::string g_test_name = "scope_single";
std::string g_log_file = "";

//=============================================================================
// Cargador de vectores
//=============================================================================

class ScopeVectorLoader {
public:
    static std::vector<int16_t> load_stimulus(const std::string& filename) {
        std::vector<int16_t> samples;
        std::ifstream ifs(filename);
        
        if (!ifs.is_open()) {
            std::cerr << "ERROR: Cannot open: " << filename << std::endl;
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
    
    static std::vector<int16_t> load_expected(const std::string& filename) {
        return load_stimulus(filename);  // Mismo formato
    }
    
    static std::vector<uint32_t> load_triggers(const std::string& filename) {
        std::vector<uint32_t> triggers;
        std::ifstream ifs(filename);
        
        if (!ifs.is_open()) {
            std::cerr << "Warning: Cannot open: " << filename << std::endl;
            return triggers;
        }
        
        std::string line;
        while (std::getline(ifs, line)) {
            if (line.empty() || line[0] == '/' || line[0] == '#') continue;
            uint32_t val;
            if (std::sscanf(line.c_str(), "%u", &val) == 1) {
                triggers.push_back(val);
            }
        }
        
        std::cout << "Info: LOADER: Loaded " << triggers.size() 
                  << " trigger positions" << std::endl;
        return triggers;
    }
    
    static scope_config_t load_config(const std::string& filename) {
        scope_config_t cfg;
        std::ifstream ifs(filename);
        
        if (!ifs.is_open()) return cfg;
        
        std::string line;
        while (std::getline(ifs, line)) {
            if (line.empty() || line[0] == '/' || line[0] == '#') continue;
            char param[64];
            int value;
            if (std::sscanf(line.c_str(), "%s %d", param, &value) == 2) {
                std::string p(param);
                if (p == "PRE_SAMPLES") cfg.pre_samples = value;
                else if (p == "POST_SAMPLES") cfg.post_samples = value;
            }
        }
        
        std::cout << "Info: LOADER: Config: pre=" << cfg.pre_samples 
                  << ", post=" << cfg.post_samples << std::endl;
        return cfg;
    }
};

//=============================================================================
// Testbench
//=============================================================================

class ScopeTestbench : public sc_module {
public:
    scope_tlm scope;
    
    std::vector<int16_t> stimulus;
    std::vector<int16_t> expected;
    std::vector<uint32_t> trigger_positions;
    scope_config_t config;
    
    std::vector<int16_t> output;
    int mismatches;
    
    SC_HAS_PROCESS(ScopeTestbench);
    
    ScopeTestbench(sc_module_name name,
                   const std::string& vectors_dir,
                   const std::string& test_name)
        : sc_module(name)
        , scope("scope")
        , mismatches(0)
    {
        std::string stim_file = vectors_dir + "/" + test_name + "_stimulus.hex";
        std::string exp_file  = vectors_dir + "/" + test_name + "_expected.hex";
        std::string trig_file = vectors_dir + "/" + test_name + "_triggers.txt";
        std::string cfg_file  = vectors_dir + "/" + test_name + "_config.txt";
        
        stimulus = ScopeVectorLoader::load_stimulus(stim_file);
        expected = ScopeVectorLoader::load_expected(exp_file);
        trigger_positions = ScopeVectorLoader::load_triggers(trig_file);
        config = ScopeVectorLoader::load_config(cfg_file);
        
        scope.configure(config);
        
        SC_THREAD(test_thread);
    }
    
    void test_thread() {
        std::cout << "Info: TEST: Starting scope test with " 
                  << stimulus.size() << " samples" << std::endl;
        
        scope.reset();
        scope.enable();
        
        size_t trig_idx = 0;
        
        for (size_t i = 0; i < stimulus.size(); i++) {
            // Determinar si hay trigger en esta posición
            bool trigger = false;
            if (trig_idx < trigger_positions.size() && 
                i == trigger_positions[trig_idx]) {
                trigger = true;
                trig_idx++;
            }
            
            auto [valid, sample] = scope.process_sample(stimulus[i], trigger);
            
            if (valid) {
                output.push_back(sample);
            }
            
            wait(8, SC_NS);
        }
        
        // Drenar salidas pendientes
        for (int i = 0; i < 1000 && scope.get_state() == ScopeState::OUTPUTTING; i++) {
            auto [valid, sample] = scope.process_sample(0, false);
            if (valid) {
                output.push_back(sample);
            }
            wait(8, SC_NS);
        }
        
        // Comparar
        compare_outputs();
        
        std::cout << "Info: TEST: Complete" << std::endl;
    }
    
    void compare_outputs() {
        size_t min_len = std::min(output.size(), expected.size());
        
        for (size_t i = 0; i < min_len; i++) {
            if (output[i] != expected[i]) {
                mismatches++;
                if (mismatches <= 5) {
                    std::cout << "Warning: Mismatch at " << i 
                              << ": got " << output[i] 
                              << ", expected " << expected[i] << std::endl;
                }
            }
        }
        
        if (output.size() != expected.size()) {
            std::cout << "Warning: Size mismatch: got " << output.size()
                      << ", expected " << expected.size() << std::endl;
            mismatches += std::abs((int)output.size() - (int)expected.size());
        }
    }
    
    void print_results(std::ostream& os) {
        os << "\n";
        os << "+-----------------------------------------------------------+\n";
        os << "|              RESUMEN DE RESULTADOS (SCOPE TLM)            |\n";
        os << "+-----------------------------------------------------------+\n";
        os << "|  Muestras entrada:      " << std::setw(33) << stimulus.size() << " |\n";
        os << "|  Muestras salida:       " << std::setw(33) << output.size() << " |\n";
        os << "|  Muestras esperadas:    " << std::setw(33) << expected.size() << " |\n";
        os << "|  Ventanas capturadas:   " << std::setw(33) << scope.get_windows().size() << " |\n";
        os << "|  Mismatches:            " << std::setw(33) << mismatches << " |\n";
        os << "+-----------------------------------------------------------+\n";
        
        if (mismatches == 0 && output.size() == expected.size()) {
            os << "|  >>> PASS                                                |\n";
        } else {
            os << "|  >>> FAIL                                                |\n";
        }
        os << "+-----------------------------------------------------------+\n";
    }
    
    bool passed() const {
        return mismatches == 0 && output.size() == expected.size();
    }
};

//=============================================================================
// Main
//=============================================================================

void parse_args(int argc, char* argv[]) {
    static struct option long_options[] = {
        {"vectors", required_argument, 0, 'v'},
        {"test",    required_argument, 0, 't'},
        {"log",     required_argument, 0, 'l'},
        {"help",    no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };
    
    int opt;
    while ((opt = getopt_long(argc, argv, "v:t:l:h", long_options, nullptr)) != -1) {
        switch (opt) {
            case 'v': g_vectors_dir = optarg; break;
            case 't': g_test_name = optarg; break;
            case 'l': g_log_file = optarg; break;
            case 'h':
                std::cout << "Uso: tb_scope_tlm [--vectors=DIR] [--test=NAME] [--log=FILE]\n";
                exit(0);
        }
    }
}

int sc_main(int argc, char* argv[]) {
    parse_args(argc, argv);
    
    std::ofstream log_stream;
    std::ostream* log = &std::cout;
    
    if (!g_log_file.empty()) {
        log_stream.open(g_log_file);
        if (log_stream.is_open()) log = &log_stream;
    }
    
    *log << "\n";
    *log << "+-----------------------------------------------------------+\n";
    *log << "|         TESTBENCH TLM: scope (SystemC TLM 2.0 LT)        |\n";
    *log << "+-----------------------------------------------------------+\n";
    *log << "Test: " << g_test_name << "\n";
    
    ScopeTestbench tb("tb_scope", g_vectors_dir, g_test_name);
    
    sc_start();
    
    tb.print_results(*log);
    
    return tb.passed() ? 0 : 1;
}
