`timescale 1ns / 1ps

module uart_rx_tb;

    // Parameters
    localparam integer ClkFreq = 50_000_000;
    localparam integer BaudRate = 115200;
    localparam integer RXBufferDepth = 32;
    localparam integer ClkPeriod = 1_000_000_000 / ClkFreq; // 20ns
    localparam integer BaudPeriod = 1_000_000_000 / BaudRate; // ~8680ns

    // DUT signals
    logic        clk_50mhz;
    logic        rst_n;
    logic        rx_in;
    logic [7:0]  rx_data;
    logic        rx_valid;
    logic        eos_flag;
    logic        buffer_full;
    logic        fifo_read;
    logic [7:0]  fifo_data;
    logic        fifo_empty;

    // Instantiate DUT
    uart_rx #(
        .CLK_FREQ(ClkFreq),
        .BAUD_RATE(BaudRate),
        .RX_BUFFER_DEPTH(RXBufferDepth)
    ) dut (.*);

    // Clock generation
    always #(ClkPeriod/2) clk_50mhz = ~clk_50mhz;

    // Task to send a byte
    task send_byte(input [7:0] data);
        integer i;
        begin
            rx_in = 1'b0; // Start bit
            #(BaudPeriod + 100);
            for (i = 0; i < 8; i++) begin
                rx_in = data[i]; // LSB first
                #(BaudPeriod);
            end
            rx_in = 1'b1; // Stop bit
            #(BaudPeriod);
        end
    endtask

    // Inicialización
    initial begin
        clk_50mhz = 0;
        rst_n = 0;
        rx_in = 1;
        #(ClkPeriod * 10) rst_n = 1;

        $display("Starting UART RX Testbench");

        // --- TEST CASE 1: Single Character 'A' ---
        $display("\nTest Case 1: Sending 'A' (0x41)");

        fork
            // Hilo 1: Enviar datos
            begin
                send_byte(8'h41);
            end

            // Hilo 2: Esperar y verificar recepción
            begin
                // Esperamos el flanco de subida de rx_valid
                // Usamos un timeout por si falla
                fork
                    begin
                        @(posedge rx_valid);
                        if (rx_data === 8'h41)
                            $display("PASS: Received 'A' correctly.");
                        else
                            $error("FAIL: Expected 0x%b, got 0x%b", 8'h41, rx_data);
                    end
                    begin
                        // Timeout: Tiempo de transmisión + margen
                        #(BaudPeriod * 15);
                        $error("FAIL: Timeout waiting for rx_valid on 'A'");
                    end
                join_any
                disable fork; // Matar el hilo de timeout si llega el dato
            end
        join

         // Test Case 2: Send a sequence of characters "HELLO" (no EOS)

        $display("\nTest Case 2: Sending \"HELLO\"");

        send_byte(8'h48); // H
        send_byte(8'h45); // E
        send_byte(8'h4C); // L
        send_byte(8'h4C); // L
        send_byte(8'h4F); // O

        if (rx_data == 8'h4F && !eos_flag) begin

            $display("PASS: Received \"HELLO\" sequence, eos_flag is low.");

        end else begin
            $error("FAIL: \"HELLO\" sequence reception error. rx_valid=%b, rx_data=0x%h, eos_flag=%b", rx_valid, rx_data, eos_flag);
        end


        $display("Testbench Finished");
        $finish;
    end
    // VCD Dumping
    initial begin
        $dumpfile("uart_rx.vcd");
        // Dump all signals in the module and the DUT's internal signals
        $dumpvars(0, uart_rx_tb);
    end
endmodule
