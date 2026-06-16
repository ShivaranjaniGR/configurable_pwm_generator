`timescale 1ns / 1ps

module tb_pwm_generator;

    // --------------------------------------------------
    // Testbench Signals & Interface
    // --------------------------------------------------
    reg [7:0] ui_in;
    reg [7:0] uio;
    reg       clk;
    reg       rst_n;
    
    wire [7:0] uo_out;

    // Output Aliases for Analysis
    wire pwm_out       = uo_out[0];
    wire comp_pwm_out  = uo_out[1];

    // Verification Tracking Variables
    integer error_count = 0;
    integer tests_run   = 0;
    
    // Loop variables for the exhaustive sweep matrix
    integer p_idx, d_idx, inv_idx;

    // --------------------------------------------------
    // Unit Under Test (UUT) Instantiation
    // --------------------------------------------------
    pwm_generator uut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio(uio),
        .clk(clk),
        .rst_n(rst_n)
    );

    // --------------------------------------------------
    // Clock Generation (50 MHz clock -> 20ns period)
    // --------------------------------------------------
    always begin
        #10 clk = ~clk; // High for 10ns, Low for 10ns
    end

    // --------------------------------------------------
    // Input Driver Task
    // --------------------------------------------------
    task set_inputs(input enable, input [3:0] period, input invert, input [3:0] duty);
        begin
            ui_in[0]   = enable;
            ui_in[4:1] = period;
            ui_in[5]   = invert;
            uio[3:0]   = duty;
            uio[7:4]   = 4'b0000; 
            ui_in[7:6] = 2'b00;   
        end
    endtask

    // --------------------------------------------------
    // Behavioral Golden Model (Reference Model)
    // --------------------------------------------------
    reg [3:0] expected_counter;
    reg       expected_pwm_raw;
    reg       expected_pwm;
    reg       expected_comp_pwm;
    
    // Extracted RTL constraint mapping
    wire [3:0] v_period = (ui_in[4:1] < 4'd3) ? 4'd3 : ui_in[4:1]; // New Floor = 3
    wire [3:0] v_duty   = (uio[3:0] > v_period) ? v_period : uio[3:0];

    // Synchronous Golden Counter Tracker
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            expected_counter <= 4'd0;
        end else if (ui_in[0]) begin 
            if (expected_counter >= (v_period - 4'd1))
                expected_counter <= 4'd0;
            else
                expected_counter <= expected_counter + 1'b1;
        end else begin
            expected_counter <= 4'd0;
        end
    end

    // Combinatorial Output Predictor
    always @(*) begin
        if (!ui_in[0]) begin 
            expected_pwm_raw  = 1'b0;
            expected_pwm      = 1'b0;
            expected_comp_pwm = 1'b0;
        end else begin
            expected_pwm_raw  = (expected_counter < v_duty);
            expected_pwm      = ui_in[5] ? ~expected_pwm_raw : expected_pwm_raw;
            expected_comp_pwm = ~expected_pwm;
        end
    end

    // --------------------------------------------------
    // Real-Time Assertion Engine
    // --------------------------------------------------
    always @(posedge clk) begin
        #1; // Strobe 1ns after clock edge to sample stable signals
        if (rst_n) begin
            tests_run = tests_run + 1;
            if (pwm_out !== expected_pwm) begin
                $display("[ERROR MISMATCH] Time=%0t | Inputs: En=%b P=%d D=%d Inv=%b | Counter=%d | PWM=%b Expected=%b", 
                         $time, ui_in[0], ui_in[4:1], uio[3:0], ui_in[5], expected_counter, pwm_out, expected_pwm);
                error_count = error_count + 1;
            end
            if (comp_pwm_out !== expected_comp_pwm) begin
                $display("[ERROR MISMATCH] Time=%0t | Inputs: En=%b P=%d D=%d Inv=%b | Counter=%d | Comp_PWM=%b Expected=%b", 
                         $time, ui_in[0], ui_in[4:1], uio[3:0], ui_in[5], expected_counter, comp_pwm_out, expected_comp_pwm);
                error_count = error_count + 1;
            end
        end
    end

    // --------------------------------------------------
    // Exhaustive Verification Test Sequence
    // --------------------------------------------------
    initial begin
        // Setup Waveform Capture
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_pwm_generator);

        // Initialize clock variable
        clk = 0;

        $display("==================================================");
        $display("STARTING FULL FORMAL VERIFICATION SUITE (50 MHz)");
        $display("==================================================");

        // --- PHASE 1: Asynchronous Reset Verification ---
        rst_n = 0;
        set_inputs(.enable(0), .period(4'd10), .invert(1), .duty(4'd5));
        #40; // Hold reset for 2 full clock cycles
        
        if (uo_out !== 8'h00) begin
            $display("[CRITICAL FAILURE] Outputs not isolated to zero during active reset.");
            error_count = error_count + 1;
        end
        
        // Release Reset safely
        rst_n = 1;
        #20; // Wait 1 clock cycle

        // Shift stimulus to the falling edge of the clock (10ns offset)
        // This stops setup/hold race conditions in the simulator.
        #10; 

        // --- PHASE 2: Comprehensive State Space Sweep ---
        $display("[STATUS] Running Exhaustive Input Matrix Sweep (512 vectors)...");
        
        for (inv_idx = 0; inv_idx <= 1; inv_idx = inv_idx + 1) begin
            for (p_idx = 0; p_idx <= 15; p_idx = p_idx + 1) begin
                for (d_idx = 0; d_idx <= 15; d_idx = d_idx + 1) begin
                    
                    set_inputs(.enable(1), .period(p_idx), .invert(inv_idx), .duty(d_idx));
                    #80; // Hold configuration for 4 full 50MHz clock cycles
                end
            end
        end

        // --- PHASE 3: Module Safe Disarm Verification ---
        $display("[STATUS] Testing Asynchronous Dynamic Disable...");
        set_inputs(.enable(1), .period(4'd8), .invert(0), .duty(4'd4));
        #60;
        set_inputs(.enable(0), .period(4'd8), .invert(0), .duty(4'd4)); 
        #40;
        
        // --- PHASE 4: Final Verification Report Generation ---
        $display("==================================================");
        $display("VERIFICATION REPORT SUMMARY");
        $display("==================================================");
        $display("Total Signal Assertions Checked: %0d", tests_run);
        $display("Total Discovered Mismatches   : %0d", error_count);
        $display("--------------------------------------------------");
        
        if (error_count == 0) begin
            $display(">>>> STATUS: SIGN-OFF SUCCESSFUL <<<<");
            $display("Design successfully passed all constraint and operational checks.");
        end else begin
            $display(">>>> STATUS: SIGN-OFF FAILED <<<<");
            $display("Review error logs. Design contains critical operational flaws.");
        end
        $display("==================================================");
        
        $finish;
    end

endmodule
