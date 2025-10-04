iverilog -g2012 -o vvps/uart_rx_tb.vvp modules/uart_rx.sv testbenches/uart_rx_tb.sv && vvp vvps/uart_rx_tb.vvp
iverilog -g2012 -o vvps/uart_rx_timing.vvp modules/uart_rx.sv testbenches/uart_rx_timing.sv && vvp vvps/uart_rx_timing.vvp
iverilog -g2012 -o vvps/uart_buffer_tb.vvp modules/uart_rx.sv testbenches/uart_buffer_tb.sv && vvp vvps/uart_buffer_tb.vvp
