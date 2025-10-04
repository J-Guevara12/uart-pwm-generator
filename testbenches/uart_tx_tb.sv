`timescale 1ns / 1ps

module tb_uart_tx;

    // =========================================================================
    // PARAMETERS & CONSTANTS
    // =========================================================================
    localparam CLK_FREQ      = 50_000_000;
    localparam BAUD_RATE     = 115200;
    localparam CLK_PERIOD    = 20; // 20ns (50MHz)
    localparam BAUD_PERIOD   = 8680; // 8.68us (115200 baud)
    localparam BAUD_TOLERANCE = 200; // Tolerance in ns for timing checks

    // =========================================================================
    // DUT SIGNALS
    // =========================================================================
    logic       clk_50mhz;
    logic       rst_n;
    logic       tx_start;
    logic [7:0] tx_data;
    
    wire        tx_out;
    wire        tx_busy;

    // =========================================================================
    // TESTBENCH VARIABLES
    // =========================================================================
    logic [7:0] rx_captured_data; // Data captured by our monitor task
    integer     errors = 0;       // Error counter

    // =========================================================================
    // DUT INSTANTIATION
    // =========================================================================
    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) dut (
        .clk_50mhz(clk_50mhz),
        .rst_n(rst_n),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_out(tx_out),
        .tx_busy(tx_busy)
    );

    // =========================================================================
    // CLOCK GENERATION
    // =========================================================================
    always #(CLK_PERIOD/2) clk_50mhz = ~clk_50mhz;

    // =========================================================================
    // TASKS
    // =========================================================================

    // 1. Monitor Task: Acts as a reference UART Receiver
    //    Samples tx_out to verify protocol compliance (Start/Data/Stop)
    task automatic monitor_uart_byte;
        output [7:0] data_out;
        integer i;
        begin
            // A. Wait for Start Bit (Falling Edge)
            @(negedge tx_out);
            
            // Verify Start Bit is stable low at the center
            #(BAUD_PERIOD / 2);
            if (tx_out !== 1'b0) begin
                $error("[MON] TIME %0t: Invalid Start Bit! Expected 0, got %b", $time, tx_out);
                errors++;
            end

            // B. Sample 8 Data Bits (LSB First)
            for (i = 0; i < 8; i++) begin
                #(BAUD_PERIOD); // Move to center of next bit
                data_out[i] = tx_out;
            end

            // C. Verify Stop Bit
            #(BAUD_PERIOD); // Move to center of stop bit
            if (tx_out !== 1'b1) begin
                $error("[MON] TIME %0t: Invalid Stop Bit! Expected 1, got %b", $time, tx_out);
                errors++;
            end
            
            // Wait out the rest of the stop bit
            #(BAUD_PERIOD / 2);
        end
    endtask

    // 2. Driver Task: Sends data to the DUT
    task automatic send_byte(input [7:0] byte_to_send);
        begin
            $display("[DRV] TIME %0t: Requesting transmission of 0x%h", $time, byte_to_send);
            
            // Wait for DUT to be ready
            wait(tx_busy == 1'b0);
            @(posedge clk_50mhz);
            
            // Drive inputs
            tx_data  <= byte_to_send;
            tx_start <= 1'b1;
            @(posedge clk_50mhz);
            tx_start <= 1'b0;

            // Optional: Verify tx_busy asserts shortly after start
            repeat(2) @(posedge clk_50mhz);
            if (tx_busy !== 1'b1) begin
                $error("[DRV] TIME %0t: tx_busy did not assert after tx_start!", $time);
                errors++;
            end
        end
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    initial begin
        // Initialize
        clk_50mhz = 0;
        rst_n     = 0;
        tx_start  = 0;
        tx_data   = 0;

        // Apply Reset
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        $display("\n==================================================");
        $display("Starting UART TX Robust Testbench");
        $display("==================================================\n");

        // ---------------------------------------------------------------------
        // TEST CASE 1: Standard Characters (Checking 0x55 - alternating bits)
        // ---------------------------------------------------------------------
        $display("--- Test Case 1: Standard Byte (0x55) ---");
        
        fork
            // Thread A: Drive the DUT
            begin
                send_byte(8'h55);
            end

            // Thread B: Monitor the Output
            begin
                monitor_uart_byte(rx_captured_data);
                if (rx_captured_data == 8'h55)
                    $display("[CHK] PASS: Sent 0x55, Received 0x55");
                else begin
                    $error("[CHK] FAIL: Sent 0x55, Received 0x%h", rx_captured_data);
                    errors++;
                end
            end
        join

        #(BAUD_PERIOD * 2); // Inter-byte delay

        // ---------------------------------------------------------------------
        // TEST CASE 2: Corner Cases (0x00 and 0xFF)
        // ---------------------------------------------------------------------
        $display("\n--- Test Case 2: Boundary Values (0x00 and 0xFF) ---");

        // Sub-test 2A: 0x00
        fork
            send_byte(8'h00);
            begin
                monitor_uart_byte(rx_captured_data);
                if (rx_captured_data !== 8'h00) begin
                    $error("[CHK] FAIL: Sent 0x00, Received 0x%h", rx_captured_data);
                    errors++;
                end else 
                    $display("[CHK] PASS: Sent 0x00, Verified.");
            end
        join
        
        #(BAUD_PERIOD);

        // Sub-test 2B: 0xFF
        fork
            send_byte(8'hFF);
            begin
                monitor_uart_byte(rx_captured_data);
                if (rx_captured_data !== 8'hFF) begin
                    $error("[CHK] FAIL: Sent 0xFF, Received 0x%h", rx_captured_data);
                    errors++;
                end else 
                    $display("[CHK] PASS: Sent 0xFF, Verified.");
            end
        join

        #(BAUD_PERIOD * 2);

        // ---------------------------------------------------------------------
        // TEST CASE 3: Randomized Stress Test
        // ---------------------------------------------------------------------
        $display("\n--- Test Case 3: Randomized Stress Test (5 Iterations) ---");

        for (int k = 0; k < 5; k++) begin
            logic [7:0] rand_byte;
            rand_byte = $random; // Generate random byte

            fork
                send_byte(rand_byte);
                begin
                    monitor_uart_byte(rx_captured_data);
                    if (rx_captured_data !== rand_byte) begin
                        $error("[CHK] FAIL: Iteration %0d - Sent 0x%h, Received 0x%h", k, rand_byte, rx_captured_data);
                        errors++;
                    end else begin
                        $display("[CHK] PASS: Iteration %0d - Sent 0x%h, Verified.", k, rand_byte);
                    end
                end
            join
            // Minimal gap between bytes to stress 'busy' logic
            @(posedge clk_50mhz); 
        end

        // =========================================================================
        // FINAL REPORT
        // =========================================================================
        $display("\n==================================================");
        if (errors == 0)
            $display("TESTBENCH COMPLETED SUCCESSFULLY: ALL CHECKS PASSED");
        else
            $display("TESTBENCH FAILED: %0d ERRORS FOUND", errors);
        $display("==================================================");
        $finish;
    end

    // VCD Dump for waveform debugging
    initial begin
        $dumpfile("uart_tx_.vcd");
        $dumpvars(0, tb_uart_tx);
    end

endmodule
