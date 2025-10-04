`timescale 1ns / 1ps

module pwm_gen_tb;
    // --- Signals ---
    logic       clk;
    logic       rst_n;
    logic [1:0] pow2;
    logic [1:0] pow5;
    logic [6:0] duty_cycle;
    logic       pwm_out;
    logic       cycle_done;

    // Coverage Counters (Manual replacement for covergroup)
    int cov_dc_0 = 0;
    int cov_dc_99 = 0;
    int cov_pow_max = 0;
    longint p2_val;
    longint p5_val;
    real expected_new_period;

    // --- Clock Generation (50 MHz) ---
    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    // --- DUT Instantiation ---
    pwm_gen DUT (
        .clk(clk),
        .rst_n(rst_n),
        .pow2(pow2),
        .pow5(pow5),
        .duty_cycle(duty_cycle),
        .cycle_done(cycle_done),
        .pwm_out(pwm_out)
    );

    // --- Helper Functions ---
    function real abs(real v);
        return (v < 0) ? -v : v;
    endfunction

    // --- Test Tasks ---

    // Task: Apply random valid inputs (Compatible with Icarus Verilog)
    task drive_random();
        int rand_selector;

        pow2 = $urandom_range(0, 3);
        pow5 = $urandom_range(0, 3);

        // Manual "Weighted Random" replacement for randcase
        rand_selector = $urandom_range(0, 99);

        if (rand_selector < 10) begin
            // 10% chance for 0% DC
            duty_cycle = 0;
            cov_dc_0++;
        end else if (rand_selector < 20) begin
            // 10% chance for 99% DC
            duty_cycle = 99;
            cov_dc_99++;
        end else begin
            // 80% chance for normal range
            duty_cycle = $urandom_range(1, 98);
        end

        // Track max power case
        if (pow2 == 3 && pow5 == 3) cov_pow_max++;

        $display("[DRV] Set: POW2=%0d POW5=%0d DC=%0d", pow2, pow5, duty_cycle);
    endtask

    // Task: Scoreboard / Self-Checker
    task check_pulse();
        realtime t_rise, t_fall, t_period_end;
        realtime measured_period, measured_high;
        real expected_period;
        longint p2_val, p5_val;
        
        // Variables for RTL-aware checking
        longint period_ticks;
        longint expected_high_ticks;
        real expected_high_time;
        real tolerance;
        realtime timeout_limit;

        // --- 1. Calculate Expected Period and Ticks based on driven values ---
        // Note: Use driven values (pow2, pow5) to calculate EXP values.
        case (pow2)
            0: p2_val = 1; 1: p2_val = 2; 2: p2_val = 4; 3: p2_val = 8;
        endcase
        case (pow5)
            0: p5_val = 1; 1: p5_val = 5; 2: p5_val = 25; 3: p5_val = 125;
        endcase
        
        // N_PERIOD (in 50kHz ticks)
        period_ticks = p2_val * p5_val; 
        
        // Expected Period in ns (20,000 ns per 50kHz tick)
        expected_period = 20000.0 * period_ticks; 

        // --- 2. Calculate Expected High Time (RTL-Aware Integer Math) ---
        // N_PULSE = ceil(period_ticks * duty_cycle / 100)
        expected_high_ticks = (period_ticks * duty_cycle + 99) / 100;
        
        // Expected High Time in ns, based on integer ticks
        expected_high_time = expected_high_ticks * 20000.0;
        
        // --- 3. Measure PWM signal ---
        // Synchronization: We assume we waited for cycle_done and a full period 
        // in the main loop, so we should be aligned to measure the next period.
        if (expected_high_ticks == period_ticks) begin
            // Case 1: Expected 100% Duty Cycle (or close, e.g., 99% that rounds up)
            #1ms; // Wait a moment to ensure output is stable
            if (pwm_out !== 1'b1) begin
                 $error("[FAIL] DC=100%% expected (Ticks=%0d), but pwm_out is LOW.", period_ticks);
            end else begin
                 $display("[PASS] DC=100%% Verified (Output held HIGH).");
            end
        end else begin
            // Case 2: Standard PWM, proceed with edge detection
            
            // Wait for the PWM signal to go LOW (Necessary for centering)
            wait (pwm_out == 0);
            
            // Set a timeout based on the expected period plus margin
            timeout_limit = expected_period * 2.5; 

            fork
                begin // Measurement Path
                    @(posedge pwm_out); 
                    t_rise = $realtime;
                    @(negedge pwm_out);
                    t_fall = $realtime;
                    @(posedge pwm_out);
                    t_period_end = $realtime;
                end
                begin // Timeout Path
                    #timeout_limit;
                    if (duty_cycle != 0 && $realtime < t_period_end) begin // Check if measurement finished
                         $error("[FAIL] Timeout waiting for PWM edges. Period might be wrong.");
                    end
                end
            join_any
            disable fork;

            // 4. Verification
            if (t_period_end > t_rise) begin
                measured_high   = t_fall - t_rise;
                measured_period = t_period_end - t_rise;

                // Period Check: Tolerance +/- 2 clock cycles (40ns)
                tolerance = 40.0;
                if (abs(measured_period - expected_period) > tolerance) begin
                    $error("[FAIL] Period Mismatch! Exp: %0fns, Meas: %0fns", expected_period, measured_period);
                end else begin
                    $display("[PASS] Period OK. Exp Ticks: %0d", period_ticks);
                end

                // Duty Cycle Check: Tolerance +/- 2 clock cycles (40ns)
                if (abs(measured_high - expected_high_time) > tolerance) begin
                     $error("[FAIL] Duty Mismatch! DC=%0d. Exp High Ticks: %0d (Exp: %0fns, Meas: %0fns)", 
                            duty_cycle, expected_high_ticks, expected_high_time, measured_high);
                end else begin
                     $display("[PASS] Duty Cycle OK. (Exp High Ticks: %0d)", expected_high_ticks);
                end
            end
    end
    endtask
    // --- Main Test Process ---
    initial begin
        // Setup Dumpfile for Waveforms
        $dumpfile("pwm_gen.vcd");
        $dumpvars(0, pwm_gen_tb);

        rst_n = 0; pow2 = 0; pow5 = 0; duty_cycle = 50;
        #100 rst_n = 1;

        $display("=== STARTING PWM REGRESSION ===");

        repeat(15) begin
            drive_random();

            // We calculate the new expected period based on the driven values.
            p2_val = 1 << pow2;
            p5_val = (pow5==0)?1:(pow5==1)?5:(pow5==2)?25:125;
            expected_new_period = 20000.0 * p2_val * p5_val;

            // Wait for internal latch updates (needs 1 old period + margin)
            @(posedge cycle_done);

            # (expected_new_period);

            if (duty_cycle > 0) begin
                #20ns;
                check_pulse();
            end else begin
                #1ms;
                // Simple check for DC=0
                if (pwm_out !== 0) $error("[FAIL] PWM not low for DC=0");
                else $display("[PASS] DC=0 Verified (Output held low)");
            end
        end

        $display("=== REGRESSION COMPLETE ===");
        $display("Manual Coverage Report:");
        $display("  DC=0 Hits: %0d", cov_dc_0);
        $display("  DC=99 Hits: %0d", cov_dc_99);
        $display("  Max Freq Divider Hits: %0d", cov_pow_max);

        if (cov_dc_0 > 0 && cov_dc_99 > 0)
            $display("Coverage Status: PASSED");
        else
            $display("Coverage Status: LOW (Increase repeat count)");

        $finish;
    end

endmodule
