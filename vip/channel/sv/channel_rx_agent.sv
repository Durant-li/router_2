// Each Router output needs one active response driver and one monitor.
class channel_rx_agent extends uvm_agent;

  `uvm_component_utils(channel_rx_agent)

  channel_rx_sequencer sequencer;
  channel_rx_driver    driver;
  channel_rx_monitor   monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sequencer = channel_rx_sequencer::type_id::create("sequencer", this);
    driver    = channel_rx_driver::type_id::create("driver", this);
    monitor   = channel_rx_monitor::type_id::create("monitor", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass : channel_rx_agent
