// uart_buffer_tb.sv
//
// Testbench for uart_rx module, specifically focusing on buffer functionality.
// Verifies buffer overflow, end-of-string buffer reset.

`timescale 1ns / 1ps

module tb_uart_buffer;

    // Parameters from uart_rx module
    localparam CLK_FREQ = 50_000_000;
    localparam BAUD_RATE = 115200;
    localparam OVERSAMPLING = 16;
    localparam RX_BUFFER_DEPTH = 32;

    // Clock period calculation
    localparam CLK_PERIOD = 1_000_000_000 / CLK_FREQ; // in ps
    localparam BAUD_PERIOD = 1_000_000_000 / BAUD_RATE; // in ps

    // DUT signals
    logic        clk_50mhz;
    logic        rst_n;
    logic        rx_in;

    logic [7:0]  rx_data;
    logic        rx_valid;
    logic        eos_flag;
    logic        buffer_full;

    // Instantiate the DUT
    uart_rx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .OVERSAMPLING(OVERSAMPLING),
        .RX_BUFFER_DEPTH(RX_BUFFER_DEPTH)
    ) dut (
        .clk_50mhz(clk_50mhz),
        .rst_n(rst_n),
        .rx_in(rx_in),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .eos_flag(eos_flag),
        .buffer_full(buffer_full)
    );

    // Clock generation
    always begin
        clk_50mhz = 1'b0;
        #(CLK_PERIOD / 2) clk_50mhz = 1'b1;
        #(CLK_PERIOD / 2);
    end

    // Task to send a byte
    task send_byte;
        input [7:0]  byte_to_send;
        logic [7:0]  temp_byte;
        integer      i;
    begin
        temp_byte = byte_to_send;
        rx_in = 1'b0; // Start bit
        #(BAUD_PERIOD); // Wait for start bit duration

        for (i = 0; i < 8; i = i + 1) begin
            rx_in = temp_byte[i]; // LSB first
            #(BAUD_PERIOD);
        end

        rx_in = 1'b1; // Stop bit
        #(BAUD_PERIOD); // Wait for stop bit duration
        #(BAUD_PERIOD); // Inter-byte delay (1 bit spacing)
        rx_in = 1'b1; // Ensure idle high
    end
    endtask

    // Test sequence
    initial begin
        $display("Starting UART Buffer Testbench");

        // Initialize signals
        rst_n = 1'b0;
        rx_in = 1'b1; // Idle high

        #(CLK_PERIOD * 10) rst_n = 1'b1; // De-assert reset
        $display("Reset de-asserted");

        // Test Case 1: Fill the buffer to its capacity (RX_BUFFER_DEPTH bytes)
        $display("\nTest Case 1: Filling the buffer with %0d bytes.", RX_BUFFER_DEPTH);
        for (integer k = 0; k < RX_BUFFER_DEPTH; k = k + 1) begin
            send_byte(8'h10 + k);
            // Use for debug:
            // $display("Sending %h, received %h", 8'h10 + k[7:0], rx_data);
            #(CLK_PERIOD * 5); // Small delay to allow processing
        end


        if (buffer_full) begin
            $display("PASS: buffer_full flag detected after filling buffer.");
        end else begin
            $error("FAIL: buffer_full flag not detected after filling buffer. buffer_full=%b", buffer_full);
        end

        // Test Case 2: Attempt to send more data when buffer is full (should stall)
        $display("\nTest Case 2: Attempting to send an additional byte when buffer is full.");
        #(CLK_PERIOD * 5); // Wait
        send_byte(8'hFF); // This byte should be ignored or not stored
        #(CLK_PERIOD * 5); // Wait

        // The `uart_rx` module will stall when full, meaning rx_valid won't assert for new data.
        // We can't directly check if it was ignored, but we can check if buffer_full remains high
        // and the internal buffer_count does not increase.
        // For now, we'll rely on the `buffer_full` remaining high and no `rx_valid` for `8'hFF`.
        if (buffer_full) begin
            $display("PASS: Buffer remained full as expected.");
        end else begin
            $error("FAIL: Buffer was not full after attempting to send extra byte. buffer_full=%b", buffer_full);
        end
        // A more robust check would involve reading from the buffer and verifying the content.

        #(CLK_PERIOD * 5); // Wait
        // Test Case 3: Send an End-of-String character to reset the buffer
        $display("\nTest Case 3: Sending CR (0x0D) to reset buffer.");
        send_byte(8'h0D); // CR
        #(CLK_PERIOD * 5); // Wait for processing

        if (eos_flag) begin
            $display("PASS: eos_flag detected.");
            // After eos_flag, buffer_full should go low, and buffer_count should be 0
            if (!buffer_full) begin // and ideally internal buffer_count is 0
                $display("PASS: Buffer not full after EOS (reset).");
            end else begin
                $error("FAIL: Buffer still full after EOS. buffer_full=%b", buffer_full);
            end
        end else begin
            $error("FAIL: eos_flag not detected after CR. eos_flag=%b", eos_flag);
        end

        // Test Case 4: Send data after buffer reset
        $display("\nTest Case 4: Sending data after buffer reset.");
        send_byte(8'hAA);

        if (rx_data == 8'hAA) begin
            $display("PASS: Received 0xAA after buffer reset.");
        end else begin
            $error("FAIL: Did not receive 0xAA after buffer reset. rx_valid=%b, rx_data=0x%h", rx_valid, rx_data);
        end

        $display("UART Buffer Testbench Finished");
        $finish;
    end

    // Monitor for debugging
    initial begin
        $dumpfile("uart_buffer_tb.vcd");
        $dumpvars(0, tb_uart_buffer);
    end

endmodule
