`timescale 1ns / 1ps

module uart_rx_timing;

    // Parameters - Must match the DUT
    localparam integer ClkFreq = 50_000_000;
    localparam integer BaudRate = 115200;
    localparam integer RXBuferDepth = 32;

    // Timing Constants
    localparam CLK_PERIOD = 20; // 50MHz = 20ns
    // Baud period in nanoseconds (~8680.5 ns)
    localparam BAUD_PERIOD_NS = 1_000_000_000 / BaudRate;
    // Number of clock cycles per baud period (50,000,000 / 115200 = ~434.02)
    localparam BAUD_TICKS = ClkFreq / BaudRate;

    // DUT Signals
    logic        clk_50mhz;
    logic        rst_n;
    logic        rx_in;

    // Outputs to monitor (using SystemVerilog `bind` or internal access for real FSM state monitoring is better,
    // but we use external signals for basic check here)
    logic [7:0]  rx_data;
    logic        rx_valid;
    logic        eos_flag;
    logic        buffer_full;
    logic        fifo_read;
    logic [7:0]  fifo_data;
    logic        fifo_empty;

    // Internal Signals (for verification purposes only - Requires probing/dumping VCD)
    // We rely on the VCD dump to verify internal state variables like 'current_state' and 'baud_tick'

    // Instantiate the DUT
    uart_rx dut (.*); // Use SystemVerilog .* for cleaner instantiation

    // Clock Generation
    always #(CLK_PERIOD/2) clk_50mhz = ~clk_50mhz;

    // -------------------------------------------------------------------------
    // Tarea: send_timing_byte
    // Sends the start, 8 data bits (all 0s for simplicity), and stop bit.
    // We will verify baud_tick and FSM state transitions on this sequence.
    // -------------------------------------------------------------------------
    task automatic send_timing_byte(input [7:0] data);
        integer i;
        begin
            $display("TB: Sending Start Bit (t=%0t)", $time);
            rx_in = 1'b0; // Start bit (0)
            #(BAUD_PERIOD_NS);

            for (i = 0; i < 8; i++) begin
                $display("TB: Sending Data Bit %0d (%0b) (t=%0t)", i, data[i], $time);
                $display("Data: %b", rx_data);
                rx_in = data[i]; // Send data LSB first (using input data for a real test)
                #(BAUD_PERIOD_NS);
            end

            $display("TB: Sending Stop Bit (t=%0t)", $time);
            rx_in = 1'b1; // Stop bit (1)
        end
    endtask

    // -------------------------------------------------------------------------
    // Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        // Initialize signals
        clk_50mhz = 0;
        rst_n = 0;
        rx_in = 1'b1; // Idle high

        $display("Starting UART RX Timing Testbench...");

        // Reset
        #(CLK_PERIOD * 10) rst_n = 1'b1; // De-assert reset
        $display("Reset de-asserted at t=%0t", $time);

        // Wait for IDLE state to settle
        #(CLK_PERIOD * 5);

        // --- Test Case 1: State Transitions and Baud Tick Timing ---
        $display("\n--- Test Case 1: Verifying Timing and FSM Transitions (Sending 0xAA) ---");

        // This task will send 0xAA (10101010b)
        send_timing_byte(8'hAA);

        // Wait for the pulse to clear and FSM to return to IDLE
        @(posedge rx_valid); // Wait for the reception to complete

        // Check for validity (a basic check to see if the timing worked)
        if (rx_valid && rx_data == 8'hAA) begin
            $display("PASS: Data 0xAA received successfully. Timing appears correct.");
        end else begin
            $error("FAIL: Data 0xAA reception failed (rx_valid=%b, rx_data=0x%h). Check VCD for baud_tick and FSM states.", rx_valid, rx_data);
        end

        // Long wait to observe IDLE state after reception
        #(CLK_PERIOD * 50);

        // --- Test Case 2: Incomplete start bit (Noise) ---
        $display("\n--- Test Case 2: Incomplete Start Bit (Noise) ---");

        rx_in = 1'b0; // Start bit detected
        #(CLK_PERIOD * 5); // Short duration (less than half the bit period)
        rx_in = 1'b1; // Signal goes high again

        // The FSM should transition to START_BIT, but then return to IDLE
        // The VCD must be checked to confirm that 'current_state' went: IDLE -> START_BIT -> IDLE
        $display("Check VCD: FSM should return to IDLE quickly.");

        #(BAUD_PERIOD_NS * 2); // Wait for the noise to clear

        $display("UART RX Timing Testbench Finished");
        $finish;
    end

    // VCD Dumping
    initial begin
        $dumpfile("uart_rx_timing.vcd");
        // Dump all signals in the module and the DUT's internal signals
        $dumpvars(0, uart_rx_timing);
    end

endmodule
