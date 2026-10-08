//------------------------------------------------------------------------------
//
// CLASS: router_error_checker
// Checks DUT error output behavior for bad parity packets.
//
// Current check policy:
//   - Count bad-parity packets observed by YAPP input monitor
//   - Count DUT error pulses
//   - At check_phase, expected error count should equal actual error pulse count
//
//------------------------------------------------------------------------------

class router_error_checker extends uvm_component;

  `uvm_component_utils(router_error_checker)

  // YAPP packet stream from input monitor
  uvm_tlm_analysis_fifo #(yapp_packet) yapp_fifo;
  
  uvm_tlm_analysis_fifo #(hbus_transaction) hbus_fifo;

  // Virtual interface for DUT error signal
  virtual router_error_if vif;

  int expected_error_count;
  int actual_error_count;
  
  bit check_enable = 1;
  
   // Router registers
   bit [7:0] max_pktsize_reg = 8'h3F;
   bit 		 router_enable_reg = 1'b1;


  function new(string name, uvm_component parent);
    super.new(name, parent);
    yapp_fifo = new("yapp_fifo", this);
	
	hbus_fifo = new("hbus_fifo", this);
	 
    expected_error_count = 0;
    actual_error_count   = 0;
  endfunction : new


  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
	
	void'(uvm_config_int::get(this,"","check_enable",check_enable));
	
    if (!uvm_config_db#(virtual router_error_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal(get_type_name(), "Failed to get virtual router_error_if")
    end
  endfunction : build_phase
  
  
  task collect_hbus_config();

  hbus_transaction hb;

  forever begin
    hbus_fifo.get(hb);

    if (hb.hwr_rd == hbus_pkg::HBUS_WRITE) begin
      case (hb.haddr)

        'h1000: begin
          max_pktsize_reg = hb.hdata;
          `uvm_info(get_type_name(),
                    $sformatf("Update current_max_pkt = %0d", max_pktsize_reg),
                    UVM_LOW)
        end

        'h1001: begin
          router_enable_reg = hb.hdata[0];
          `uvm_info(get_type_name(),
                    $sformatf("Update router_enable = %0d", router_enable_reg),
                    UVM_LOW)
        end

      endcase
    end
  end

endtask : collect_hbus_config


  task run_phase(uvm_phase phase);

    fork
      collect_expected_errors();
      monitor_actual_error_signal();
	  collect_hbus_config();
    join

  endtask : run_phase


  // Count expected errors based on bad-parity YAPP input packets
  task collect_expected_errors();

    yapp_packet pkt;

    forever begin
      yapp_fifo.get(pkt);
	  
	  
	  if (!check_enable) begin
      `uvm_info(get_type_name(),
                "Error checker disabled: ignoring YAPP packet",
                UVM_HIGH)
      continue;
    end

	if (pkt.parity_type == yapp_pkg::BAD_PARITY) begin

		if ((pkt.addr inside {[0:2]}) &&   (pkt.length <= max_pktsize_reg) &&router_enable_reg) begin

			expected_error_count++;

			`uvm_info(get_type_name(),
              $sformatf("Expected error event from legal bad parity packet: addr=%0d len=%0d max=%0d enable=%0d expected_error_count=%0d",
                        pkt.addr, pkt.length, max_pktsize_reg, router_enable_reg, expected_error_count),
              UVM_LOW)

	end
	else begin

			`uvm_info(get_type_name(),
              $sformatf("Ignore bad parity packet: addr=%0d len=%0d max=%0d enable=%0d",
                        pkt.addr, pkt.length, max_pktsize_reg, router_enable_reg),
              UVM_LOW)

  end
  end

end

  endtask : collect_expected_errors


  // Count actual DUT error pulses
  task monitor_actual_error_signal();

    forever begin
      @(posedge vif.error);

      // Ignore reset-time activity
      if (!vif.reset) begin
        actual_error_count++;

        `uvm_info(get_type_name(),
                  $sformatf("Observed DUT error pulse: actual_error_count=%0d",
                            actual_error_count),
                  UVM_LOW)
      end
    end

  endtask : monitor_actual_error_signal


  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
	
	if (!check_enable) begin
		`uvm_info(get_type_name(),
              "Error checker disabled for this test",
              UVM_LOW)
      return;
    end

    if (actual_error_count !== expected_error_count) begin
      `uvm_error(get_type_name(),
                 $sformatf("Bad parity error count mismatch: expected=%0d actual=%0d",
                           expected_error_count, actual_error_count))
    end
    else begin
      `uvm_info(get_type_name(),
                $sformatf("Bad parity error check PASS: expected=%0d actual=%0d",
                          expected_error_count, actual_error_count),
                UVM_LOW)
    end

  endfunction : check_phase


  function void report_phase(uvm_phase phase);
    super.report_phase(phase);

    `uvm_info(get_type_name(),
              $sformatf("Error Checker Report: expected_error_count=%0d actual_error_count=%0d",
                        expected_error_count, actual_error_count),
              UVM_LOW)

  endfunction : report_phase

endclass : router_error_checker