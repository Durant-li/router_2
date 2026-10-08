class clock_and_reset_driver
  extends uvm_driver #(clock_and_reset_sequence_item);

  `uvm_component_utils(clock_and_reset_driver)

  virtual clock_and_reset_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!clock_and_reset_vif_config::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", {"Clock/reset virtual interface is not set for ",
                            get_full_name()})
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);

      if (req.clock_period < 2)
        `uvm_fatal(get_type_name(), "clock_period must be at least 2")

      vif.configure(req.clock_period, req.reset_cycles, req.run_clock);
      seq_item_port.item_done();
    end
  endtask

endclass : clock_and_reset_driver
