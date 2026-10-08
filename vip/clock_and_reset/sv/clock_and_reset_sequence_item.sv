// One clock/reset configuration request.
class clock_and_reset_sequence_item extends uvm_sequence_item;

  int unsigned clock_period;
  int unsigned reset_cycles;
  bit          run_clock;

  `uvm_object_utils_begin(clock_and_reset_sequence_item)
    `uvm_field_int(clock_period, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(reset_cycles, UVM_DEFAULT | UVM_DEC)
    `uvm_field_int(run_clock, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "clock_and_reset_sequence_item");
    super.new(name);
  endfunction

endclass : clock_and_reset_sequence_item
