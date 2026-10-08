// Project-specific HBUS environment: exactly one master drives the Router DUT.
class hbus_env extends uvm_env;

  `uvm_component_utils(hbus_env)

  hbus_master_agent master;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    master = hbus_master_agent::type_id::create("master", this);
  endfunction

endclass : hbus_env
