`timescale 1ns / 1ps

module pwm_gen #(
    parameter integer CLK_FREQ = 50_000_000,
    parameter integer REF_FREQ = 50_000
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic [1:0]  pow2,       // 0..3
    input  logic [1:0]  pow5,       // 0..3
    input  logic [6:0]  duty_cycle, // 0..99
    output logic        pwm_out,
    output logic        cycle_done
);

    // -------------------------------------------------------------------------
    // 1. 50kHz Clock Enable Generation
    // -------------------------------------------------------------------------
    localparam int Div50K = CLK_FREQ / REF_FREQ; // 1000
    logic [9:0] cnt_50k;
    logic       ce_50k;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_50k <= '0;
            ce_50k  <= 1'b0;
        end else begin
            if (cnt_50k == Div50K - 1) begin
                cnt_50k <= '0;
                ce_50k  <= 1'b1;
            end else begin
                cnt_50k <= cnt_50k + 1'b1;
                ce_50k  <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 2. Parameter Shadowing (Safe Updates)
    // -------------------------------------------------------------------------
    // Latch new parameters only when the current PWM cycle completes (cycle_done)
    logic [1:0] active_pow2;
    logic [1:0] active_pow5;
    logic [6:0] active_dc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_pow2 <= 2'd0;
            active_pow5 <= 2'd0;
            active_dc   <= 7'd0;
        end else if (cycle_done) begin
            active_pow2 <= pow2;
            active_pow5 <= pow5;
            active_dc   <= duty_cycle;
        end
    end

    // -------------------------------------------------------------------------
    // 3. Frequency Period Calculation
    // -------------------------------------------------------------------------
    logic [9:0] val_pow2;
    logic [9:0] val_pow5;
    logic [9:0] n_period;

    // Look-up tables for powers
    always_comb begin
        case (active_pow2)
            2'd0: val_pow2 = 1;  2'd1: val_pow2 = 2;
            2'd2: val_pow2 = 4;  2'd3: val_pow2 = 8;
            default: val_pow2 = 1;
        endcase
        case (active_pow5)
            2'd0: val_pow5 = 1;  2'd1: val_pow5 = 5;
            2'd2: val_pow5 = 25; 2'd3: val_pow5 = 125;
            default: val_pow5 = 1;
        endcase
    end

    assign n_period = val_pow2 * val_pow5;

    // -------------------------------------------------------------------------
    // 4. PWM Counter & Cycle Control
    // -------------------------------------------------------------------------
    logic [9:0] period_cnt;

    // Cycle is done when counter reaches max period.
    // Also forces a reset if period shrinks dynamically.
    assign cycle_done = (period_cnt >= n_period - 1) && ce_50k;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            period_cnt <= '0;
        end else if (ce_50k) begin
            if (period_cnt >= n_period - 1) begin
                period_cnt <= '0;
            end else begin
                period_cnt <= period_cnt + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 5. Centered Pulse Logic
    // -------------------------------------------------------------------------
    // Pulse Width (n_pulse) = ceil(N_PERIOD * DC / 100)
    logic [16:0] mult_res;
    logic [9:0]  n_pulse;

    assign mult_res = n_period * active_dc;
    assign n_pulse  = (mult_res + 99) / 100;

    // Start = (Period - Pulse) / 2
    // End   = Start + Pulse - 1
    logic [9:0] cnt_start;
    logic [9:0] cnt_end;

    assign cnt_start = (n_period - n_pulse) >> 1;
    assign cnt_end   = cnt_start + n_pulse - 1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_out <= 1'b0;
        end else begin
            if (active_dc == 0) begin
                pwm_out <= 1'b0;
            end else if (period_cnt >= cnt_start && period_cnt <= cnt_end) begin
                pwm_out <= 1'b1;
            end else begin
                pwm_out <= 1'b0;
            end
        end
    end

endmodule
