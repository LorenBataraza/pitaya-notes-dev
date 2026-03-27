/**
 * @file axis_sequences.sv
 * @brief Sequences básicas para el agent AXI-Stream
 *
 * Define sequences reutilizables para generar tráfico AXI-Stream.
 * Estas sequences pueden usarse directamente o como base para
 * sequences más específicas.
 */

/**
 * @brief Sequence base para AXI-Stream
 */
class axis_base_sequence extends uvm_sequence #(axis_seq_item);

    `uvm_object_utils(axis_base_sequence)
    
    function new(string name = "axis_base_sequence");
        super.new(name);
    endfunction
    
endclass : axis_base_sequence

/**
 * @brief Sequence que envía un paquete de N samples
 */
class axis_packet_sequence extends axis_base_sequence;

    `uvm_object_utils(axis_packet_sequence)
    
    /// Número de beats en el paquete
    rand int unsigned packet_size;
    
    /// Datos a enviar (si no se especifica, se genera aleatorio)
    int unsigned data_queue[$];
    
    /// ID del paquete
    int unsigned packet_id = 0;
    
    constraint c_packet_size {
        packet_size inside {[1:1024]};
    }
    
    function new(string name = "axis_packet_sequence");
        super.new(name);
    endfunction
    
    /**
     * @brief Configura los datos a enviar
     */
    function void set_data(int unsigned data[$]);
        this.data_queue = data;
        this.packet_size = data.size();
    endfunction
    
    virtual task body();
        axis_seq_item item;
        
        `uvm_info("AXIS_SEQ", $sformatf("Enviando paquete de %0d beats", packet_size), UVM_MEDIUM)
        
        for (int i = 0; i < packet_size; i++) begin
            item = axis_seq_item::type_id::create($sformatf("item_%0d", i));
            
            start_item(item);
            
            if (!item.randomize()) begin
                `uvm_error("AXIS_SEQ", "Randomization failed")
            end
            
            // Usar datos específicos si están disponibles
            if (data_queue.size() > i) begin
                item.data = data_queue[i];
            end
            
            // Marcar último beat
            item.tlast      = (i == packet_size - 1);
            item.packet_id  = packet_id;
            item.beat_index = i;
            
            finish_item(item);
        end
        
        `uvm_info("AXIS_SEQ", "Paquete enviado", UVM_MEDIUM)
    endtask
    
endclass : axis_packet_sequence

/**
 * @brief Sequence que carga datos desde archivo .hex
 */
class axis_file_sequence extends axis_base_sequence;

    `uvm_object_utils(axis_file_sequence)
    
    /// Archivo de estímulos
    string stimulus_file;
    
    /// Datos cargados
    int unsigned samples[$];
    
    function new(string name = "axis_file_sequence");
        super.new(name);
    endfunction
    
    /**
     * @brief Carga datos desde archivo .hex
     */
    function bit load_file(string filename);
        int fd;
        string line;
        int value;
        
        this.stimulus_file = filename;
        samples.delete();
        
        fd = $fopen(filename, "r");
        if (fd == 0) begin
            `uvm_error("AXIS_SEQ", $sformatf("Cannot open file: %s", filename))
            return 0;
        end
        
        while (!$feof(fd)) begin
            if ($fgets(line, fd)) begin
                // Ignorar comentarios y líneas vacías
                if (line.len() < 1 || line[0] == "/" || line[0] == "#") continue;
                
                if ($sscanf(line, "%x", value) == 1) begin
                    samples.push_back(value);
                end
            end
        end
        
        $fclose(fd);
        
        `uvm_info("AXIS_SEQ", $sformatf("Cargados %0d samples desde %s", 
                  samples.size(), filename), UVM_MEDIUM)
        
        return 1;
    endfunction
    
    virtual task body();
        axis_seq_item item;
        
        if (samples.size() == 0) begin
            `uvm_error("AXIS_SEQ", "No hay datos para enviar. Use load_file() primero.")
            return;
        end
        
        `uvm_info("AXIS_SEQ", $sformatf("Enviando %0d samples desde archivo", 
                  samples.size()), UVM_MEDIUM)
        
        for (int i = 0; i < samples.size(); i++) begin
            item = axis_seq_item::type_id::create($sformatf("item_%0d", i));
            
            start_item(item);
            
            item.data       = samples[i];
            item.tlast      = (i == samples.size() - 1);
            item.delay      = 0;
            item.beat_index = i;
            
            finish_item(item);
        end
        
        `uvm_info("AXIS_SEQ", "Todos los samples enviados", UVM_MEDIUM)
    endtask
    
endclass : axis_file_sequence

/**
 * @brief Sequence que genera rampa
 */
class axis_ramp_sequence extends axis_base_sequence;

    `uvm_object_utils(axis_ramp_sequence)
    
    int unsigned start_value = 0;
    int unsigned end_value   = 1023;
    int unsigned num_samples = 100;
    
    function new(string name = "axis_ramp_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        axis_seq_item item;
        real step;
        
        step = real'(end_value - start_value) / (num_samples - 1);
        
        `uvm_info("AXIS_SEQ", $sformatf("Generando rampa: %0d -> %0d, %0d samples",
                  start_value, end_value, num_samples), UVM_MEDIUM)
        
        for (int i = 0; i < num_samples; i++) begin
            item = axis_seq_item::type_id::create($sformatf("ramp_%0d", i));
            
            start_item(item);
            
            item.data       = int'(start_value + i * step);
            item.tlast      = (i == num_samples - 1);
            item.delay      = 0;
            item.beat_index = i;
            
            finish_item(item);
        end
    endtask
    
endclass : axis_ramp_sequence

/**
 * @brief Sequence que genera senoidal
 */
class axis_sine_sequence extends axis_base_sequence;

    `uvm_object_utils(axis_sine_sequence)
    
    int unsigned amplitude   = 400;
    int unsigned offset      = 512;
    int unsigned num_samples = 1000;
    int unsigned periods     = 4;
    
    function new(string name = "axis_sine_sequence");
        super.new(name);
    endfunction
    
    virtual task body();
        axis_seq_item item;
        real angle;
        real value;
        
        `uvm_info("AXIS_SEQ", $sformatf("Generando seno: amp=%0d, off=%0d, %0d samples, %0d periods",
                  amplitude, offset, num_samples, periods), UVM_MEDIUM)
        
        for (int i = 0; i < num_samples; i++) begin
            item = axis_seq_item::type_id::create($sformatf("sine_%0d", i));
            
            start_item(item);
            
            angle = 2.0 * 3.14159265 * periods * i / num_samples;
            value = offset + amplitude * $sin(angle);
            
            item.data       = int'(value);
            item.tlast      = (i == num_samples - 1);
            item.delay      = 0;
            item.beat_index = i;
            
            finish_item(item);
        end
    endtask
    
endclass : axis_sine_sequence
