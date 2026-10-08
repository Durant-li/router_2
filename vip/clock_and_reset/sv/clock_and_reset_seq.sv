// Configurable protocol sequence: one item programs clock and reset generation.
class clock_and_reset_sequence
  extends uvm_sequence #(clock_and_reset_sequence_item);

  `uvm_object_utils(clock_and_reset_sequence)

  int unsigned clock_period = 10;
  int unsigned reset_cycles = 5;
  bit          run_clock    = 1'b1;

  function new(string name = "clock_and_reset_sequence");
    super.new(name);
  endfunction

  task body();
    clock_and_reset_sequence_item config_item;

    config_item =
      clock_and_reset_sequence_item::type_id::create("config_item");
    start_item(config_item);
    config_item.clock_period = clock_period;
    config_item.reset_cycles = reset_cycles;
    config_item.run_clock    = run_clock;
    finish_item(config_item);
  endtask

endclass : clock_and_reset_sequence


// Named default profile retained for all existing tests. The fields remain
// configurable, so a test or virtual sequence may reuse it for another reset.
class clk10_rst5_seq
  extends uvm_sequence #(clock_and_reset_sequence_item);

  `uvm_object_utils(clk10_rst5_seq)

  int unsigned clock_period = 10;
  int unsigned reset_cycles = 5;
  time         settle_time  = 300ns;

  function new(string name = "clk10_rst5_seq");
    super.new(name);
  endfunction

  task body();
    clock_and_reset_sequence configure_clock;

    configure_clock =
      clock_and_reset_sequence::type_id::create("configure_clock");
    configure_clock.clock_period = clock_period;
    configure_clock.reset_cycles = reset_cycles;
    configure_clock.run_clock    = 1'b1;
    configure_clock.start(m_sequencer);

    // Existing virtual sequences expect start() to return after reset recovery.
    #(settle_time);
  endtask

endclass : clk10_rst5_seq
