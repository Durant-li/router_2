// Project clock/reset control interface. Reset is active high.
interface clock_and_reset_if (
  input  logic        clock,
  output logic        reset,
  output logic        run_clock = 1'b0,
  output logic [31:0] clock_period = 32'd10
);

  int unsigned reset_cycles_remaining = 0;

  initial reset = 1'b0;

  task automatic configure(
    input int unsigned new_clock_period,
    input int unsigned new_reset_cycles,
    input bit          enable_clock
  );
    clock_period          = new_clock_period;
    reset_cycles_remaining = new_reset_cycles;
    run_clock             = enable_clock;
  endtask

  always @(posedge clock) begin
    if (reset_cycles_remaining > 0) begin
      reset <= 1'b1;
      reset_cycles_remaining--;
    end
    else begin
      reset <= 1'b0;
    end
  end

endinterface : clock_and_reset_if
