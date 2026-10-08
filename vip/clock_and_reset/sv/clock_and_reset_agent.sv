class clock_and_reset_agent extends uvm_agent;

  `uvm_component_utils(clock_and_reset_agent)

  clock_and_reset_sequencer sequencer;
  clock_and_reset_driver    driver;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sequencer = clock_and_reset_sequencer::type_id::create("sequencer", this);
    driver    = clock_and_reset_driver::type_id::create("driver", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass : clock_and_reset_agent
