//------------------------------------------------------------------------------
// Verification-plan-oriented router virtual sequences
//
// Tests configure scenario-level knobs on these classes.  The virtual
// sequences translate those knobs into HBUS accesses, YAPP traffic patterns,
// channel responses, and reset operations.
//------------------------------------------------------------------------------


class router_vplan_vseq_base extends uvm_sequence;

  `uvm_object_utils(router_vplan_vseq_base)
  `uvm_declare_p_sequencer(router_mcsequencer)

  function new(string name = "router_vplan_vseq_base");
    super.new(name);
  endfunction

  task wait_for_initial_reset();
    // The training clock/reset VIP has no completion analysis port.  Its
    // default reset sequence completes well before this project-level guard.
    #1000ns;
  endtask

  task hbus_write(bit [15:0] address,
                  bit [7:0]  data,
                  string     description = "");
    hbus_write_seq seq;

    seq = hbus_write_seq::type_id::create({"write_", description});
    seq.address = address;
    seq.data    = data;
    seq.start(p_sequencer.hbus_seqr);
  endtask

  task hbus_read_value(bit [15:0] address,
                       output bit [7:0] data,
                       input string description = "");
    hbus_read_seq seq;

    seq = hbus_read_seq::type_id::create({"read_", description});
    seq.address = address;
    seq.start(p_sequencer.hbus_seqr);
    data = seq.data;
  endtask

  task hbus_read_check(bit [15:0] address,
                       bit [7:0]  expected,
                       string     description = "");
    bit [7:0] actual;

    hbus_read_value(address, actual, description);
    if (actual !== expected)
      `uvm_error(get_type_name(),
                 $sformatf("%s readback mismatch: addr=0x%0h expected=0x%0h actual=0x%0h",
                           description, address, expected, actual))
  endtask

  task hbus_read_check_mask(bit [15:0] address,
                            bit [7:0]  expected,
                            bit [7:0]  mask,
                            string     description = "");
    bit [7:0] actual;

    hbus_read_value(address, actual, description);
    if ((actual & mask) !== (expected & mask))
      `uvm_error(get_type_name(),
                 $sformatf("%s masked readback mismatch: addr=0x%0h expected=0x%0h actual=0x%0h mask=0x%0h",
                           description, address, expected, actual, mask))
  endtask

  task send_yapp_packet(bit [1:0]          address,
                        bit [5:0]          length,
                        yapp_pkg::parity_t parity_type,
                        bit                allow_illegal_address = 0,
                        int unsigned       gap = 1);
    yapp_send_one_seq packet_seq;

    packet_seq = yapp_send_one_seq::type_id::create(
      $sformatf("packet_addr%0d_len%0d", address, length)
    );
    packet_seq.target_addr        = address;
    packet_seq.target_length      = length;
    packet_seq.target_parity      = parity_type;
    packet_seq.target_gap         = gap;
    packet_seq.payload_profile    = yapp_pkg::YAPP_PAYLOAD_INCREMENTING;
    packet_seq.allow_illegal_addr = allow_illegal_address;
    packet_seq.start(p_sequencer.yapp_seqr);
  endtask

  task apply_reset(int unsigned reset_cycles = 5);
    clk10_rst5_seq reset_seq;

    reset_seq = clk10_rst5_seq::type_id::create("reset_seq");
    reset_seq.reset_cycles = reset_cycles;
    reset_seq.start(p_sequencer.clk_rst_seqr);
  endtask

  function void configure_response(
    channel_rx_configurable_resp_seq response,
    router_pressure_mode_e           pressure_mode,
    int unsigned                     response_count
  );
    response.response_count = response_count;

    case (pressure_mode)
      ROUTER_PRESSURE_NONE: begin
        response.delay_min = 0;
        response.delay_max = 0;
      end

      ROUTER_PRESSURE_LIGHT: begin
        response.delay_min = 1;
        response.delay_max = 3;
      end

      ROUTER_PRESSURE_MODERATE: begin
        response.delay_min = 5;
        response.delay_max = 15;
      end

      default: begin
        response.delay_min = 18;
        response.delay_max = 25;
      end
    endcase
  endfunction

endclass : router_vplan_vseq_base


// Basic reset/configuration/readback and one packet to each legal channel.
class router_smoke_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_smoke_vseq)

  rand bit [5:0] packet_length;
  bit            check_default_registers = 1;

  constraint length_c {
    packet_length inside {[1:20]};
  }

  function new(string name = "router_smoke_vseq");
    super.new(name);
  endfunction

  virtual task body();
    router_address_pattern_seq         traffic;
    channel_rx_configurable_resp_seq   rsp0, rsp1, rsp2;

    wait_for_initial_reset();

    if (check_default_registers) begin
      hbus_read_check(16'h1000, 8'h3f, "ctrl_reg_reset");
      hbus_read_check(16'h1001, 8'h01, "en_reg_reset");
    end

    traffic = router_address_pattern_seq::type_id::create("traffic");
    traffic.packet_length      = packet_length;
    traffic.packets_per_address = 1;
    traffic.packet_gap         = 1;

    rsp0 = channel_rx_configurable_resp_seq::type_id::create("rsp0");
    rsp1 = channel_rx_configurable_resp_seq::type_id::create("rsp1");
    rsp2 = channel_rx_configurable_resp_seq::type_id::create("rsp2");
    configure_response(rsp0, ROUTER_PRESSURE_NONE, 1);
    configure_response(rsp1, ROUTER_PRESSURE_NONE, 1);
    configure_response(rsp2, ROUTER_PRESSURE_NONE, 1);

    fork
      rsp0.start(p_sequencer.channel_seqr[0]);
      rsp1.start(p_sequencer.channel_seqr[1]);
      rsp2.start(p_sequencer.channel_seqr[2]);
      traffic.start(p_sequencer.yapp_seqr);
    join
  endtask

endclass : router_smoke_vseq


// Address decode, same-channel bursts, and channel-to-channel transitions.
class router_routing_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_routing_vseq)

  bit [1:0] address_pattern[$];
  rand int unsigned packets_per_address;
  rand bit [5:0]    packet_length;
  router_pressure_mode_e pressure_mode = ROUTER_PRESSURE_NONE;

  constraint count_c {
    packets_per_address inside {[1:10]};
  }

  constraint length_c {
    packet_length inside {[1:63]};
  }

  function new(string name = "router_routing_vseq");
    super.new(name);
  endfunction

  virtual task body();
    router_address_pattern_seq       traffic;
    channel_rx_configurable_resp_seq rsp0, rsp1, rsp2;
    int unsigned channel_count[3];

    wait_for_initial_reset();

    channel_count[0] = 0;
    channel_count[1] = 0;
    channel_count[2] = 0;

    if (address_pattern.size() == 0) begin
      address_pattern.push_back(2'd0);
      address_pattern.push_back(2'd1);
      address_pattern.push_back(2'd2);
      address_pattern.push_back(2'd0);
    end

    foreach (address_pattern[i])
      if (address_pattern[i] < 3)
        channel_count[address_pattern[i]] += packets_per_address;

    traffic = router_address_pattern_seq::type_id::create("traffic");
    traffic.address_list        = address_pattern;
    traffic.packets_per_address = packets_per_address;
    traffic.packet_length       = packet_length;
    traffic.packet_gap          = 0;

    rsp0 = channel_rx_configurable_resp_seq::type_id::create("rsp0");
    rsp1 = channel_rx_configurable_resp_seq::type_id::create("rsp1");
    rsp2 = channel_rx_configurable_resp_seq::type_id::create("rsp2");

    if (channel_count[0] > 0) configure_response(rsp0, pressure_mode, channel_count[0]);
    if (channel_count[1] > 0) configure_response(rsp1, pressure_mode, channel_count[1]);
    if (channel_count[2] > 0) configure_response(rsp2, pressure_mode, channel_count[2]);

    fork
      begin if (channel_count[0] > 0) rsp0.start(p_sequencer.channel_seqr[0]); end
      begin if (channel_count[1] > 0) rsp1.start(p_sequencer.channel_seqr[1]); end
      begin if (channel_count[2] > 0) rsp2.start(p_sequencer.channel_seqr[2]); end
      traffic.start(p_sequencer.yapp_seqr);
    join
  endtask

endclass : router_routing_vseq


// Program max_packet_size=N and send N-1/N/N+1.
class router_length_control_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_length_control_vseq)

  rand int unsigned max_size;
  rand bit [1:0]    target_addr;
  bit               do_readback = 1;

  constraint max_c {
    max_size inside {[2:62]};
  }

  constraint target_c {
    target_addr inside {[0:2]};
  }

  function new(string name = "router_length_control_vseq");
    super.new(name);
  endfunction

  virtual task body();
    router_length_boundary_seq       traffic;
    channel_rx_configurable_resp_seq response;

    wait_for_initial_reset();

    hbus_write(16'h1000, max_size, "max_packet_size");
    hbus_write(16'h1001, 8'h01, "router_enable");

    if (do_readback)
      hbus_read_check(16'h1000, max_size, "max_packet_size");

    traffic = router_length_boundary_seq::type_id::create("traffic");
    traffic.boundary    = max_size;
    traffic.target_addr = target_addr;

    // N-1 and N are expected to be forwarded; N+1 is a drop case.
    response = channel_rx_configurable_resp_seq::type_id::create("response");
    configure_response(response, ROUTER_PRESSURE_NONE, 2);

    fork
      response.start(p_sequencer.channel_seqr[target_addr]);
      traffic.start(p_sequencer.yapp_seqr);
    join

    // N+1 is a drop case, so allow its monitor/scoreboard decision to be
    // consumed before changing the configuration epoch.
    #5000ns;
    hbus_write(16'h1000, 8'h3f, "restore_max_packet_size");
  endtask

endclass : router_length_control_vseq


// Configure the Router and generate one selected negative event.
class router_error_drop_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_error_drop_vseq)

  rand router_error_kind_e error_kind;
  rand bit [1:0]           target_addr;
  rand int unsigned        max_size;
  rand int unsigned        legal_length;

  constraint kind_c {
    error_kind inside {
      ROUTER_ERROR_BAD_PARITY,
      ROUTER_ERROR_ILLEGAL_ADDRESS,
      ROUTER_ERROR_OVERSIZED,
      ROUTER_ERROR_DISABLED
    };
  }

  constraint target_c {
    target_addr inside {[0:2]};
  }

  constraint size_c {
    max_size inside {[2:62]};
    legal_length inside {[1:20]};
  }

  function new(string name = "router_error_drop_vseq");
    super.new(name);
  endfunction

  virtual task body();
    router_error_event_seq          traffic;
    channel_rx_configurable_resp_seq response;

    wait_for_initial_reset();

    hbus_write(16'h1000, max_size, "error_test_max_size");
    hbus_write(16'h1001,
               (error_kind == ROUTER_ERROR_DISABLED) ? 8'h00 : 8'h01,
               "error_test_enable");

    traffic = router_error_event_seq::type_id::create("traffic");
    traffic.error_kind          = error_kind;
    traffic.target_addr         = target_addr;
    traffic.configured_max_size = max_size;
    traffic.legal_length        = legal_length;

    if (error_kind == ROUTER_ERROR_BAD_PARITY) begin
      response = channel_rx_configurable_resp_seq::type_id::create("response");
      configure_response(response, ROUTER_PRESSURE_NONE, 1);

      fork
        response.start(p_sequencer.channel_seqr[target_addr]);
        traffic.start(p_sequencer.yapp_seqr);
      join
    end
    else begin
      traffic.start(p_sequencer.yapp_seqr);
    end

    // Negative cases may have no output-side synchronization point.
    #5000ns;
    hbus_write(16'h1000, 8'h3f, "restore_max_packet_size");
    hbus_write(16'h1001, 8'h01, "restore_router_enable");
  endtask

endclass : router_error_drop_vseq


// Register reset values, representative writes, readback, and restore.
class router_register_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_register_vseq)

  rand bit [7:0] max_size_value;
  rand bit [7:0] enable_value;

  constraint values_c {
    max_size_value inside {[1:63]};
    enable_value inside {8'h00, 8'h01, 8'hf7};
  }

  function new(string name = "router_register_vseq");
    super.new(name);
  endfunction

  virtual task body();
    wait_for_initial_reset();

    hbus_read_check(16'h1000, 8'h3f, "ctrl_reg_reset");
    hbus_read_check(16'h1001, 8'h01, "en_reg_reset");

    hbus_write(16'h1000, max_size_value, "ctrl_reg_program");
    hbus_write(16'h1001, enable_value,   "en_reg_program");
    hbus_read_check(16'h1000, max_size_value, "ctrl_reg_readback");
    hbus_read_check(16'h1001, enable_value,   "en_reg_readback");

    hbus_write(16'h1000, 8'h3f, "restore_ctrl_reg");
    hbus_write(16'h1001, 8'h01, "restore_en_reg");
  endtask

endclass : router_register_vseq


// Counter readback and interrupt status/clear share one scenario-level class.
// The detailed flow is implemented here rather than hidden in legacy macros.
class router_counter_interrupt_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_counter_interrupt_vseq)

  bit check_interrupt_and_clear = 1;

  function new(string name = "router_counter_interrupt_vseq");
    super.new(name);
  endfunction

  task run_counter_readback();
    router_counter_stimulus_seq      traffic;
    channel_rx_configurable_resp_seq rsp0, rsp1, rsp2;

    traffic = router_counter_stimulus_seq::type_id::create("counter_traffic");
    rsp0 = channel_rx_configurable_resp_seq::type_id::create("rsp0");
    rsp1 = channel_rx_configurable_resp_seq::type_id::create("rsp1");
    rsp2 = channel_rx_configurable_resp_seq::type_id::create("rsp2");
    configure_response(rsp0, ROUTER_PRESSURE_NONE, 1);
    configure_response(rsp1, ROUTER_PRESSURE_NONE, 2);
    configure_response(rsp2, ROUTER_PRESSURE_NONE, 1);

    hbus_write(16'h1000, 8'd20, "counter_max_size");
    hbus_write(16'h1001, 8'hf7, "counter_enables");
    hbus_read_check(16'h1000, 8'd20, "counter_max_size");
    hbus_read_check(16'h1001, 8'hf7, "counter_enables");

    fork
      rsp0.start(p_sequencer.channel_seqr[0]);
      rsp1.start(p_sequencer.channel_seqr[1]);
      rsp2.start(p_sequencer.channel_seqr[2]);
      traffic.start(p_sequencer.yapp_seqr);
    join

    #5000ns;
    hbus_read_check(16'h1004, 8'd1, "parity_error_count");
    hbus_read_check(16'h1005, 8'd1, "oversized_count");
    hbus_read_check(16'h1006, 8'd1, "illegal_address_count");
    hbus_read_check(16'h1009, 8'd1, "channel0_count");
    hbus_read_check(16'h100a, 8'd2, "channel1_count");
    hbus_read_check(16'h100b, 8'd1, "channel2_count");
  endtask

  task run_interrupt_status_clear();
    channel_rx_configurable_resp_seq response;

    response = channel_rx_configurable_resp_seq::type_id::create("response");
    configure_response(response, ROUTER_PRESSURE_NONE, 1);

    hbus_write(16'h1000, 8'd20, "interrupt_max_size");
    hbus_write(16'h1001, 8'hf7, "router_and_counter_enables");
    hbus_write(16'h1002, 8'h07, "interrupt_enables");
    hbus_read_check_mask(16'h1002, 8'h07, 8'h07, "interrupt_enables");
    hbus_read_check_mask(16'h1003, 8'h00, 8'h07, "initial_interrupt_status");

    // Bad parity is forwarded, so coordinate one channel-1 response.
    fork
      response.start(p_sequencer.channel_seqr[1]);
      begin
        send_yapp_packet(2'd1, 6'd5, yapp_pkg::BAD_PARITY);
        #5000ns;
      end
    join
    hbus_read_check_mask(16'h1003, 8'h01, 8'h07,
                         "status_after_bad_parity");

    send_yapp_packet(2'd0, 6'd21, yapp_pkg::GOOD_PARITY);
    #5000ns;
    hbus_read_check_mask(16'h1003, 8'h03, 8'h07,
                         "status_after_oversized");

    send_yapp_packet(2'd3, 6'd5, yapp_pkg::GOOD_PARITY, 1'b1);
    #5000ns;
    hbus_read_check_mask(16'h1003, 8'h07, 8'h07,
                         "status_after_illegal_address");

    // Status bits are write-one-to-clear.
    hbus_write(16'h1003, 8'h07, "clear_interrupt_status");
    #1000ns;
    hbus_read_check_mask(16'h1003, 8'h00, 8'h07,
                         "status_after_clear");
    hbus_write(16'h1002, 8'h00, "restore_interrupt_enables");
  endtask

  virtual task body();
    wait_for_initial_reset();

    if (check_interrupt_and_clear)
      run_interrupt_status_clear();
    else
      run_counter_readback();

    hbus_write(16'h1000, 8'h3f, "restore_max_size");
    hbus_write(16'h1001, 8'h01, "restore_router_enable");
  endtask

endclass : router_counter_interrupt_vseq


// Prove that each enable bit independently gates its matching counter.
class router_counter_gating_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_counter_gating_vseq)

  function new(string name = "router_counter_gating_vseq");
    super.new(name);
  endfunction

  task check_one_counter(string               counter_name,
                         bit [15:0]           counter_address,
                         int unsigned         enable_bit,
                         bit [1:0]            packet_address,
                         bit [5:0]            packet_length,
                         yapp_pkg::parity_t   parity_type,
                         bit                  allow_illegal_address);
    bit [7:0] before_value;
    bit [7:0] after_disabled;
    bit [7:0] after_enabled;
    bit [7:0] disabled_enable_value;

    disabled_enable_value = 8'hf7 & ~(8'h01 << enable_bit);
    hbus_read_value(counter_address, before_value,
                    {counter_name, "_baseline"});

    hbus_write(16'h1001, disabled_enable_value,
               {counter_name, "_disabled"});
    send_yapp_packet(packet_address, packet_length, parity_type,
                     allow_illegal_address);
    #5000ns;
    hbus_read_value(counter_address, after_disabled,
                    {counter_name, "_after_disabled_event"});
    if (after_disabled !== before_value)
      `uvm_error(get_type_name(),
                 $sformatf("%s changed while disabled: before=%0d after=%0d",
                           counter_name, before_value, after_disabled))

    hbus_write(16'h1001, 8'hf7, {counter_name, "_enabled"});
    send_yapp_packet(packet_address, packet_length, parity_type,
                     allow_illegal_address);
    #5000ns;
    hbus_read_value(counter_address, after_enabled,
                    {counter_name, "_after_enabled_event"});
    if (after_enabled !== (before_value + 8'd1))
      `uvm_error(get_type_name(),
                 $sformatf("%s did not increment once: before=%0d after=%0d",
                           counter_name, before_value, after_enabled))
  endtask

  virtual task body();
    channel_rx_configurable_resp_seq rsp0, rsp1, rsp2;

    wait_for_initial_reset();
    hbus_write(16'h1000, 8'd20, "counter_gating_max_size");
    hbus_write(16'h1001, 8'hf7, "counter_gating_enables");

    rsp0 = channel_rx_configurable_resp_seq::type_id::create("rsp0");
    rsp1 = channel_rx_configurable_resp_seq::type_id::create("rsp1");
    rsp2 = channel_rx_configurable_resp_seq::type_id::create("rsp2");
    configure_response(rsp0, ROUTER_PRESSURE_NONE, 2);
    configure_response(rsp1, ROUTER_PRESSURE_NONE, 4);
    configure_response(rsp2, ROUTER_PRESSURE_NONE, 2);

    fork
      rsp0.start(p_sequencer.channel_seqr[0]);
      rsp1.start(p_sequencer.channel_seqr[1]);
      rsp2.start(p_sequencer.channel_seqr[2]);
      begin
        check_one_counter("parity_error", 16'h1004, 1, 2'd1, 6'd5,
                          yapp_pkg::BAD_PARITY, 1'b0);
        check_one_counter("oversized", 16'h1005, 2, 2'd0, 6'd21,
                          yapp_pkg::GOOD_PARITY, 1'b0);
        check_one_counter("illegal_address", 16'h1006, 7, 2'd3, 6'd5,
                          yapp_pkg::GOOD_PARITY, 1'b1);
        check_one_counter("channel0", 16'h1009, 4, 2'd0, 6'd5,
                          yapp_pkg::GOOD_PARITY, 1'b0);
        check_one_counter("channel1", 16'h100a, 5, 2'd1, 6'd5,
                          yapp_pkg::GOOD_PARITY, 1'b0);
        check_one_counter("channel2", 16'h100b, 6, 2'd2, 6'd5,
                          yapp_pkg::GOOD_PARITY, 1'b0);
      end
    join

    hbus_write(16'h1000, 8'h3f, "restore_max_size");
    hbus_write(16'h1001, 8'h01, "restore_router_enable");
  endtask

endclass : router_counter_gating_vseq


// Select ordinary reset recovery or reset while a packet is in flight.
class router_reset_recovery_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_reset_recovery_vseq)

  bit reset_during_packet = 0;

  function new(string name = "router_reset_recovery_vseq");
    super.new(name);
  endfunction

  virtual task body();
    router_address_pattern_seq       pre_reset_traffic;
    router_address_pattern_seq       recovery_traffic;
    channel_rx_configurable_resp_seq rsp0, rsp1, rsp2;

    wait_for_initial_reset();

    rsp0 = channel_rx_configurable_resp_seq::type_id::create("rsp0");
    rsp1 = channel_rx_configurable_resp_seq::type_id::create("rsp1");
    rsp2 = channel_rx_configurable_resp_seq::type_id::create("rsp2");

    recovery_traffic = router_address_pattern_seq::type_id::create(
      "recovery_traffic"
    );
    recovery_traffic.packet_length       = 6'd5;
    recovery_traffic.packets_per_address = 1;
    recovery_traffic.packet_gap          = 1;

    if (reset_during_packet) begin
      // The legal channel-2 packet may become visible before reset, so the
      // number of output handshakes across the reset boundary is deliberately
      // not assumed. Background responders remain active through recovery.
      configure_response(rsp0, ROUTER_PRESSURE_NONE, 0);
      configure_response(rsp1, ROUTER_PRESSURE_NONE, 0);
      configure_response(rsp2, ROUTER_PRESSURE_NONE, 0);
      fork
        rsp0.start(p_sequencer.channel_seqr[0]);
        rsp1.start(p_sequencer.channel_seqr[1]);
        rsp2.start(p_sequencer.channel_seqr[2]);
      join_none

      hbus_write(16'h1000, 8'h3f, "pre_reset_max_size");
      hbus_write(16'h1001, 8'h01, "pre_reset_enable");

      // Use a legal long packet so this proves that an accepted in-flight
      // transaction is cancelled by reset. The reset-aware monitor drops the
      // partial packet and the scoreboard advances its reset epoch.
      fork
        send_yapp_packet(2'd2, 6'd63, yapp_pkg::GOOD_PARITY, 1'b0, 0);
        begin
          #600ns;
          apply_reset();
        end
      join

      #2000ns;
      hbus_read_check(16'h1000, 8'h3f, "post_reset_max_size");
      hbus_read_check(16'h1001, 8'h01, "post_reset_enable");
      // Explicit writes synchronize the scoreboard configuration mirror.
      hbus_write(16'h1000, 8'h3f, "sync_post_reset_max_size");
      hbus_write(16'h1001, 8'h01, "sync_post_reset_enable");
      #1000ns;
      recovery_traffic.start(p_sequencer.yapp_seqr);
      #15000ns;
    end
    else begin
      pre_reset_traffic = router_address_pattern_seq::type_id::create(
        "pre_reset_traffic"
      );
      pre_reset_traffic.packet_length       = 6'd5;
      pre_reset_traffic.packets_per_address = 1;
      pre_reset_traffic.packet_gap          = 1;

      configure_response(rsp0, ROUTER_PRESSURE_NONE, 2);
      configure_response(rsp1, ROUTER_PRESSURE_NONE, 2);
      configure_response(rsp2, ROUTER_PRESSURE_NONE, 2);

      fork
        rsp0.start(p_sequencer.channel_seqr[0]);
        rsp1.start(p_sequencer.channel_seqr[1]);
        rsp2.start(p_sequencer.channel_seqr[2]);
        begin
          hbus_write(16'h1000, 8'd20, "pre_reset_max_size");
          hbus_write(16'h1001, 8'h01, "pre_reset_enable");
          pre_reset_traffic.start(p_sequencer.yapp_seqr);
          #10000ns;

          apply_reset();
          #1000ns;
          hbus_read_check(16'h1000, 8'h3f, "post_reset_max_size");
          hbus_read_check(16'h1001, 8'h01, "post_reset_enable");
          hbus_write(16'h1000, 8'h3f, "sync_post_reset_max_size");
          hbus_write(16'h1001, 8'h01, "sync_post_reset_enable");
          #1000ns;

          recovery_traffic.start(p_sequencer.yapp_seqr);
          #10000ns;
        end
      join
    end
  endtask

endclass : router_reset_recovery_vseq


// Make counters non-zero, apply reset, then verify every reset value.
class router_reset_registers_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_reset_registers_vseq)

  function new(string name = "router_reset_registers_vseq");
    super.new(name);
  endfunction

  virtual task body();
    router_counter_stimulus_seq      traffic;
    channel_rx_configurable_resp_seq rsp0, rsp1, rsp2;

    wait_for_initial_reset();
    hbus_write(16'h1000, 8'd20, "pre_reset_max_size");
    hbus_write(16'h1001, 8'hf7, "pre_reset_counter_enables");

    traffic = router_counter_stimulus_seq::type_id::create("traffic");
    rsp0 = channel_rx_configurable_resp_seq::type_id::create("rsp0");
    rsp1 = channel_rx_configurable_resp_seq::type_id::create("rsp1");
    rsp2 = channel_rx_configurable_resp_seq::type_id::create("rsp2");
    configure_response(rsp0, ROUTER_PRESSURE_NONE, 1);
    configure_response(rsp1, ROUTER_PRESSURE_NONE, 2);
    configure_response(rsp2, ROUTER_PRESSURE_NONE, 1);

    fork
      rsp0.start(p_sequencer.channel_seqr[0]);
      rsp1.start(p_sequencer.channel_seqr[1]);
      rsp2.start(p_sequencer.channel_seqr[2]);
      traffic.start(p_sequencer.yapp_seqr);
    join

    #10000ns;
    hbus_read_check(16'h1004, 8'd1, "pre_reset_parity_count");
    hbus_read_check(16'h1005, 8'd1, "pre_reset_oversized_count");
    hbus_read_check(16'h1006, 8'd1, "pre_reset_illegal_count");
    hbus_read_check(16'h1009, 8'd1, "pre_reset_channel0_count");
    hbus_read_check(16'h100a, 8'd2, "pre_reset_channel1_count");
    hbus_read_check(16'h100b, 8'd1, "pre_reset_channel2_count");

    apply_reset();
    #1000ns;
    hbus_read_check(16'h1000, 8'h3f, "post_reset_max_size");
    hbus_read_check(16'h1001, 8'h01, "post_reset_enable");
    hbus_read_check(16'h1004, 8'h00, "post_reset_parity_count");
    hbus_read_check(16'h1005, 8'h00, "post_reset_oversized_count");
    hbus_read_check(16'h1006, 8'h00, "post_reset_illegal_count");
    hbus_read_check(16'h1009, 8'h00, "post_reset_channel0_count");
    hbus_read_check(16'h100a, 8'h00, "post_reset_channel1_count");
    hbus_read_check(16'h100b, 8'h00, "post_reset_channel2_count");
  endtask

endclass : router_reset_registers_vseq


// HBUS memory decode plus the last-packet status path.
class router_memory_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_memory_vseq)

  function new(string name = "router_memory_vseq");
    super.new(name);
  endfunction

  virtual task body();
    bit [7:0]                         memory_data;
    channel_rx_configurable_resp_seq response;

    wait_for_initial_reset();
    hbus_write(16'h1000, 8'h3f, "memory_test_max_size");
    hbus_write(16'h1001, 8'h01, "memory_test_enable");

    hbus_write(16'h1100, 8'ha5, "rw_memory_0");
    hbus_write(16'h1101, 8'h5a, "rw_memory_1");
    hbus_read_check(16'h1100, 8'ha5, "rw_memory_0");
    hbus_read_check(16'h1101, 8'h5a, "rw_memory_1");

    response = channel_rx_configurable_resp_seq::type_id::create("response");
    configure_response(response, ROUTER_PRESSURE_NONE, 1);
    fork
      response.start(p_sequencer.channel_seqr[1]);
      send_yapp_packet(2'd1, 6'd3, yapp_pkg::GOOD_PARITY);
    join

    #10000ns;
    hbus_read_check(16'h100d, 8'h03, "last_packet_size");
    // These are smoke reads only: the training RTL documents limitations in
    // its last-packet memory/parity update behavior.
    hbus_read_value(16'h1010, memory_data, "last_packet_header");
    hbus_read_value(16'h1011, memory_data, "last_packet_payload0");
    hbus_read_value(16'h1012, memory_data, "last_packet_payload1");
    hbus_read_value(16'h1013, memory_data, "last_packet_payload2");
  endtask

endclass : router_memory_vseq


// Reach the disabled branch that actually exists in the training RTL.
class router_disabled_branch_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_disabled_branch_vseq)

  function new(string name = "router_disabled_branch_vseq");
    super.new(name);
  endfunction

  virtual task body();
    wait_for_initial_reset();
    hbus_write(16'h1000, 8'd20, "disabled_branch_max_size");
    hbus_write(16'h1001, 8'h00, "disabled_branch_enable");
    send_yapp_packet(2'd0, 6'd21, yapp_pkg::GOOD_PARITY);
    #10000ns;
    hbus_write(16'h1000, 8'h3f, "restore_max_size");
    hbus_write(16'h1001, 8'h01, "restore_router_enable");
  endtask

endclass : router_disabled_branch_vseq


// Expected-fail spec check: legal packets should be dropped at router_en=0.
// The three finite responders let any incorrect output drain to the monitors;
// on a conforming RTL they simply remain waiting until the test phase ends.
class router_disable_known_fail_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_disable_known_fail_vseq)

  function new(string name = "router_disable_known_fail_vseq");
    super.new(name);
  endfunction

  virtual task body();
    router_address_pattern_seq       traffic;
    channel_rx_configurable_resp_seq rsp0, rsp1, rsp2;

    wait_for_initial_reset();
    hbus_write(16'h1000, 8'h3f, "disable_test_max_size");
    hbus_write(16'h1001, 8'h00, "disable_router");

    traffic = router_address_pattern_seq::type_id::create("traffic");
    traffic.packet_length       = 6'd5;
    traffic.packets_per_address = 1;
    traffic.packet_gap          = 1;
    rsp0 = channel_rx_configurable_resp_seq::type_id::create("rsp0");
    rsp1 = channel_rx_configurable_resp_seq::type_id::create("rsp1");
    rsp2 = channel_rx_configurable_resp_seq::type_id::create("rsp2");
    configure_response(rsp0, ROUTER_PRESSURE_NONE, 1);
    configure_response(rsp1, ROUTER_PRESSURE_NONE, 1);
    configure_response(rsp2, ROUTER_PRESSURE_NONE, 1);

    fork
      rsp0.start(p_sequencer.channel_seqr[0]);
      rsp1.start(p_sequencer.channel_seqr[1]);
      rsp2.start(p_sequencer.channel_seqr[2]);
    join_none

    traffic.start(p_sequencer.yapp_seqr);
    #10000ns;
    hbus_write(16'h1001, 8'h01, "restore_router_enable");
  endtask

endclass : router_disable_known_fail_vseq


// Coordinate one traffic profile with one observed channel-pressure profile.
class router_backpressure_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_backpressure_vseq)

  rand bit [1:0]                target_channel;
  rand router_pressure_mode_e   pressure_mode;
  rand router_traffic_profile_e traffic_profile;
  rand int unsigned             packet_count;
  bit                           length_range_override = 0;
  int unsigned                  min_packet_length = 1;
  int unsigned                  max_packet_length = 63;

  constraint channel_c {
    target_channel inside {[0:2]};
  }

  constraint pressure_c {
    pressure_mode inside {
      ROUTER_PRESSURE_LIGHT,
      ROUTER_PRESSURE_MODERATE,
      ROUTER_PRESSURE_HEAVY
    };
  }

  constraint traffic_c {
    traffic_profile inside {
      ROUTER_TRAFFIC_BACK_TO_BACK,
      ROUTER_TRAFFIC_LONG_PACKET,
      ROUTER_TRAFFIC_SAME_CHANNEL
    };
  }

  constraint count_c {
    packet_count inside {[1:50]};
  }

  function new(string name = "router_backpressure_vseq");
    super.new(name);
  endfunction

  virtual task body();
    router_traffic_profile_seq        traffic;
    channel_rx_configurable_resp_seq response;

    wait_for_initial_reset();

    traffic = router_traffic_profile_seq::type_id::create("traffic");
    traffic.profile            = traffic_profile;
    traffic.packet_count       = packet_count;
    traffic.target_addr        = target_channel;
    traffic.bad_parity_percent = 0;
    // Retain the selected gap/length profile but force one known output so
    // every response is paired deterministically with one input packet.
    traffic.force_target_addr  = 1;
    traffic.length_range_override = length_range_override;
    traffic.override_min_length   = min_packet_length;
    traffic.override_max_length   = max_packet_length;

    response = channel_rx_configurable_resp_seq::type_id::create("response");
    configure_response(response, pressure_mode, packet_count);

    fork
      response.start(p_sequencer.channel_seqr[target_channel]);
      traffic.start(p_sequencer.yapp_seqr);
    join
  endtask

endclass : router_backpressure_vseq


// Constrained-random system scenario.  Configuration is changed only between
// traffic rounds so every input packet has an unambiguous configuration epoch.
class router_random_system_vseq extends router_vplan_vseq_base;

  `uvm_object_utils(router_random_system_vseq)

  rand int unsigned rounds;
  rand int unsigned packets_per_round;
  rand bit [7:0]    max_size;
  rand bit [1:0]    target_channel;
  rand router_pressure_mode_e pressure_mode;

  constraint random_c {
    rounds inside {[2:8]};
    packets_per_round inside {[5:30]};
    max_size inside {8'd20, 8'd40, 8'd63};
    target_channel inside {[0:2]};
    pressure_mode inside {
      ROUTER_PRESSURE_NONE,
      ROUTER_PRESSURE_LIGHT,
      ROUTER_PRESSURE_MODERATE
    };
  }

  function new(string name = "router_random_system_vseq");
    super.new(name);
  endfunction

  virtual task body();
    wait_for_initial_reset();

    repeat (rounds) begin
      router_traffic_profile_seq        traffic;
      channel_rx_configurable_resp_seq response;

      // Re-randomize round-level knobs at packet boundaries.
      if (!std::randomize(max_size, target_channel, pressure_mode) with {
        max_size inside {8'd20, 8'd40, 8'd63};
        target_channel inside {[0:2]};
        pressure_mode inside {
          ROUTER_PRESSURE_NONE,
          ROUTER_PRESSURE_LIGHT,
          ROUTER_PRESSURE_MODERATE
        };
      })
        `uvm_error(get_type_name(), "Unable to randomize system round")

      hbus_write(16'h1000, max_size, "random_round_max_size");
      hbus_write(16'h1001, 8'h01,    "random_round_enable");

      traffic = router_traffic_profile_seq::type_id::create("traffic");
      traffic.profile            = ROUTER_TRAFFIC_NORMAL_RANDOM;
      traffic.packet_count       = packets_per_round;
      traffic.target_addr        = target_channel;
      traffic.bad_parity_percent = 5;
      traffic.force_target_addr  = 1;
      traffic.length_range_override = 1;
      traffic.override_min_length   = 1;
      traffic.override_max_length   = max_size;

      response = channel_rx_configurable_resp_seq::type_id::create("response");
      configure_response(response, pressure_mode, packets_per_round);

      fork
        response.start(p_sequencer.channel_seqr[target_channel]);
        traffic.start(p_sequencer.yapp_seqr);
      join
    end

    hbus_write(16'h1000, 8'h3f, "restore_max_packet_size");
    hbus_write(16'h1001, 8'h01, "restore_router_enable");
  endtask

endclass : router_random_system_vseq
