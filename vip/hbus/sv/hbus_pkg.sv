// Minimal HBUS VIP used by the YAPP Router project.
// Multi-master/slave and RAL-adapter course extensions are out of scope.
package hbus_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef uvm_config_db #(virtual hbus_if) hbus_vif_config;

  `include "hbus_transaction.sv"
  `include "hbus_master_sequencer.sv"
  `include "hbus_master_driver.sv"
  `include "hbus_monitor.sv"
  `include "hbus_master_agent.sv"
  `include "hbus_master_seqs.sv"
  `include "hbus_env.sv"

endpackage : hbus_pkg
