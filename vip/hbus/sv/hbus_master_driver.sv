// Converts hbus_transaction items into the Router DUT's simple HBUS protocol.
class hbus_master_driver extends uvm_driver #(hbus_transaction);

  `uvm_component_utils(hbus_master_driver)

  virtual hbus_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!hbus_vif_config::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", {"HBUS virtual interface is not set for ",
                            get_full_name()})
  endfunction

  task run_phase(uvm_phase phase);
    vif.drive_idle();

    // Do not consume a default-sequence request during the pre-reset window.
    @(posedge vif.reset);
    @(negedge vif.reset);

    // Reset owns the bus whenever it is asserted.
    fork
      forever begin
        @(posedge vif.reset);
        vif.drive_idle();
      end

      forever begin
        seq_item_port.get_next_item(req);
        if (vif.reset === 1'b1)
          @(negedge vif.reset);
        vif.drive_transfer(req.haddr,
                           req.hwr_rd,
                           req.hdata,
                           req.wait_between_cycle);
        seq_item_port.item_done();
      end
    join
  endtask

endclass : hbus_master_driver
