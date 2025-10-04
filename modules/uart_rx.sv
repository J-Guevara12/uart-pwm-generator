// uart_rx.sv
//
// UART Receiver module.
// Receives serial data at 115200 baud, 8N1 format.
// Includes a 32-byte FIFO buffer, end-of-string detection, and buffer overflow handling.
// All inputs and outputs are registered with reset.

module uart_rx #(
    parameter integer CLK_FREQ = 50_000_000,   // 50 MHz system clock
    parameter integer BAUD_RATE = 115200,      // 115200 baud
    parameter integer OVERSAMPLING = 16,       // Oversampling rate for baud detection
    parameter integer RX_BUFFER_DEPTH = 32     // 32-byte RX buffer
) (
    input  logic        clk_50mhz,     // System clock
    input  logic        rst_n,         // Asynchronous active-low reset
    input  logic        rx_in,         // Serial data input
    input  logic         fifo_read,      // Señal de lectura (Read Enable)

    output logic [7:0]  rx_data,       // Received byte output
    output logic        rx_valid,      // Indicates a valid byte is available
    output logic        eos_flag,      // End-of-string flag (active high for one clock cycle)
    output logic        buffer_full,    // Indicates RX buffer is full
    output logic [7:0]   fifo_data,      // Datos leídos de la FIFO
    output logic         fifo_empty      // Bandera de vacío
);

    // Baud rate generation
    localparam integer BAUD_TICK_DIVIDER = CLK_FREQ / BAUD_RATE;
    localparam integer SAMPLE_POINT = BAUD_TICK_DIVIDER / 2; // Mid-point for sampling

    // FSM states
    typedef enum logic [1:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT
    } rx_state_e;

    rx_state_e current_state, next_state;

    // Internal registers
    logic [9:0]           baud_tick_counter; // Counts system clock cycles for baud rate
    logic                 baud_tick;         // Pulse once per baud period
    logic [3:0]           bit_count_reg;     // Counts start, data, stop bits (0-9)
    logic [7:0]           data_reg;
    logic                 rx_in_d1, rx_in_d2; // For synchronizer

    // FIFO Buffer
    logic [4:0]           head_ptr, tail_ptr;
    logic [7:0]           rx_buffer [RX_BUFFER_DEPTH-1:0];
    logic [5:0]           buffer_count;

    // Registered outputs
    logic [7:0]           rx_data_reg;
    logic                 rx_valid_reg;
    logic                 eos_flag_reg;
    logic                 buffer_full_reg;

    // Baud tick generator
    always_ff @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            baud_tick_counter <= '0;
            baud_tick         <= 1'b0;
        end else begin
            if (baud_tick_counter == BAUD_TICK_DIVIDER - 1) begin
                baud_tick_counter <= '0;
                baud_tick         <= 1'b1;
            end else begin
                baud_tick_counter <= baud_tick_counter + 1;
                baud_tick         <= 1'b0;
            end
        end
    end

    // Input synchronizer and debounce (basic, for demonstration)
    always_ff @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            rx_in_d1 <= 1'b1; // UART idle is high
            rx_in_d2 <= 1'b1;
        end else begin
            rx_in_d1 <= rx_in;
            rx_in_d2 <= rx_in_d1;
        end
    end

    // State machine sequential logic
    always_ff @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
            bit_count_reg <= '0;
            data_reg      <= '0;
            rx_data_reg   <= '0;
            rx_valid_reg  <= 1'b0;
            eos_flag_reg  <= 1'b0;
        end else begin
            current_state <= next_state;
            rx_valid_reg  <= 1'b0; // Default to not valid for this clock cycle

            case (current_state)
                IDLE: begin
                    if (!rx_in_d2) begin // Detect falling edge for start bit
                        baud_tick_counter <= '0;
                        bit_count_reg <= '0;
                        data_reg      <= '0;
                    end
                end
                START_BIT: begin
                    if (baud_tick_counter == SAMPLE_POINT) begin // Sample start bit in the middle
                        if (rx_in_d2) begin // If not low, spurious start bit
                            // Stay in IDLE or transition to IDLE via next_state logic
                        end
                    end
                    if (baud_tick) begin // After one full bit period, prepare for data bits
                        bit_count_reg <= '0; // Reset for data bits (starting from data0)
                    end
                end
                DATA_BITS: begin
                    if (baud_tick_counter == SAMPLE_POINT) begin // Sample data bit in the middle
                        data_reg <= {rx_in_d2, data_reg[7:1]}; // Shift in LSB first
                    end
                    if (baud_tick) begin // After one full bit period
                        bit_count_reg <= bit_count_reg + 1;
                        // Latch the received byte when the last data bit is sampled and ready
                        if (bit_count_reg == 8) begin
                            rx_data_reg <= data_reg; // Latch the 8th data bit
                        end
                    end
                end
                STOP_BIT: begin
                    if (baud_tick_counter == SAMPLE_POINT) begin // Sample stop bit in the middle
                        // We don't sample the stop bit value into data_reg. It should be high.
                        // Framing error check: if rx_in_d2 is '0' here, it's a framing error.
                    end
                    if (baud_tick) begin // After one full stop bit period
                        rx_valid_reg <= 1'b1;
                        // Check for end of string characters (CR/LF)
                        if (data_reg == 8'h0D || data_reg == 8'h0A) begin // CR or LF
                            eos_flag_reg <= 1'b1;
                        end
                        bit_count_reg <= '0; // Reset for next byte
                        data_reg      <= '0;
                    end
                end
            endcase
        end
    end

    // State machine combinational logic
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (!rx_in_d2) begin // Detect falling edge for start bit
                    next_state = START_BIT;
                end
            end
            START_BIT: begin
                eos_flag_reg  <= 1'b0;
                // Transition to DATA_BITS after one full start bit period
                if (baud_tick_counter == BAUD_TICK_DIVIDER - 1) begin 
                    // Check for framing error if start bit was not low
                    if (rx_in_d2) begin 
                        next_state = IDLE; // Spurious start bit, return to idle
                    end else begin
                        next_state = DATA_BITS;
                    end
                end
            end
            DATA_BITS: begin
                // Transition to STOP_BIT after 8 data bits are sampled and processed.
                // This happens when bit_count_reg has just been incremented to 7 (meaning 8 bits have passed).
                if (bit_count_reg == 8 && baud_tick) begin
                    next_state = STOP_BIT;
                end
            end
            STOP_BIT: begin
                // Transition to IDLE after one full stop bit period
                if (baud_tick) begin 
                    next_state = IDLE;
                end
            end
        endcase
    end

    // FIFO Buffer logic
    always_ff @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= '0;
            tail_ptr <= '0;
            buffer_count <= '0;
            buffer_full_reg <= 1'b0;
        end else begin
            // Write to FIFO if rx_valid_reg is high AND buffer is NOT full
            if (rx_valid_reg && !buffer_full_reg) begin
                rx_buffer[head_ptr] <= rx_data_reg;
                head_ptr <= head_ptr + 1;
            end

            // Cuando el Parser pide datos
            if (fifo_read && (buffer_count > 0)) begin
                tail_ptr <= tail_ptr + 1;
            end

            // Incrementa si escribe y no lee
            if ((rx_valid_reg && !buffer_full_reg) && !(fifo_read && buffer_count > 0)) begin
                buffer_count <= buffer_count + 1;
            end
            // Decrementa si lee y no escribe
            else if (!(rx_valid_reg && !buffer_full_reg) && (fifo_read && buffer_count > 0)) begin
                buffer_count <= buffer_count - 1;
            end

            // Reset buffer pointer on End-of-String flag
            if (eos_flag_reg) begin // Ojo: Si ya cambiaste a eos_latch, usa eos_latch
                head_ptr     <= '0;
                tail_ptr     <= '0;
                buffer_count <= '0;
            end

            // Update buffer full flag based on buffer count
            buffer_full_reg <= (buffer_count == RX_BUFFER_DEPTH);
        end
    end

    assign rx_data = rx_data_reg;
    assign rx_valid = rx_valid_reg;
    assign eos_flag = eos_flag_reg;
    assign buffer_full = buffer_full_reg;

    assign fifo_data = rx_buffer[tail_ptr];
    assign fifo_empty = (buffer_count == 0);

endmodule
