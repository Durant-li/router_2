/*-----------------------------------------------------------------
File name     : yapp_tx_monitor.sv
Developers    : Kathleen Meade, Brian Dickinson
Created       : 01/04/11
Description   : YAPP UVC TX Monitor for acceleration
Notes         : From the Cadence "SystemVerilog Accelerated Verification with UVM" training
-------------------------------------------------------------------
Copyright Cadence Design Systems (c)2015
-----------------------------------------------------------------*/

//------------------------------------------------------------------------------
//
// CLASS: yapp_tx_monitor
//
//------------------------------------------------------------------------------

class yapp_tx_monitor extends uvm_monitor;

  // Collected Data handle
  yapp_packet pkt;

  // Count packets collected
  int num_pkt_col;

  // analysis port for lab09*
  uvm_analysis_port#(yapp_packet) item_collected_port;

  virtual interface yapp_if vif;

  // component macro
  `uvm_component_utils_begin(yapp_tx_monitor)
    `uvm_field_int(num_pkt_col, UVM_ALL_ON)
  `uvm_component_utils_end

  // component constructor - required syntax for UVM automation and utilities
  function new (string name, uvm_component parent);
    super.new(name, parent);
    item_collected_port = new("item_collected_port",this);
  endfunction : new

  function void connect_phase(uvm_phase phase);
    if (!yapp_vif_config::get(this, get_full_name(),"vif", vif))
      `uvm_error("NOVIF",{"virtual interface must be set for: ",get_full_name(),".vif"})
  endfunction: connect_phase

  // UVM run() phase
  task run_phase(uvm_phase phase);
    // Look for packets after reset
    @(posedge vif.reset)
    @(negedge vif.reset)
    `uvm_info(get_type_name(), "Detected Reset Done", UVM_MEDIUM)
    forever begin 
      bit packet_complete;
      bit transaction_started;

      // Create collected packet instance
      pkt = yapp_packet::type_id::create("pkt", this);
      packet_complete     = 0;
      transaction_started = 0;

      // Packet collection races reset.  If reset wins, discard this partial
      // transaction and restart cleanly after reset deassertion.
      fork : collect_or_reset
        begin
          fork
            begin
              vif.collect_packet(pkt.length, pkt.addr, pkt.payload, pkt.parity);
              packet_complete = 1;
            end
            begin
              @(posedge vif.monstart);
              transaction_started = 1;
              void'(begin_tr(pkt, "Monitor_YAPP_Packet"));
            end
          join
        end
        begin
          @(posedge vif.reset);
        end
      join_any
      disable collect_or_reset;

      if (!packet_complete) begin
        if (transaction_started)
          end_tr(pkt);
        `uvm_info(get_type_name(),
                  "Reset aborted partial YAPP monitor transaction",
                  UVM_LOW)
        if (vif.reset === 1'b1)
          @(negedge vif.reset);
        continue;
      end

      pkt.parity_type = (pkt.parity == pkt.calc_parity()) ? GOOD_PARITY : BAD_PARITY;
      // End transaction recording
      end_tr(pkt);
      `uvm_info(get_type_name(), $sformatf("Packet Collected :\n%s", pkt.sprint()), UVM_LOW)
      item_collected_port.write(pkt);
      num_pkt_col++;
    end
  endtask : run_phase

  // UVM report_phase
  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf("Report: YAPP Monitor Collected %0d Packets", num_pkt_col), UVM_LOW)
  endfunction : report_phase

endclass : yapp_tx_monitor
