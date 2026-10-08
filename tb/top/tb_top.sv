/*-----------------------------------------------------------------
File name     : tb_top.sv
Developers    : Kathleen Meade, Brian Dickinson
Created       : 01/04/11
Description   : lab09_sbc UVM top module for acceleration
              : Instantiates UVM test environment
Notes         : From the Cadence "SystemVerilog Accelerated Verification with UVM" training
-------------------------------------------------------------------
Copyright Cadence Design Systems (c)2015
-----------------------------------------------------------------*/

module tb_top;

  // import the UVM library
  import uvm_pkg::*;

  // include the UVM macros
  `include "uvm_macros.svh"

  // import the YAPP UVC package
  import yapp_pkg::*;

  // import the HBUS UVC package
  import hbus_pkg::*;

  // import the Channel UVC package
  import channel_pkg::*;

  // import the clock and reset UVC package
  import clock_and_reset_pkg::*;

  // Verification-plan enums and semantic coverage transactions
  `include "router_vplan_types.sv"

  // include the multichannel sequencer
  `include "router_mcsequencer.sv"

  // Project-level YAPP patterns used by VPlan virtual sequences
  `include "router_vplan_project_seqs.sv"

  // Cross-interface, scenario-level virtual sequences
  `include "router_vplan_virtual_seqs.sv"

   // include the router analysis fifo scoreboard
  `include "router_fifo_scoreboard.sv"
  
   // include the router functional coverage collector
  `include "router_coverage.sv"
  
  // include router error checker
  `include "router_error_checker.sv"

   // environment
  `include "router_tb.sv"

  // One current, VPlan-oriented test library
  `include "router_base_test.sv"
  `include "router_vplan_tests.sv"
  
  initial begin
    yapp_vif_config::set(null,"*.tb.yapp.tx_agent.*","vif", hw_top.in0);
    hbus_vif_config::set(null,"*.tb.hbus.*","vif", hw_top.hif);
    channel_vif_config::set(null,"*.tb.chan0.*","vif", hw_top.ch0);
    channel_vif_config::set(null,"*.tb.chan1.*","vif", hw_top.ch1);
    channel_vif_config::set(null,"*.tb.chan2.*","vif", hw_top.ch2);
    clock_and_reset_vif_config::set(null, "*.tb.clock_and_reset*", "vif", hw_top.clk_rst_if);

    // Coverage observes reset context (idle versus an in-flight input packet)
    // and later associates it with the first successful post-reset route.
    yapp_vif_config::set(null,"*.tb.router_cov","vif", hw_top.in0);

	uvm_config_db#(virtual clock_and_reset_if)::set(null,"*.tb.router_cov","clk_rst_vif",hw_top.clk_rst_if);
	
	uvm_config_db#(virtual clock_and_reset_if)::set(null,"*.tb.router_sb","clk_rst_vif",hw_top.clk_rst_if);
	
	uvm_config_db#(virtual router_error_if)::set(null,"*.tb.error_checker","vif",hw_top.err_if);

    run_test();
  end

endmodule
