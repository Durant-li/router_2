class channel_env extends uvm_env;

  int unsigned channel_id;

  `uvm_component_utils_begin(channel_env)
    `uvm_field_int(channel_id, UVM_DEFAULT)
  `uvm_component_utils_end

  channel_rx_agent rx_agent;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_int::set(this, "rx_agent.*", "channel_id", channel_id);
    rx_agent = channel_rx_agent::type_id::create("rx_agent", this);
  endfunction

endclass : channel_env
