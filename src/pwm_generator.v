module pwm_generator (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio,        
    input  wire       clk,
    input  wire       rst_n
);
  
  // --------------------------------------------------
  // Inputs & Constraint Handling
  // --------------------------------------------------
  wire enable = ui_in[0];
  wire [3:0] raw_period = ui_in[4:1]; // 0 to 15
  wire invert = ui_in[5];
  wire [3:0] raw_duty = uio[3:0];     
  
  // CONSTRAINT 1: Period cannot be 0, 1, or 2 to protect Sky130 output pad bandwidth.
  // If raw_period is less than 3, force it to 3.
  wire [3:0] period = (raw_period < 4'd3) ? 4'd3 : raw_period;
  
  // CONSTRAINT 2: Duty cycle cannot exceed period. Clamped to the new 'period' value.
  wire [3:0] duty = (raw_duty > period) ? period : raw_duty;
  
  // --------------------------------------------------
  // Up Counter (0 to period-1)
  // --------------------------------------------------
  reg [3:0] counter;

  always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
          counter <= 4'd0;
      end else if (enable) begin
          // Because period is at least 3, counter resets properly at period-1
          if (counter >= (period - 4'd1))
              counter <= 4'd0;
          else
              counter <= counter + 1'b1;
      end
  end
  
  // --------------------------------------------------
  // PWM Output Generation
  // --------------------------------------------------
  wire pwm_raw;

  // With 'duty' clamped to 'period', this properly handles 0% to 100%
  // e.g., if duty==period, (counter < duty) is always true, yielding 100% duty cycle.
  assign pwm_raw = (counter < duty);

  wire pwm = invert ? ~pwm_raw : pwm_raw;

  // --------------------------------------------------
  // Outputs
  // --------------------------------------------------
  assign uo_out[0] = enable ? pwm  : 1'b0; // pwm out
  assign uo_out[1] = enable ? ~pwm : 1'b0; // complementary pwm out
  assign uo_out[7:2] = 6'b0;

endmodule
