/**
 * @file tb_ram_writer_tlm.cpp
 * @brief Testbench SystemC para el modelo TLM del RAM Writer
 */

#include <systemc>
#include <fstream>
#include <vector>
#include <string>
#include <iomanip>
#include <getopt.h>

#include "ram_writer/ram_writer_tlm.h"

using namespace sc_core;
using namespace mcpha;

//=============================================================================
// Variables globales
//=============================================================================

std::string g_vectors_dir = "../../sim/vectors";
std::string g_test_name = "rw_basic_256";
std::string g_log_file = "";

//=============================================================================
// Cargador de vectores
//=============================================================================

class RwVectorLoader {
public:
    /**
     * @brief Carga estímulo con formato "DATA TLAST"
     */
    static bool load_stimulus(const std::string& filename,
                              std::vector<uint32_t>& data,
                              std::vector<bool>& tlast) {
        std::ifstream ifs(filename);
        
        if (!ifs.is_open()) {
            std::cerr << "ERROR: Cannot open: " << filename << std::endl;
            return false;
        }
        
        data.clear();
        tlast.clear();
        
        std::string line;
        while (std::getline(ifs, line)) {
            if (line.empty() || line[0] == '/' || line[0] == '#') continue;
            
            uint32_t val;
            int last;
            if (std::sscanf(line.c_str(), "%x %d", &val, &last) == 2) {
                data.push_back(val);
                tlast.push_back(last != 0);
            }
        }
        
        std::cout << "Info: LOADER: Loaded " << data.size() 
                  << " samples from " << filename << std::endl;
        return true;
    }
    
    static std::vector<uint32_t> load_expected(const std::string& filename) {
        std::vector<uint32_t> expected;
        std::ifstream ifs(filename);
        
        if (!ifs.is_open()) {
            std::cerr << "Warning: Cannot open: " << filename << std::endl;
            return expected;
        }
        
        std::string line;
        while (std::getline(ifs, line)) {
            if (line.empty() || line[0] == '/' || line[0] == '#') continue;
            uint32_t val;
            if (std::sscanf(line.c_str(), "%x", &val) == 1) {
                expected.push_back(val);
            }
        }
        
        std::cout << "Info: LOADER: Loaded " << expected.size() 
                  << " expected values" << std::endl;
        return expected;
    }
    
    static ram_writer_config_t load_config(const std::string& filename) {
        ram_writer_config_t cfg;
        std::ifstream ifs(filename);
        
        if (!ifs.is_open()) return cfg;
        
        std::string line;
        while (std::getline(ifs, line)) {
            if (line.empty() || line[0] == '/' || line[0] == '#') continue;
            char param[64];
            char value[64];
            if (std::sscanf(line.c_str(), "%s %s", param, value) == 2) {
                std::string p(param);
                if (p == "BASE_ADDR") {
                    cfg.base_addr = std::strtoull(value, nullptr, 0);
                } else if (p == "BUFFER_SIZE") {
                    cfg.buffer_size = std::strtoull(value, nullptr, 0);
                }
            }
        }
        
        std::cout << "Info: LOADER: Config: base=0x" << std::hex << cfg.base_addr
                  << ", size=0x" << cfg.buffer_size << std::dec << std::endl;
        return cfg;
    }
};

//=============================================================================
// Testbench
//=============================================================================

class RamWriterTestbench : public sc_module {
public:
    ram_writer_tlm rw;
    
    std::vector<uint32_t> stimulus;
    std::vector<bool> tlast;
    std::vector<uint32_t> expected;
    ram_writer_config_t config;
    
    int mismatches;
    
    SC_HAS_PROCESS(RamWriterTestbench);
    
    RamWriterTestbench(sc_module_name name,
                       const std::string& vectors_dir,
                       const std::string& test_name)
        : sc_module(name)
        , rw("ram_writer")
        , mismatches(0)
    {
        std::string stim_file = vectors_dir + "/" + test_name + "_stimulus.hex";
        std::string exp_file  = vectors_dir + "/" + test_name + "_expected.hex";
        std::string cfg_file  = vectors_dir + "/" + test_name + "_config.txt";
        
        RwVectorLoader::load_stimulus(stim_file, stimulus, tlast);
        expected = RwVectorLoader::load_expected(exp_file);
        config = RwVectorLoader::load_config(cfg_file);
        
        rw.configure(config);
        
        SC_THREAD(test_thread);
    }
    
    void test_thread() {
        std::cout << "Info: TEST: Starting RAM writer test with " 
                  << stimulus.size() << " samples" << std::endl;
        
        rw.reset();
        rw.enable();
        
        for (size_t i = 0; i < stimulus.size(); i++) {
            // RAM Writer espera 16 bits, truncamos
            int16_t sample = static_cast<int16_t>(stimulus[i] & 0xFFFF);
            bool last = tlast[i];
            
            rw.write_sample(sample, last);
            
            wait(8, SC_NS);
        }
        
        // Forzar flush final
        rw.flush();
        
        // Verificar
        verify_results();
        
        std::cout << "Info: TEST: Complete" << std::endl;
    }
    
    void verify_results() {
        auto& memory = rw.get_memory();
        
        // Desempaquetar memoria (64 bits -> 4 x 16 bits)
        std::vector<uint32_t> unpacked;
        for (uint64_t word : memory) {
            for (int i = 0; i < 4; i++) {
                uint16_t sample = (word >> (i * 16)) & 0xFFFF;
                unpacked.push_back(sample);
            }
        }
        
        // Comparar (solo los datos válidos, no el padding)
        size_t compare_len = std::min(unpacked.size(), expected.size());
        compare_len = std::min(compare_len, stimulus.size());
        
        for (size_t i = 0; i < compare_len; i++) {
            uint32_t got = unpacked[i] & 0xFFFF;
            uint32_t exp = expected[i] & 0xFFFF;
            
            if (got != exp) {
                mismatches++;
                if (mismatches <= 5) {
                    std::cout << "Warning: Mismatch at " << i 
                              << ": got 0x" << std::hex << got 
                              << ", expected 0x" << exp << std::dec << std::endl;
                }
            }
        }
        
        // Verificar 4KB boundary
        for (auto& txn : rw.get_transactions()) {
            if (txn.crosses_4kb()) {
                std::cout << "Warning: Transaction at 0x" << std::hex 
                          << txn.address << " crosses 4KB boundary" 
                          << std::dec << std::endl;
                mismatches++;
            }
        }
    }
    
    void print_results(std::ostream& os) {
        os << "\n";
        os << "+-----------------------------------------------------------+\n";
        os << "|           RESUMEN DE RESULTADOS (RAM_WRITER TLM)          |\n";
        os << "+-----------------------------------------------------------+\n";
        os << "|  Muestras entrada:      " << std::setw(33) << stimulus.size() << " |\n";
        os << "|  Bursts generados:      " << std::setw(33) << rw.get_burst_count() << " |\n";
        os << "|  Bytes escritos:        " << std::setw(33) << rw.get_total_bytes() << " |\n";
        os << "|  Transacciones AXI4:    " << std::setw(33) << rw.get_transactions().size() << " |\n";
        os << "|  Mismatches:            " << std::setw(33) << mismatches << " |\n";
        os << "+-----------------------------------------------------------+\n";
        
        if (mismatches == 0) {
            os << "|  >>> PASS                                                |\n";
        } else {
            os << "|  >>> FAIL                                                |\n";
        }
        os << "+-----------------------------------------------------------+\n";
    }
    
    bool passed() const {
        return mismatches == 0;
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
                std::cout << "Uso: tb_ram_writer_tlm [--vectors=DIR] [--test=NAME] [--log=FILE]\n";
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
    *log << "|       TESTBENCH TLM: ram_writer (SystemC TLM 2.0 LT)     |\n";
    *log << "+-----------------------------------------------------------+\n";
    *log << "Test: " << g_test_name << "\n";
    
    RamWriterTestbench tb("tb_rw", g_vectors_dir, g_test_name);
    
    sc_start();
    
    tb.print_results(*log);
    
    return tb.passed() ? 0 : 1;
}
