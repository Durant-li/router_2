/*-----------------------------------------------------------------
File name     : router_tb.sv
Developers    : Kathleen Meade, Brian Dickinson
Created       : 01/04/11
Description   : lab09_sbd router testbench for analysis fifo scoreboard
Notes         : From the Cadence "SystemVerilog Accelerated Verification with UVM" training
-------------------------------------------------------------------
Copyright Cadence Design Systems (c)2015
-----------------------------------------------------------------*/

//------------------------------------------------------------------------------
//
// CLASS: router_tb
//
//------------------------------------------------------------------------------

class router_tb extends uvm_env;

  // component macro
  `uvm_component_utils(router_tb)

  // clock and reset UVC
  clock_and_reset_env clock_and_reset;

  // yapp environment
  yapp_env yapp;

  //Channel environmnent UVCs
  channel_env chan0;
  channel_env chan1;
  channel_env chan2;

  // HBUS UVC
  hbus_env hbus;

  // Virtual Sequencer
  router_mcsequencer mcsequencer;

  // Router Scoreboard
  router_fifo_scoreboard router_sb;
  
  // Router Functional Coverage
  router_coverage router_cov;
  
  // Router Error Checker
  router_error_checker error_checker;

  // Constructor - required syntax for UVM automation and utilities
  function new (string name, uvm_component parent=null);
    super.new(name, parent);
  endfunction : new

  // UVM build_phase
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // clock and reset UVC
    clock_and_reset = clock_and_reset_env::type_id::create("clock_and_reset", this);

    // YAPP UVC
    yapp = yapp_env::type_id::create("yapp", this);

    // Channel UVC - RX ONLY
    uvm_config_int::set(this, "chan0", "channel_id", 0);
    uvm_config_int::set(this, "chan1", "channel_id", 1);
    uvm_config_int::set(this, "chan2", "channel_id", 2);
    chan0 = channel_env::type_id::create("chan0", this);
    chan1 = channel_env::type_id::create("chan1", this);
    chan2 = channel_env::type_id::create("chan2", this);

    // Router-specific HBUS VIP contains exactly one master.
    hbus = hbus_env::type_id::create("hbus", this);

   // virtual sequencer
   mcsequencer = router_mcsequencer::type_id::create("mcsequencer", this);

  // router scoreboard
  router_sb = router_fifo_scoreboard::type_id::create("router_sb", this);
  
  // router coverage
  router_cov = router_coverage::type_id::create("router_cov", this);
  
  // router error checker
  error_checker = router_error_checker::type_id::create("error_checker", this);

  endfunction : build_phase

  // UVM connect_phase
  function void connect_phase(uvm_phase phase);

    // Virtual Sequencer Connections
    mcsequencer.hbus_seqr = hbus.master.sequencer;
    mcsequencer.yapp_seqr = yapp.tx_agent.sequencer;
    mcsequencer.clk_rst_seqr = clock_and_reset.agent.sequencer;
    mcsequencer.channel_seqr[0] = chan0.rx_agent.sequencer;
    mcsequencer.channel_seqr[1] = chan1.rx_agent.sequencer;
    mcsequencer.channel_seqr[2] = chan2.rx_agent.sequencer;

    // Connect the TLM ports from the YAPP and Channel UVCs to the scoreboard
    yapp.tx_agent.monitor.item_collected_port.connect(router_sb.yapp_fifo.analysis_export);
    chan0.rx_agent.monitor.item_collected_port.connect(router_sb.chan0_fifo.analysis_export);
    chan1.rx_agent.monitor.item_collected_port.connect(router_sb.chan1_fifo.analysis_export);
    chan2.rx_agent.monitor.item_collected_port.connect(router_sb.chan2_fifo.analysis_export);
    hbus.master.monitor.item_collected_port.connect(router_sb.hbus_fifo.analysis_export);
	
	// Connect monitor analysis ports to functional coverage collector
	yapp.tx_agent.monitor.item_collected_port.connect(router_cov.yapp_cov_fifo.analysis_export);
	chan0.rx_agent.monitor.item_collected_port.connect(router_cov.chan0_cov_fifo.analysis_export);
	chan1.rx_agent.monitor.item_collected_port.connect(router_cov.chan1_cov_fifo.analysis_export);
	chan2.rx_agent.monitor.item_collected_port.connect(router_cov.chan2_cov_fifo.analysis_export);
	hbus.master.monitor.item_collected_port.connect(router_cov.hbus_cov_fifo.analysis_export);

    // The scoreboard publishes events only after configuration and/or
    // input-output transactions have been associated.  These are the source
    // for verification-plan feature coverage.
    router_sb.decision_cov_port.connect(router_cov.decision_cov_fifo.analysis_export);
    router_sb.route_cov_port.connect(router_cov.route_cov_fifo.analysis_export);
	
	// Connect YAPP input monitor to error checker
    yapp.tx_agent.monitor.item_collected_port.connect(error_checker.yapp_fifo.analysis_export);
	hbus.master.monitor.item_collected_port.connect(error_checker.hbus_fifo.analysis_export);
	
	
  endfunction : connect_phase

endclass : router_tb
