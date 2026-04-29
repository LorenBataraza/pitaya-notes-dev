/**
 * @file trigger_combiner.sv
 * @brief Combinador de triggers de multiples canales
 *
 * Implementa logica configurable para combinar las senales de trigger
 * de multiples canales en una unica senal para el scope.
 *
 * Modos soportados:
 *   - OR:      Cualquier trigger activa el scope
 *   - AND:     Todos los triggers deben estar activos
 *   - CH0:     Solo usa trigger del canal 0
 *   - CH1:     Solo usa trigger del canal 1
 *   - BLOCK:   CH0 activa solo si CH1 esta inactivo (trig0 && ~trig1)
 *   - BLOCK_R: CH1 activa solo si CH0 esta inactivo (trig1 && ~trig0)
 *
 * @note El sistema es extensible a 4 canales. Los canales 2 y 3
 *       estan preparados pero no conectados actualmente.
 */

`timescale 1ns/1ps

module trigger_combiner #(
    parameter int NUM_CHANNELS = 2   ///< Numero de canales (2 o 4)
) (
    input  logic                    aclk,
    input  logic                    aresetn,
    
    /// Triggers de entrada (uno por canal)
    input  logic [NUM_CHANNELS-1:0] triggers_in,
    
    /// Configuracion del modo de combinacion
    input  logic [2:0]              combine_mode,
    
    /// Mascara de canales habilitados
    input  logic [NUM_CHANNELS-1:0] channel_mask,
    
    /// Trigger combinado de salida
    output logic                    trigger_out,
    
    /// Indica cual canal origino el trigger (para debug)
    output logic [NUM_CHANNELS-1:0] trigger_source
);

    //=========================================================================
    // Modos de Combinacion
    //=========================================================================
    
    localparam logic [2:0] MODE_OR      = 3'b000;  ///< OR de todos
    localparam logic [2:0] MODE_AND     = 3'b001;  ///< AND de todos
    localparam logic [2:0] MODE_CH0     = 3'b010;  ///< Solo canal 0
    localparam logic [2:0] MODE_CH1     = 3'b011;  ///< Solo canal 1
    localparam logic [2:0] MODE_BLOCK   = 3'b100;  ///< CH0 && ~CH1
    localparam logic [2:0] MODE_BLOCK_R = 3'b101;  ///< CH1 && ~CH0

    //=========================================================================
    // Triggers enmascarados
    //=========================================================================
    
    logic [NUM_CHANNELS-1:0] masked_triggers;
    
    assign masked_triggers = triggers_in & channel_mask;

    //=========================================================================
    // Logica de Combinacion
    //=========================================================================
    
    logic combined;
    
    always_comb begin
        case (combine_mode)
            MODE_OR: begin
                // OR: cualquier canal activo
                combined = |masked_triggers;
            end
            
            MODE_AND: begin
                // AND: todos los canales habilitados deben estar activos
                combined = &(masked_triggers | ~channel_mask);
            end
            
            MODE_CH0: begin
                // Solo canal 0
                combined = masked_triggers[0];
            end
            
            MODE_CH1: begin
                // Solo canal 1
                combined = (NUM_CHANNELS > 1) ? masked_triggers[1] : 1'b0;
            end
            
            MODE_BLOCK: begin
                // Canal 0 dispara solo si canal 1 NO esta activo
                // Util para ignorar ruido en un canal
                combined = masked_triggers[0] && 
                           ((NUM_CHANNELS > 1) ? ~triggers_in[1] : 1'b1);
            end
            
            MODE_BLOCK_R: begin
                // Canal 1 dispara solo si canal 0 NO esta activo
                combined = (NUM_CHANNELS > 1) ? 
                           (masked_triggers[1] && ~triggers_in[0]) : 1'b0;
            end
            
            default: begin
                // Default: OR
                combined = |masked_triggers;
            end
        endcase
    end

    //=========================================================================
    // Registro de Salida
    //=========================================================================
    
    always_ff @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            trigger_out    <= 1'b0;
            trigger_source <= '0;
        end else begin
            trigger_out    <= combined;
            trigger_source <= masked_triggers;
        end
    end

    //=========================================================================
    // Assertions
    //=========================================================================
    
    // Verificar que al menos un canal esta habilitado
    property at_least_one_channel;
        @(posedge aclk) disable iff (!aresetn)
        |channel_mask;
    endproperty
    // Comentado porque puede ser valido tener todos deshabilitados
    // assert property (at_least_one_channel);
    
    // Verificar modo valido
    property valid_mode;
        @(posedge aclk) disable iff (!aresetn)
        combine_mode <= 3'b101;
    endproperty
    assert property (valid_mode) else
        $warning("[TRIG_COMB] Invalid combine_mode: %0d", combine_mode);

endmodule : trigger_combiner
