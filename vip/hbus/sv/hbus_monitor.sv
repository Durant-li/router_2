// Publishes every accepted HBUS access. Functional coverage is intentionally
// kept in router_coverage, where accesses can be crossed with packet behavior.
class hbus_monitor extends uvm_monitor;

  `uvm_component_utils(hbus_monitor)

  virtual hbus_if vif;
  uvm_analysis_port #(hbus_transaction) item_collected_port;

  int unsigned num_read_trans;
  int unsigned num_write_trans;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!hbus_vif_config::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", {"HBUS virtual interface is not set for ",
                            get_full_name()})
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      hbus_transaction observed;
      bit completed;

      observed = hbus_transaction::type_id::create("observed", this);
      vif.monitor_transfer(observed.haddr,
                           observed.hwr_rd,
                           observed.hdata,
                           completed);

      if (!completed)
        continue;

      if (observed.hwr_rd == HBUS_WRITE)
        num_write_trans++;
      else
        num_read_trans++;

      item_collected_port.write(observed);
      `uvm_info(get_type_name(),
                {"Observed HBUS access:\n", observed.sprint()},
                UVM_HIGH)
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(),
              $sformatf("HBUS monitor: %0d writes, %0d reads",
                        num_write_trans, num_read_trans),
              UVM_LOW)
  endfunction

endclass : hbus_monitor
