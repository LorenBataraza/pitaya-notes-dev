/**
 * @file axis_ram_writer.sv
 * @brief Controlador de escritura a DDR con interfaz AXI4 Master
 * 
 * Este módulo recibe datos a través de una interfaz AXI-Stream y los
 * escribe a memoria DDR utilizando el protocolo AXI4. Implementa un
 * buffer interno FIFO para manejar la diferencia de velocidades entre
 * la fuente de datos (Scope) y el bus de memoria.
 * 
 * @par Diagrama de bloques:
 * @verbatim
 *                        ┌────────────────────────────────────────────────┐
 *     s_axis_tdata ──────┤                                                │
 *    s_axis_tvalid ──────┤      ┌────────┐    ┌─────────┐    ┌──────┐    ├── m_axi_aw*
 *    s_axis_tready ◀─────┤      │ INPUT  │───▶│ BURST   │───▶│ AXI4 │────├── m_axi_w*
 *     s_axis_tlast ──────┤      │  FIFO  │    │ BUILDER │    │  IF  │    ├── m_axi_b*
 *                        │      └────────┘    └─────────┘    └──────┘    │
 *           config ──────┤                                                │
 *           status ◀─────┤                                                │
 *                        └────────────────────────────────────────────────┘
 * @endverbatim
 * 
 * @par Funcionamiento:
 * 1. Los datos entrantes se almacenan en un FIFO interno
 * 2. Cuando el FIFO tiene suficientes datos (o se recibe TLAST), 
 *    se inicia una transacción burst AXI4
 * 3. La máquina de estados coordina las fases de dirección, datos y respuesta
 * 4. El puntero de escritura se actualiza y puede implementar buffer circular
 * 
 * @par Consideraciones importantes:
 * - El tamaño de burst máximo de AXI4 es 256 beats
 * - Las direcciones de burst deben estar alineadas a 4KB
 * - Se debe manejar correctamente AWREADY/WREADY con backpressure
 * 
 * @warning Este módulo requiere que el software configure correctamente
 *          las regiones de memoria en el MMU para acceso coherente.
 */

`default_nettype none

module axis_ram_writer
    import axi_stream_pkg::*;
#(
    /** @brief Ancho del bus de datos AXI4 */
    parameter int unsigned AXI_DATA_W = AXI_DATA_WIDTH,
    
    /** @brief Ancho del bus de direcciones AXI4 */
    parameter int unsigned AXI_ADDR_W = AXI_ADDR_WIDTH,
    
    /** @brief Ancho del ID de transacción AXI4 */
    parameter int unsigned AXI_ID_W = 4,
    
    /** @brief Profundidad del FIFO interno */
    parameter int unsigned FIFO_DEPTH = 1024,
    
    /** @brief Longitud máxima de burst (1-256) */
    parameter int unsigned MAX_BURST_LEN = 16,
    
    /** @brief Ancho del bus de datos de entrada */
    parameter int unsigned DATA_WIDTH = DSP_DATA_WIDTH
)(
    //=========================================================================
    // Señales de reloj y reset
    //=========================================================================
    
    /** @brief Reloj del sistema */
    input  wire                          aclk,
    
    /** @brief Reset asíncrono activo bajo */
    input  wire                          aresetn,
    
    //=========================================================================
    // Interfaz de configuración y estado
    //=========================================================================
    
    /** @brief Configuración del módulo */
    input  ram_writer_config_t           config_i,
    
    /** @brief Estado actual del módulo */
    output ram_writer_status_t           status_o,
    
    //=========================================================================
    // Interfaz AXI-Stream Slave (entrada de datos)
    //=========================================================================
    
    /** @brief Datos de entrada */
    input  wire [DATA_WIDTH-1:0]         s_axis_tdata,
    
    /** @brief Datos válidos */
    input  wire                          s_axis_tvalid,
    
    /** @brief Listo para recibir */
    output logic                         s_axis_tready,
    
    /** @brief Último dato del frame */
    input  wire                          s_axis_tlast,
    
    //=========================================================================
    // Interfaz AXI4 Master (escritura a memoria)
    //=========================================================================
    
    // Canal de dirección de escritura (AW)
    /** @brief ID de la transacción */
    output logic [AXI_ID_W-1:0]          m_axi_awid,
    
    /** @brief Dirección de escritura */
    output logic [AXI_ADDR_W-1:0]        m_axi_awaddr,
    
    /** @brief Longitud del burst (número de transferencias - 1) */
    output logic [7:0]                   m_axi_awlen,
    
    /** @brief Tamaño de cada transferencia (2^size bytes) */
    output logic [2:0]                   m_axi_awsize,
    
    /** @brief Tipo de burst (INCR = 01) */
    output logic [1:0]                   m_axi_awburst,
    
    /** @brief Tipo de cache (Write-through) */
    output logic [3:0]                   m_axi_awcache,
    
    /** @brief Dirección válida */
    output logic                         m_axi_awvalid,
    
    /** @brief Slave listo para dirección */
    input  wire                          m_axi_awready,
    
    // Canal de datos de escritura (W)
    /** @brief Datos de escritura */
    output logic [AXI_DATA_W-1:0]        m_axi_wdata,
    
    /** @brief Strobes de bytes válidos */
    output logic [AXI_DATA_W/8-1:0]      m_axi_wstrb,
    
    /** @brief Último dato del burst */
    output logic                         m_axi_wlast,
    
    /** @brief Datos válidos */
    output logic                         m_axi_wvalid,
    
    /** @brief Slave listo para datos */
    input  wire                          m_axi_wready,
    
    // Canal de respuesta de escritura (B)
    /** @brief ID de la respuesta */
    input  wire [AXI_ID_W-1:0]           m_axi_bid,
    
    /** @brief Respuesta (OKAY = 00) */
    input  wire [1:0]                    m_axi_bresp,
    
    /** @brief Respuesta válida */
    input  wire                          m_axi_bvalid,
    
    /** @brief Master listo para respuesta */
    output logic                         m_axi_bready
);

    //=========================================================================
    // Parámetros locales
    //=========================================================================
    
    /** @brief Número de muestras de entrada que caben en una palabra AXI */
    localparam int unsigned SAMPLES_PER_WORD = AXI_DATA_W / DATA_WIDTH;
    
    /** @brief Bits para direccionar el FIFO */
    localparam int unsigned FIFO_ADDR_W = $clog2(FIFO_DEPTH);
    
    /** @brief Bytes por transferencia AXI */
    localparam int unsigned BYTES_PER_BEAT = AXI_DATA_W / 8;
    
    //=========================================================================
    // Declaración de señales internas
    //=========================================================================
    
    /** @brief Estado actual de la FSM */
    ram_writer_state_e state, state_next;
    
    // Señales del FIFO
    logic [AXI_DATA_W-1:0]  fifo_din;
    logic [AXI_DATA_W-1:0]  fifo_dout;
    logic                   fifo_wr_en;
    logic                   fifo_rd_en;
    logic                   fifo_full;
    logic                   fifo_empty;
    logic [FIFO_ADDR_W:0]   fifo_count;
    
    // Acumulador para empaquetar muestras
    logic [AXI_DATA_W-1:0]  sample_accumulator;
    logic [$clog2(SAMPLES_PER_WORD)-1:0] sample_idx;
    logic                   accumulator_valid;
    logic                   flush_accumulator;
    
    // Control de burst
    logic [AXI_ADDR_W-1:0]  current_addr;
    logic [7:0]             burst_len;
    logic [7:0]             beat_count;
    logic                   burst_in_progress;
    
    // Control de buffer circular
    logic [31:0]            write_offset;
    logic                   buffer_wrapped;
    
    // Registros de estado
    logic [31:0]            total_bytes_written;
    logic                   overflow_flag;
    logic                   last_seen;

    //=========================================================================
    // FIFO de entrada (instanciación)
    //=========================================================================
    
    /**
     * @brief FIFO para buffer de datos de entrada
     * 
     * Este FIFO desacopla el flujo de entrada AXI-Stream del proceso
     * de escritura AXI4, permitiendo absorber variaciones de throughput.
     */
    logic [AXI_DATA_W-1:0] fifo_mem [FIFO_DEPTH];
    logic [FIFO_ADDR_W-1:0] fifo_wr_ptr, fifo_rd_ptr;
    logic [FIFO_ADDR_W:0] fifo_level;
    
    always_ff @(posedge aclk or negedge aresetn) begin : proc_fifo
        if (!aresetn) begin
            fifo_wr_ptr <= '0;
            fifo_rd_ptr <= '0;
            fifo_level  <= '0;
        end
        else begin
            // Escritura al FIFO
            if (fifo_wr_en && !fifo_full) begin
                fifo_mem[fifo_wr_ptr] <= fifo_din;
                fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
            end
            
            // Lectura del FIFO
            if (fifo_rd_en && !fifo_empty) begin
                fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
            end
            
            // Actualización del nivel
            case ({fifo_wr_en && !fifo_full, fifo_rd_en && !fifo_empty})
                2'b10:   fifo_level <= fifo_level + 1'b1;
                2'b01:   fifo_level <= fifo_level - 1'b1;
                default: fifo_level <= fifo_level;
            endcase
        end
    end
    
    assign fifo_dout  = fifo_mem[fifo_rd_ptr];
    assign fifo_full  = (fifo_level == FIFO_DEPTH);
    assign fifo_empty = (fifo_level == 0);
    assign fifo_count = fifo_level;

    //=========================================================================
    // Acumulador de muestras
    //=========================================================================
    
    /**
     * @brief Proceso de empaquetamiento de muestras
     * 
     * Agrupa múltiples muestras de entrada (DATA_WIDTH bits) en una
     * palabra AXI (AXI_DATA_W bits) para maximizar eficiencia del bus.
     */
    always_ff @(posedge aclk or negedge aresetn) begin : proc_accumulator
        if (!aresetn) begin
            sample_accumulator <= '0;
            sample_idx         <= '0;
            accumulator_valid  <= 1'b0;
            last_seen          <= 1'b0;
        end
        else begin
            accumulator_valid <= 1'b0;
            
            if (s_axis_tvalid && s_axis_tready && config_i.enable) begin
                // Insertar muestra en la posición correspondiente
                sample_accumulator[sample_idx*DATA_WIDTH +: DATA_WIDTH] <= s_axis_tdata;
                
                if (s_axis_tlast) begin
                    // Último dato: forzar flush del acumulador
                    last_seen <= 1'b1;
                    accumulator_valid <= 1'b1;
                    sample_idx <= '0;
                end
                else if (sample_idx == SAMPLES_PER_WORD - 1) begin
                    // Acumulador lleno: escribir al FIFO
                    accumulator_valid <= 1'b1;
                    sample_idx <= '0;
                end
                else begin
                    sample_idx <= sample_idx + 1'b1;
                end
            end
            
            // Reset last_seen solo cuando:
            // 1. Se deshabilita el módulo
            // 2. La transferencia terminó exitosamente (FIFO vacío después de ver tlast)
            if (!config_i.enable) begin
                last_seen <= 1'b0;
            end
            else if (state == WR_RESP && m_axi_bvalid && m_axi_bready && 
                     m_axi_bresp == 2'b00 && fifo_empty && last_seen) begin
                last_seen <= 1'b0;
            end
        end
    end
    
    // Conexión acumulador -> FIFO
    assign fifo_din   = sample_accumulator;
    assign fifo_wr_en = accumulator_valid && !fifo_full;

    //=========================================================================
    // Control de TREADY
    //=========================================================================
    
    /**
     * @brief Control de backpressure hacia el upstream
     * 
     * Acepta datos solo si hay espacio en el FIFO y el módulo está habilitado.
     */
    assign s_axis_tready = config_i.enable && !fifo_full;

    //=========================================================================
    // Máquina de estados principal
    //=========================================================================
    
    /**
     * @brief Lógica de próximo estado
     */
    always_comb begin : proc_next_state
        state_next = state;
        
        case (state)
            WR_IDLE: begin
                if (config_i.enable && (fifo_count >= MAX_BURST_LEN || last_seen)) begin
                    state_next = WR_CALC;
                end
            end
            
            WR_CALC: begin
                // Calcular parámetros del burst
                state_next = WR_ADDR;
            end
            
            WR_ADDR: begin
                // Enviar dirección de escritura
                if (m_axi_awvalid && m_axi_awready) begin
                    state_next = WR_DATA;
                end
            end
            
            WR_DATA: begin
                // Transferir datos
                if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                    state_next = WR_RESP;
                end
            end
            
            WR_RESP: begin
                // Esperar respuesta
                if (m_axi_bvalid && m_axi_bready) begin
                    if (m_axi_bresp != 2'b00) begin
                        state_next = WR_ERROR;
                    end
                    else if (fifo_empty && last_seen) begin
                        state_next = WR_IDLE;
                    end
                    else if (fifo_count >= MAX_BURST_LEN || last_seen) begin
                        state_next = WR_CALC;
                    end
                    else begin
                        state_next = WR_IDLE;
                    end
                end
            end
            
            WR_ERROR: begin
                // Mantener en error hasta reset o disable
                if (!config_i.enable) begin
                    state_next = WR_IDLE;
                end
            end
            
            default: state_next = WR_IDLE;
        endcase
    end
    
    /**
     * @brief Registro de estado
     */
    always_ff @(posedge aclk or negedge aresetn) begin : proc_state_reg
        if (!aresetn) begin
            state <= WR_IDLE;
        end
        else begin
            state <= state_next;
        end
    end

    //=========================================================================
    // Control de dirección y burst
    //=========================================================================
    
    /**
     * @brief Cálculo de parámetros de burst
     */
    always_ff @(posedge aclk or negedge aresetn) begin : proc_burst_params
        if (!aresetn) begin
            current_addr <= '0;
            burst_len    <= '0;
            write_offset <= '0;
        end
        else begin
            case (state)
                WR_IDLE: begin
                    if (!config_i.enable) begin
                        write_offset <= '0;
                        current_addr <= config_i.base_addr;
                    end
                end
                
                WR_CALC: begin
                    // Calcular dirección actual
                    current_addr <= config_i.base_addr + write_offset;
                    
                    // Calcular longitud de burst
                    if (fifo_count >= MAX_BURST_LEN) begin
                        burst_len <= MAX_BURST_LEN - 1;
                    end
                    else begin
                        burst_len <= fifo_count[7:0] - 1;
                    end
                end
                
                WR_RESP: begin
                    if (m_axi_bvalid && m_axi_bready && m_axi_bresp == 2'b00) begin
                        // Actualizar offset
                        write_offset <= write_offset + ((burst_len + 1) * BYTES_PER_BEAT);
                        
                        // Manejar wrap-around de buffer circular
                        if (write_offset + ((burst_len + 1) * BYTES_PER_BEAT) >= config_i.buffer_size) begin
                            write_offset <= '0;
                        end
                    end
                end
                
                default: ;
            endcase
        end
    end
    
    /**
     * @brief Contador de beats dentro del burst
     */
    always_ff @(posedge aclk or negedge aresetn) begin : proc_beat_counter
        if (!aresetn) begin
            beat_count <= '0;
        end
        else begin
            if (state == WR_ADDR && m_axi_awready) begin
                beat_count <= '0;
            end
            else if (state == WR_DATA && m_axi_wvalid && m_axi_wready) begin
                beat_count <= beat_count + 1'b1;
            end
        end
    end

    //=========================================================================
    // Generación de señales AXI4
    //=========================================================================
    
    // Canal AW (dirección de escritura)
    assign m_axi_awid    = '0;
    assign m_axi_awaddr  = current_addr;
    assign m_axi_awlen   = burst_len;
    assign m_axi_awsize  = $clog2(BYTES_PER_BEAT);  // Full width transfers
    assign m_axi_awburst = 2'b01;  // INCR
    assign m_axi_awcache = 4'b0011;  // Bufferable, modifiable
    assign m_axi_awvalid = (state == WR_ADDR);
    
    // Canal W (datos de escritura)
    assign m_axi_wdata  = fifo_dout;
    assign m_axi_wstrb  = {(AXI_DATA_W/8){1'b1}};  // Todos los bytes válidos
    assign m_axi_wlast  = (beat_count == burst_len);
    assign m_axi_wvalid = (state == WR_DATA) && !fifo_empty;
    
    // Canal B (respuesta)
    assign m_axi_bready = (state == WR_RESP);
    
    // Control de lectura del FIFO
    assign fifo_rd_en = (state == WR_DATA) && m_axi_wvalid && m_axi_wready;

    //=========================================================================
    // Contadores de estadísticas
    //=========================================================================
    
    always_ff @(posedge aclk or negedge aresetn) begin : proc_stats
        if (!aresetn) begin
            total_bytes_written <= '0;
            overflow_flag       <= 1'b0;
        end
        else begin
            if (!config_i.enable) begin
                total_bytes_written <= '0;
                overflow_flag       <= 1'b0;
            end
            else begin
                // Contar bytes escritos
                if (state == WR_RESP && m_axi_bvalid && m_axi_bready && 
                    m_axi_bresp == 2'b00) begin
                    total_bytes_written <= total_bytes_written + 
                                          ((burst_len + 1) * BYTES_PER_BEAT);
                end
                
                // Detectar overflow del FIFO
                if (fifo_full && s_axis_tvalid) begin
                    overflow_flag <= 1'b1;
                end
            end
        end
    end

    //=========================================================================
    // Generación de señales de estado
    //=========================================================================
    
    always_comb begin : proc_status
        status_o.state         = state;
        status_o.write_ptr     = write_offset;
        status_o.bytes_written = total_bytes_written;
        status_o.overflow      = overflow_flag;
    end

    //=========================================================================
    // Assertions de verificación
    //=========================================================================
    
`ifndef SYNTHESIS
    /**
     * @brief Assertion: AWVALID estable hasta handshake
     */
    property p_awvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axi_awvalid && !m_axi_awready) |=> m_axi_awvalid;
    endproperty
    
    assert property (p_awvalid_stable)
        else $error("[RAM_WRITER] AWVALID cayó sin handshake");
    
    /**
     * @brief Assertion: WVALID estable hasta handshake
     */
    property p_wvalid_stable;
        @(posedge aclk) disable iff (!aresetn)
        (m_axi_wvalid && !m_axi_wready) |=> m_axi_wvalid;
    endproperty
    
    assert property (p_wvalid_stable)
        else $error("[RAM_WRITER] WVALID cayó sin handshake");
    
    /**
     * @brief Assertion: WLAST solo en último beat
     */
    property p_wlast_correct;
        @(posedge aclk) disable iff (!aresetn)
        (m_axi_wlast && m_axi_wvalid) |-> (beat_count == burst_len);
    endproperty
    
    assert property (p_wlast_correct)
        else $error("[RAM_WRITER] WLAST incorrecto");
    
    /**
     * @brief Assertion: No leer de FIFO vacío
     */
    property p_no_empty_read;
        @(posedge aclk) disable iff (!aresetn)
        fifo_rd_en |-> !fifo_empty;
    endproperty
    
    assert property (p_no_empty_read)
        else $error("[RAM_WRITER] Lectura de FIFO vacío");
    
    /**
     * @brief Assertion: Respuesta OKAY para escrituras
     */
    property p_write_okay;
        @(posedge aclk) disable iff (!aresetn)
        (m_axi_bvalid && m_axi_bready) |-> (m_axi_bresp == 2'b00);
    endproperty
    
    assert property (p_write_okay)
        else $warning("[RAM_WRITER] Respuesta de escritura no-OKAY: %b", m_axi_bresp);
    
    /**
     * @brief Cover: Burst completo exitoso
     */
    cover property (@(posedge aclk) disable iff (!aresetn)
        (state == WR_DATA) ##[1:$] (state == WR_RESP && m_axi_bvalid));
    
    /**
     * @brief Cover: Múltiples bursts consecutivos
     */
    cover property (@(posedge aclk) disable iff (!aresetn)
        (state == WR_RESP && m_axi_bvalid) ##[1:5] (state == WR_CALC));
`endif

endmodule : axis_ram_writer

`default_nettype wire
