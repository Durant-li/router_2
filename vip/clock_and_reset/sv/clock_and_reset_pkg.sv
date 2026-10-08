// Minimal clock/reset VIP for the Router project.
// The course-only clock-count queue and unused config object are out of scope.
package clock_and_reset_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef uvm_config_db #(virtual clock_and_reset_if)
    clock_and_reset_vif_config;

  `include "clock_and_reset_sequence_item.sv"
  `include "clock_and_reset_sequencer.sv"
  `include "clock_and_reset_driver.sv"
  `include "clock_and_reset_agent.sv"
  `include "clock_and_reset_env.sv"
  `include "clock_and_reset_seq.sv"

endpackage : clock_and_reset_pkg
