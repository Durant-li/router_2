// Router project uses one always-active HBUS master plus one passive monitor.
class hbus_master_agent extends uvm_agent;

  `uvm_component_utils(hbus_master_agent)

  hbus_master_sequencer sequencer;
  hbus_master_driver    driver;
  hbus_monitor          monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    sequencer = hbus_master_sequencer::type_id::create("sequencer", this);
    driver    = hbus_master_driver::type_id::create("driver", this);
    monitor   = hbus_monitor::type_id::create("monitor", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass : hbus_master_agent
