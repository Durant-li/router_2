class channel_rx_sequencer extends uvm_sequencer #(channel_resp);

  `uvm_component_utils(channel_rx_sequencer)

  // Response sequences use the interface only to wait for data_vld.
  virtual channel_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!channel_vif_config::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", {"Channel virtual interface is not set for ",
                            get_full_name()})
  endfunction

endclass : channel_rx_sequencer
