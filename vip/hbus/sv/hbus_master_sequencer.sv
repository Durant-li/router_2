class hbus_master_sequencer extends uvm_sequencer #(hbus_transaction);

  `uvm_component_utils(hbus_master_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : hbus_master_sequencer
