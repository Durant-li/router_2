class channel_rx_driver extends uvm_driver #(channel_resp);

  `uvm_component_utils(channel_rx_driver)

  virtual channel_if vif;
  int unsigned num_responses;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!channel_vif_config::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", {"Channel virtual interface is not set for ",
                            get_full_name()})
  endfunction

  task run_phase(uvm_phase phase);
    vif.suspend <= 1'b1;

    // Keep the receiver stalled until the initial reset has completed.
    @(posedge vif.reset);
    @(negedge vif.reset);

    forever begin
      seq_item_port.get_next_item(rsp);
      if (vif.reset === 1'b1)
        @(negedge vif.reset);
      vif.drive_response(rsp.resp_delay);
      seq_item_port.item_done();
      num_responses++;
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(),
              $sformatf("Channel RX driver sent %0d responses", num_responses),
              UVM_LOW)
  endfunction

endclass : channel_rx_driver
