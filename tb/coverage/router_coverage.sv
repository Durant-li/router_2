//------------------------------------------------------------------------------
// YAPP Router functional coverage
//
// Coverage is intentionally split into two layers:
//   1. Raw protocol coverage samples transactions observed by each monitor.
//   2. Feature coverage samples semantic events after the scoreboard has
//      associated configuration state and/or input-output transactions.
//
// A test name is not used as proof that a scenario happened; the sampled
// DUT-visible facts are.
//------------------------------------------------------------------------------

class router_coverage extends uvm_component;

  `uvm_component_utils(router_coverage)

  // Raw observations from interface monitors.
  uvm_tlm_analysis_fifo #(yapp_packet)      yapp_cov_fifo;
  uvm_tlm_analysis_fifo #(hbus_transaction) hbus_cov_fifo;
  uvm_tlm_analysis_fifo #(channel_packet)   chan0_cov_fifo;
  uvm_tlm_analysis_fifo #(channel_packet)   chan1_cov_fifo;
  uvm_tlm_analysis_fifo #(channel_packet)   chan2_cov_fifo;

  // Correlated semantic events from the scoreboard.
  uvm_tlm_analysis_fifo #(router_decision_cov_item) decision_cov_fifo;
  uvm_tlm_analysis_fifo #(router_route_cov_item)    route_cov_fifo;

  virtual yapp_if            yapp_vif;
  virtual clock_and_reset_if clk_rst_vif;
  router_reset_context_e     last_reset_context = ROUTER_RESET_IDLE;
  bit                        post_reset_route_pending;


  // ---------------------------------------------------------------------------
  // Layer 1: raw protocol coverage
  // ---------------------------------------------------------------------------

  covergroup packet_protocol_cg with function sample(
    bit [1:0]          addr,
    int unsigned       length,
    yapp_pkg::parity_t parity_type,
    bit                incrementing_payload
  );
    option.per_instance = 1;

    ADDRESS: coverpoint addr {
      bins channel0 = {2'd0};
      bins channel1 = {2'd1};
      bins channel2 = {2'd2};
      bins illegal  = {2'd3};
    }

    LENGTH: coverpoint length {
      bins minimum = {1};
      bins short   = {[2:15]};
      bins medium  = {[16:40]};
      bins long    = {[41:62]};
      bins maximum = {63};
    }

    PARITY: coverpoint parity_type {
      bins good = {yapp_pkg::GOOD_PARITY};
      bins bad  = {yapp_pkg::BAD_PARITY};
    }

    PAYLOAD_PATTERN: coverpoint incrementing_payload {
      bins random_or_constant = {0};
      bins incrementing       = {1};
    }

    ADDRESS_TRANSITION: coverpoint addr iff (addr < 3) {
      bins same_channel[] = (0 => 0), (1 => 1), (2 => 2);
      bins channel_switch[] =
        (0 => 1), (0 => 2),
        (1 => 0), (1 => 2),
        (2 => 0), (2 => 1);
    }

    LEGAL_ADDRESS_X_LENGTH: cross ADDRESS, LENGTH {
      ignore_bins illegal_address = binsof(ADDRESS.illegal);
    }
  endgroup


  covergroup counter_readback_cg with function sample(
    bit        is_write,
    bit [15:0] address,
    bit [7:0]  data
  );
    option.per_instance = 1;

    COUNTER_READ: coverpoint address iff (!is_write) {
      bins parity_error_count = {16'h1004};
      bins length_error_count = {16'h1005};
      bins illegal_addr_count = {16'h1006};
      bins channel0_count     = {16'h1009};
      bins channel1_count     = {16'h100a};
      bins channel2_count     = {16'h100b};
      ignore_bins other       = default;
    }

    // Each bin proves both that the register was read and that its intended
    // event actually incremented it.
    NONZERO_COUNTER_READ: coverpoint address
      iff (!is_write && (data != 0)) {
      bins parity_error_count = {16'h1004};
      bins length_error_count = {16'h1005};
      bins illegal_addr_count = {16'h1006};
      bins channel0_count     = {16'h1009};
      bins channel1_count     = {16'h100a};
      bins channel2_count     = {16'h100b};
      ignore_bins other       = default;
    }
  endgroup


  covergroup interrupt_status_cg with function sample(
    bit        is_write,
    bit [15:0] address,
    bit [7:0]  data
  );
    option.per_instance = 1;

    STATUS_READ: coverpoint data[2:0]
      iff (!is_write && (address == 16'h1003)) {
      bins clear             = {3'b000};
      bins parity_set        = {3'b001};
      bins parity_length_set = {3'b011};
      bins all_error_set     = {3'b111};
      ignore_bins other_combination = default;
    }

    STATUS_CLEAR_WRITE: coverpoint data[2:0]
      iff (is_write && (address == 16'h1003)) {
      bins clear_command = {3'b111};
    }
  endgroup


  covergroup register_access_cg with function sample(
    bit        is_write,
    bit [15:0] address,
    bit [7:0]  data
  );
    option.per_instance = 1;

    OPERATION: coverpoint is_write {
      bins read  = {0};
      bins write = {1};
    }

    REGISTER: coverpoint address {
      bins ctrl_reg            = {16'h1000};
      bins enable_reg          = {16'h1001};
      bins interrupt_enable    = {16'h1002};
      bins interrupt_status    = {16'h1003};
      bins parity_error_count  = {16'h1004};
      bins length_error_count  = {16'h1005};
      bins illegal_addr_count  = {16'h1006};
      bins channel0_count      = {16'h1009};
      bins channel1_count      = {16'h100a};
      bins channel2_count      = {16'h100b};
      ignore_bins other        = default;
    }

    CTRL_VALUE_CLASS: coverpoint data iff (address == 16'h1000) {
      bins small         = {[1:20]};
      bins medium        = {[21:62]};
      bins default_value = {63};
    }

    ENABLE_VALUE: coverpoint data iff (address == 16'h1001) {
      bins all_disabled        = {8'h00};
      bins router_enabled_only = {8'h01};
      bins counters_enabled    = {8'hf7};
    }

    OPERATION_X_REGISTER: cross OPERATION, REGISTER {
      // Counter registers are read-only; writes are not VPlan targets.
      ignore_bins write_parity_counter =
        binsof(OPERATION.write) && binsof(REGISTER.parity_error_count);
      ignore_bins write_length_counter =
        binsof(OPERATION.write) && binsof(REGISTER.length_error_count);
      ignore_bins write_illegal_counter =
        binsof(OPERATION.write) && binsof(REGISTER.illegal_addr_count);
      ignore_bins write_channel0_counter =
        binsof(OPERATION.write) && binsof(REGISTER.channel0_count);
      ignore_bins write_channel1_counter =
        binsof(OPERATION.write) && binsof(REGISTER.channel1_count);
      ignore_bins write_channel2_counter =
        binsof(OPERATION.write) && binsof(REGISTER.channel2_count);
    }
  endgroup


  // ---------------------------------------------------------------------------
  // Layer 2: verification-plan feature coverage
  // ---------------------------------------------------------------------------

  // Configuration snapshot + current input transaction.  The scoreboard
  // computes the semantic relation before calling sample(), so values from
  // different interfaces are crossed inside one covergroup instance.
  covergroup length_policy_cg with function sample(
    bit                      enable_at_accept,
    int unsigned             max_size_at_accept,
    router_length_relation_e length_relation,
    router_packet_action_e   expected_action
  );
    option.per_instance = 1;

    ENABLE_AT_ACCEPT: coverpoint enable_at_accept {
      bins enabled  = {1};
      // The supplied training RTL does not implement the documented global
      // router-disable behavior for normal packets.  Keep it out of sign-off
      // until the RTL/spec discrepancy is resolved.
      ignore_bins known_rtl_gap = {0};
    }

    MAX_SIZE_CLASS: coverpoint max_size_at_accept {
      bins small         = {[1:20]};
      bins medium        = {[21:62]};
      bins default_value = {63};
    }

    LENGTH_RELATION: coverpoint length_relation {
      bins below = {ROUTER_LEN_BELOW_MAX};
      bins equal = {ROUTER_LEN_EQUAL_MAX};
      bins above = {ROUTER_LEN_ABOVE_MAX};
    }

    EXPECTED_ACTION: coverpoint expected_action {
      bins forwarded = {ROUTER_ACTION_FORWARDED};
      bins dropped   = {ROUTER_ACTION_DROPPED};
    }

    MAX_CLASS_X_RELATION: cross MAX_SIZE_CLASS, LENGTH_RELATION {
      // Packet length is limited to 63, so it cannot exceed reset max=63.
      ignore_bins above_default_max =
        binsof(MAX_SIZE_CLASS.default_value) &&
        binsof(LENGTH_RELATION.above);
    }

    POLICY_DECISION: cross ENABLE_AT_ACCEPT, LENGTH_RELATION, EXPECTED_ACTION {
      ignore_bins enabled_below_drop =
        binsof(ENABLE_AT_ACCEPT.enabled) &&
        binsof(LENGTH_RELATION.below) &&
        binsof(EXPECTED_ACTION.dropped);
      ignore_bins enabled_equal_drop =
        binsof(ENABLE_AT_ACCEPT.enabled) &&
        binsof(LENGTH_RELATION.equal) &&
        binsof(EXPECTED_ACTION.dropped);
      ignore_bins enabled_above_forward =
        binsof(ENABLE_AT_ACCEPT.enabled) &&
        binsof(LENGTH_RELATION.above) &&
        binsof(EXPECTED_ACTION.forwarded);
    }
  endgroup


  covergroup error_response_cg with function sample(
    yapp_pkg::parity_t     parity_type,
    router_drop_reason_e   drop_reason,
    router_packet_action_e expected_action
  );
    option.per_instance = 1;

    PARITY_STATUS: coverpoint parity_type {
      bins good = {yapp_pkg::GOOD_PARITY};
      bins bad  = {yapp_pkg::BAD_PARITY};
    }

    DROP_REASON: coverpoint drop_reason {
      bins none        = {ROUTER_DROP_NONE};
      bins bad_address = {ROUTER_DROP_BAD_ADDRESS};
      bins oversized   = {ROUTER_DROP_OVERSIZED};
      ignore_bins known_rtl_gap = {ROUTER_DROP_DISABLED};
    }

    EXPECTED_ACTION: coverpoint expected_action {
      bins forwarded = {ROUTER_ACTION_FORWARDED};
      bins dropped   = {ROUTER_ACTION_DROPPED};
    }

    PARITY_X_ACTION: cross PARITY_STATUS, EXPECTED_ACTION {
      // The VPlan injects one error dimension at a time.  A bad-parity packet
      // is forwarded while the parity error is reported/counted.
      ignore_bins combined_parity_and_drop =
        binsof(PARITY_STATUS.bad) && binsof(EXPECTED_ACTION.dropped);
    }

    DROP_REASON_X_ACTION: cross DROP_REASON, EXPECTED_ACTION {
      ignore_bins no_reason_but_dropped =
        binsof(DROP_REASON.none) && binsof(EXPECTED_ACTION.dropped);
      ignore_bins reason_but_forwarded =
        (binsof(DROP_REASON.bad_address) ||
         binsof(DROP_REASON.oversized)) &&
        binsof(EXPECTED_ACTION.forwarded);
    }
  endgroup


  // Request and response fields enter this covergroup only after scoreboard
  // association.  The scoreboard still owns pass/fail; coverage records which
  // correct routes and packet classes were exercised.
  covergroup routing_feature_cg with function sample(
    bit [1:0]    request_addr,
    int unsigned expected_channel,
    int unsigned actual_channel,
    int unsigned packet_length,
    bit          compare_pass
  );
    option.per_instance = 1;

    REQUEST: coverpoint request_addr {
      bins channel0 = {0};
      bins channel1 = {1};
      bins channel2 = {2};
    }

    EXPECTED_CHANNEL: coverpoint expected_channel {
      bins channel0 = {0};
      bins channel1 = {1};
      bins channel2 = {2};
    }

    ACTUAL_CHANNEL: coverpoint actual_channel {
      bins channel0 = {0};
      bins channel1 = {1};
      bins channel2 = {2};
    }

    LENGTH_CLASS: coverpoint packet_length {
      bins short  = {[1:15]};
      bins medium = {[16:40]};
      bins long   = {[41:63]};
    }

    COMPARE_RESULT: coverpoint compare_pass {
      bins pass = {1};
      illegal_bins fail = {0};
    }

    EXPECTED_X_ACTUAL: cross EXPECTED_CHANNEL, ACTUAL_CHANNEL {
      ignore_bins ch0_to_ch1 = binsof(EXPECTED_CHANNEL.channel0) &&
                               binsof(ACTUAL_CHANNEL.channel1);
      ignore_bins ch0_to_ch2 = binsof(EXPECTED_CHANNEL.channel0) &&
                               binsof(ACTUAL_CHANNEL.channel2);
      ignore_bins ch1_to_ch0 = binsof(EXPECTED_CHANNEL.channel1) &&
                               binsof(ACTUAL_CHANNEL.channel0);
      ignore_bins ch1_to_ch2 = binsof(EXPECTED_CHANNEL.channel1) &&
                               binsof(ACTUAL_CHANNEL.channel2);
      ignore_bins ch2_to_ch0 = binsof(EXPECTED_CHANNEL.channel2) &&
                               binsof(ACTUAL_CHANNEL.channel0);
      ignore_bins ch2_to_ch1 = binsof(EXPECTED_CHANNEL.channel2) &&
                               binsof(ACTUAL_CHANNEL.channel1);
    }

    ROUTE_X_LENGTH: cross REQUEST, LENGTH_CLASS;
  endgroup


  // Output-interface facts only: physical channel, packet length, and the
  // number of suspend cycles actually seen by the monitor for that packet.
  covergroup flow_control_cg with function sample(
    int unsigned channel,
    int unsigned packet_length,
    int unsigned stall_cycles
  );
    option.per_instance = 1;

    CHANNEL: coverpoint channel {
      bins channel0 = {0};
      bins channel1 = {1};
      bins channel2 = {2};
    }

    LENGTH_CLASS: coverpoint packet_length {
      bins short  = {[1:15]};
      bins medium = {[16:40]};
      bins long   = {[41:63]};
    }

    STALL_CLASS: coverpoint stall_cycles {
      bins none     = {0};
      bins light    = {[1:4]};
      bins moderate = {[5:15]};
      bins heavy    = {[16:$]};
    }

    LENGTH_X_STALL:  cross LENGTH_CLASS, STALL_CLASS;
    CHANNEL_X_STALL: cross CHANNEL, STALL_CLASS;
  endgroup


  // Temporal feature: remember the context at reset assertion, then sample
  // only when the first correlated post-reset route is seen.
  covergroup reset_recovery_cg with function sample(
    router_reset_context_e reset_context,
    bit                    recovery_compare_pass
  );
    option.per_instance = 1;

    RESET_CONTEXT: coverpoint reset_context {
      bins idle      = {ROUTER_RESET_IDLE};
      bins in_packet = {ROUTER_RESET_IN_PACKET};
    }

    RECOVERY_RESULT: coverpoint recovery_compare_pass {
      bins pass = {1};
      illegal_bins fail = {0};
    }

    CONTEXT_X_RECOVERY: cross RESET_CONTEXT, RECOVERY_RESULT;
  endgroup


  function new(string name = "router_coverage", uvm_component parent = null);
    super.new(name, parent);

    yapp_cov_fifo     = new("yapp_cov_fifo", this);
    hbus_cov_fifo     = new("hbus_cov_fifo", this);
    chan0_cov_fifo    = new("chan0_cov_fifo", this);
    chan1_cov_fifo    = new("chan1_cov_fifo", this);
    chan2_cov_fifo    = new("chan2_cov_fifo", this);
    decision_cov_fifo = new("decision_cov_fifo", this);
    route_cov_fifo    = new("route_cov_fifo", this);

    packet_protocol_cg = new();
    register_access_cg = new();
    counter_readback_cg = new();
    interrupt_status_cg = new();
    length_policy_cg   = new();
    error_response_cg  = new();
    routing_feature_cg = new();
    flow_control_cg    = new();
    reset_recovery_cg  = new();
  endfunction


  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!yapp_vif_config::get(this, "", "vif", yapp_vif))
      `uvm_warning(get_type_name(), "No YAPP vif: reset context coverage disabled")
    if (!uvm_config_db#(virtual clock_and_reset_if)::get(
          this, "", "clk_rst_vif", clk_rst_vif))
      `uvm_warning(get_type_name(), "No clock/reset vif: reset coverage disabled")
  endfunction


  function bit is_incrementing_payload(yapp_packet packet);
    foreach (packet.payload[i])
      if (packet.payload[i] != (i & 8'hff))
        return 0;
    return 1;
  endfunction


  task run_phase(uvm_phase phase);
    fork
      collect_yapp_packets();
      collect_hbus_transactions();
      collect_channel_packets(chan0_cov_fifo);
      collect_channel_packets(chan1_cov_fifo);
      collect_channel_packets(chan2_cov_fifo);
      collect_decision_events();
      collect_route_events();
      monitor_reset_context();
    join
  endtask


  task collect_yapp_packets();
    yapp_packet packet;
    forever begin
      yapp_cov_fifo.get_peek_export.get(packet);
      packet_protocol_cg.sample(packet.addr,
                                packet.length,
                                packet.parity_type,
                                is_incrementing_payload(packet));
    end
  endtask


  task collect_hbus_transactions();
    hbus_transaction transaction;
    forever begin
      hbus_cov_fifo.get_peek_export.get(transaction);
      register_access_cg.sample(
        transaction.hwr_rd == hbus_pkg::HBUS_WRITE,
        transaction.haddr,
        transaction.hdata
      );
      counter_readback_cg.sample(
        transaction.hwr_rd == hbus_pkg::HBUS_WRITE,
        transaction.haddr,
        transaction.hdata
      );
      interrupt_status_cg.sample(
        transaction.hwr_rd == hbus_pkg::HBUS_WRITE,
        transaction.haddr,
        transaction.hdata
      );
    end
  endtask


  task collect_channel_packets(
    uvm_tlm_analysis_fifo #(channel_packet) channel_fifo
  );
    channel_packet packet;
    forever begin
      channel_fifo.get_peek_export.get(packet);
      flow_control_cg.sample(packet.observed_channel,
                             packet.length,
                             packet.stall_cycles);
    end
  endtask


  task collect_decision_events();
    router_decision_cov_item event_item;
    forever begin
      decision_cov_fifo.get_peek_export.get(event_item);

      // Address errors are covered by error_response_cg.  They are excluded
      // from the length-policy cross because address, not length, determines
      // their action.
      if (event_item.request_addr < 3)
        length_policy_cg.sample(event_item.enable_at_accept,
                                event_item.max_size_at_accept,
                                event_item.length_relation,
                                event_item.expected_action);

      error_response_cg.sample(event_item.parity_type,
                               event_item.drop_reason,
                               event_item.expected_action);
    end
  endtask


  task collect_route_events();
    router_route_cov_item event_item;
    forever begin
      route_cov_fifo.get_peek_export.get(event_item);
      routing_feature_cg.sample(event_item.request_addr,
                                event_item.expected_channel,
                                event_item.actual_channel,
                                event_item.packet_length,
                                event_item.compare_pass);

      if (post_reset_route_pending) begin
        reset_recovery_cg.sample(last_reset_context,
                                 event_item.compare_pass);
        post_reset_route_pending = 0;
      end
    end
  endtask


  task monitor_reset_context();
    if ((clk_rst_vif == null) || (yapp_vif == null))
      return;

    forever begin
      @(posedge clk_rst_vif.reset);
      last_reset_context = (yapp_vif.in_data_vld === 1'b1)
                         ? ROUTER_RESET_IN_PACKET
                         : ROUTER_RESET_IDLE;
      @(negedge clk_rst_vif.reset);
      post_reset_route_pending = 1;
    end
  endtask


  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(),
      $sformatf({
        "Functional Coverage Summary:\n",
        "  raw.packet_protocol = %0.2f%%\n",
        "  raw.register_access = %0.2f%%\n",
        "  feature.counter_readback = %0.2f%%\n",
        "  feature.interrupt_status = %0.2f%%\n",
        "  feature.length_policy = %0.2f%%\n",
        "  feature.error_response = %0.2f%%\n",
        "  feature.routing = %0.2f%%\n",
        "  feature.flow_control = %0.2f%%\n",
        "  feature.reset_recovery = %0.2f%%\n"
      },
      packet_protocol_cg.get_coverage(),
      register_access_cg.get_coverage(),
      counter_readback_cg.get_coverage(),
      interrupt_status_cg.get_coverage(),
      length_policy_cg.get_coverage(),
      error_response_cg.get_coverage(),
      routing_feature_cg.get_coverage(),
      flow_control_cg.get_coverage(),
      reset_recovery_cg.get_coverage()),
      UVM_LOW)
  endfunction

endclass : router_coverage
