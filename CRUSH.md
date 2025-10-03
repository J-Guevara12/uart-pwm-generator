# CRUSH.md

## Project Overview
This is a digital design project for a PWM generator controlled via UART in Verilog/SystemVerilog. Focus on RTL implementation, verification with testbenches modeling UART at bit level, and coverage goals.

## Build Commands
- Compile RTL and testbench: iverilog -g2012 -o sim.vvp *.sv tb_*.sv
- Simulate full regression: vvp sim.vvp -lxt2 +ntb_random_seed_automatic +ntb_seed=$(date +%s)
- Generate VCD for waveform: vvp sim.vvp -vcd
- View waveform: gtkwave dump.vcd (install gtkwave if needed)

## Lint and Check Commands
- Lint with Verilator: verilator --lint-only -Wall --top-module top *.sv (install verilator)
- Syntax check: iverilog -t null *.sv tb_*.sv
- Coverage report: vvp sim.vvp; vcov sim.vvp.cov (for line/toggle coverage)

## Test Commands
- Run all tests: make test (setup Makefile with targets for directed and random tests)
- Run single test (e.g., duty cycle update): iverilog -o dc_test.vvp tb_duty_cycle.sv uart_model.sv && vvp dc_test.vvp | grep -E 'PASS|FAIL'
- Run UART buffer overflow test: iverilog -o overflow.vvp tb_buffer.sv && vvp overflow.vvp
- Coverage for single test: Add +UVM_TESTNAME=test_name to vvp command if using UVM

## Code Style Guidelines
- Language: SystemVerilog (IEEE 1800-2012) for RTL and testbenches
- Naming Conventions:
  - Modules: lowercase_with_underscores (e.g., pwm_generator)
  - Signals: snake_case, prefixes like clk_, rst_n, pwm_out
  - Parameters: UPPER_CASE (e.g., CLK_FREQ)
  - Testbenches: tb_module_name
- Formatting:
  - Indent: 2 spaces, no tabs
  - Lines: Max 100 characters
  - Always specify full port list in module declarations
  - Use ANSI-style port declarations
- Imports: Use `include for files; avoid global imports, scope packages locally
- Types: Use logic over reg/wire where possible; std_logic for VHDL if mixed
- Error Handling: Assert for illegal states; parameter guards for invalid inputs (e.g., if (DC > 99) no change)
- Comments: Brief header in modules with I/O and purpose; no inline unless complex logic
- Verification: Self-checking testbenches with assertions; scoreboard for PWM output vs expected; covergroups for POW2/POW5, duty cycle transitions
- Reset: Asynchronous active-low reset_n; synchronous resets where needed
- Clock Domains: Explicit clock enables from dividers; handshakes for cross-domain

## AI Usage Notes
Document AI interactions for assessment; evaluate suggestions critically; ensure academic integrity by overseeing outputs.

## Additional Info
- Clock: 50 MHz input
- UART: 115200 baud, 8N1
- PWM Freq: 50kHz / (2^POW2 * 5^POW5), POW2/POW5 = 0-3
- No external libs assumed; use built-in SystemVerilog features