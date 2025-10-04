// uart_tx.sv
//
// UART Transmitter module.
// Refactored for Robustness: Uses Shift Register approach.
// Transmits serial data at 115200 baud, 8N1 format.

module uart_tx #(
    parameter integer CLK_FREQ = 50_000_000,   // 50 MHz system clock
    parameter integer BAUD_RATE = 115200       // 115200 baud
) (
    input  logic        clk_50mhz,     // System clock
    input  logic        rst_n,         // Asynchronous active-low reset
    input  logic        tx_start,      // Start transmission pulse
    input  logic [7:0]  tx_data,       // Data to transmit

    output logic        tx_out,        // Serial data output
    output logic        tx_busy        // Indicates transmitter is busy
);

    // Baud rate generation
    localparam integer BaudTickDivider = CLK_FREQ / BAUD_RATE;

    // FSM states
    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT,
        INTER_BYTE_DELAY
    } tx_state_e;

    tx_state_e current_state, next_state;

    // Internal registers
    logic [9:0]           baud_tick_counter;
    logic                 baud_tick;

    // Shift register and counters
    logic [7:0]           shifter_reg;   // Stores data and shifts right
    logic [3:0]           bit_count;     // Counts bits 0-7
    logic                 tx_reg;        // Registered output
    logic                 tx_busy_reg;

    // -------------------------------------------------------------------------
    // 1. Baud Tick Generator
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n) begin
            baud_tick_counter <= '0;
            baud_tick         <= 1'b0;
        end else begin
            if (baud_tick_counter == BaudTickDivider - 1) begin
                baud_tick_counter <= '0;
                baud_tick         <= 1'b1;
            end else begin
                baud_tick_counter <= baud_tick_counter + 1;
                baud_tick         <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 2. FSM Sequential Logic (Data Path)
    // -------------------------------------------------------------------------
    always_ff @(posedge clk_50mhz) begin
        if (!rst_n) begin
            current_state <= IDLE;
            shifter_reg   <= '0;
            bit_count     <= '0;
            tx_reg        <= 1'b1; // Idle High
            tx_busy_reg   <= 1'b0;
        end else begin
            // Output is registered to prevent glitches
            tx_busy_reg <= (current_state != IDLE);

            case (current_state)
                IDLE: begin
                    tx_reg <= 1'b1; // Idle High
                    if (tx_start) begin
                        shifter_reg   <= tx_data; // Latch data
                        current_state <= START_BIT;
                        tx_reg        <= 1'b0;    // Drive Start Bit immediately
                    end
                end

                START_BIT: begin
                    // Hold 0 for one baud period
                    if (baud_tick) begin
                        current_state <= DATA_BITS;
                        tx_reg        <= shifter_reg[0]; // Put LSB on line
                        shifter_reg   <= shifter_reg >> 1; // Shift for next time
                        bit_count     <= '0;
                    end
                end

                DATA_BITS: begin
                    if (baud_tick) begin
                        if (bit_count == 7) begin
                            current_state <= STOP_BIT;
                            tx_reg        <= 1'b1; // Drive Stop Bit
                        end else begin
                            bit_count     <= bit_count + 1;
                            tx_reg        <= shifter_reg[0]; // Put next LSB
                            shifter_reg   <= shifter_reg >> 1; // Shift
                        end
                    end
                end

                STOP_BIT: begin
                    if (baud_tick) begin
                        current_state <= INTER_BYTE_DELAY;
                    end
                end

                INTER_BYTE_DELAY: begin
                    if (baud_tick) begin
                        current_state <= IDLE;
                    end
                end

                default: current_state <= IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 3. FSM Next State Logic (Combinational)
    // -------------------------------------------------------------------------
    // Note: In this specific design, the transitions are handled directly
    // inside the sequential block above for simplicity and to ensure data/state
    // synchronization. The 'next_state' variable declared earlier is technically
    // redundant in this specific coding style (Merged State/Output FSM),
    // but I kept the structure clean.

    // -------------------------------------------------------------------------
    // 4. Output Assignments
    // -------------------------------------------------------------------------
    assign tx_out  = tx_reg;
    assign tx_busy = tx_busy_reg;

endmodule
