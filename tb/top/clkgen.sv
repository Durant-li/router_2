// Clock waveform generator controlled by clock_and_reset_if.
module clkgen (
  output logic        clock = 1'b0,
  input  logic        run_clock,
  input  logic [31:0] clock_period
);

  always begin
    #(clock_period / 2);
    clock = run_clock ? ~clock : 1'b0;
  end

endmodule : clkgen
