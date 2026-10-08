//------------------------------------------------------------------------------
// Router project-level traffic sequences
//
// These sequences sit between reusable VIP protocol primitives and system
// virtual sequences.  Each class represents a reusable, single-interface
// Router traffic pattern from the verification plan.
//------------------------------------------------------------------------------


// Route packets through a configurable address pattern.
class router_address_pattern_seq extends yapp_base_seq;

  `uvm_object_utils(router_address_pattern_seq)

  bit [1:0] address_list[$];
  int unsigned packets_per_address = 1;
  bit [5:0] packet_length = 6'd5;
  int unsigned packet_gap = 1;
  yapp_pkg::parity_t parity_type = yapp_pkg::GOOD_PARITY;
  yapp_pkg::yapp_payload_profile_e payload_profile =
    yapp_pkg::YAPP_PAYLOAD_INCREMENTING;

  function new(string name = "router_address_pattern_seq");
    super.new(name);
  endfunction

  virtual task body();

    if (address_list.size() == 0) begin
      address_list.push_back(2'd0);
      address_list.push_back(2'd1);
      address_list.push_back(2'd2);
    end

    foreach (address_list[i]) begin
      repeat (packets_per_address) begin
        yapp_send_one_seq send_one;

        send_one = yapp_send_one_seq::type_id::create("send_one");
        send_one.target_addr     = address_list[i];
        send_one.target_length   = packet_length;
        send_one.target_parity   = parity_type;
        send_one.target_gap      = packet_gap;
        send_one.payload_profile = payload_profile;
        send_one.allow_illegal_addr = (address_list[i] == 2'd3);
        send_one.start(m_sequencer);
      end
    end

  endtask : body

endclass : router_address_pattern_seq


// Send N-1, N, and N+1 packets for one configured maximum length N.
class router_length_boundary_seq extends yapp_base_seq;

  `uvm_object_utils(router_length_boundary_seq)

  rand int unsigned boundary;
  rand bit [1:0]    target_addr;
  int unsigned      packet_gap = 1;

  constraint boundary_c {
    boundary inside {[2:62]};
  }

  constraint target_c {
    target_addr inside {[0:2]};
  }

  function new(string name = "router_length_boundary_seq");
    super.new(name);
  endfunction

  task send_length(int unsigned length_value, string label);
    yapp_send_one_seq send_one;

    send_one = yapp_send_one_seq::type_id::create({"send_", label});
    send_one.target_addr     = target_addr;
    send_one.target_length   = length_value;
    send_one.target_parity   = yapp_pkg::GOOD_PARITY;
    send_one.target_gap      = packet_gap;
    send_one.payload_profile = yapp_pkg::YAPP_PAYLOAD_INCREMENTING;
    send_one.start(m_sequencer);
  endtask

  virtual task body();
    `uvm_info(get_type_name(),
              $sformatf("Boundary traffic: max=%0d, lengths=%0d/%0d/%0d",
                        boundary, boundary-1, boundary, boundary+1),
              UVM_LOW)

    send_length(boundary - 1, "below");
    send_length(boundary,     "equal");
    send_length(boundary + 1, "above");
  endtask

endclass : router_length_boundary_seq


// Generate one deterministic error or control event on the YAPP interface.
// HBUS configuration needed by OVERSIZED/DISABLED is deliberately left to the
// owning virtual sequence.
class router_error_event_seq extends yapp_base_seq;

  `uvm_object_utils(router_error_event_seq)

  rand router_error_kind_e error_kind;
  rand bit [1:0]           target_addr;
  rand int unsigned        configured_max_size;
  rand int unsigned        legal_length;

  constraint error_c {
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
    configured_max_size inside {[2:62]};
    legal_length inside {[1:63]};
  }

  function new(string name = "router_error_event_seq");
    super.new(name);
  endfunction

  virtual task body();
    yapp_send_one_seq send_one;

    send_one = yapp_send_one_seq::type_id::create("send_error_event");
    send_one.target_addr     = target_addr;
    send_one.target_length   = legal_length;
    send_one.target_parity   = yapp_pkg::GOOD_PARITY;
    send_one.target_gap      = 1;
    send_one.payload_profile = yapp_pkg::YAPP_PAYLOAD_INCREMENTING;

    case (error_kind)
      ROUTER_ERROR_BAD_PARITY:
        send_one.target_parity = yapp_pkg::BAD_PARITY;

      ROUTER_ERROR_ILLEGAL_ADDRESS: begin
        send_one.target_addr        = 2'd3;
        send_one.allow_illegal_addr = 1;
      end

      ROUTER_ERROR_OVERSIZED:
        send_one.target_length = configured_max_size + 1;

      ROUTER_ERROR_DISABLED: begin
        // A normal legal packet is used; router_en=0 is configured by HBUS.
      end

      default:
        `uvm_error(get_type_name(), "Unsupported router error kind")
    endcase

    send_one.start(m_sequencer);
  endtask

endclass : router_error_event_seq


// Map a scenario-level traffic profile onto the configurable YAPP VIP stream.
class router_traffic_profile_seq extends yapp_base_seq;

  `uvm_object_utils(router_traffic_profile_seq)

  rand router_traffic_profile_e profile;
  rand int unsigned             packet_count;
  rand bit [1:0]                target_addr;
  rand int unsigned             bad_parity_percent;

  // Orthogonal overrides let a virtual sequence combine a length/gap profile
  // with a known destination or a configuration-dependent legal range.
  bit          force_target_addr    = 0;
  bit          length_range_override = 0;
  int unsigned override_min_length   = 1;
  int unsigned override_max_length   = 63;

  constraint count_c {
    packet_count inside {[1:200]};
  }

  constraint target_c {
    target_addr inside {[0:2]};
  }

  constraint parity_c {
    bad_parity_percent inside {[0:20]};
  }

  function new(string name = "router_traffic_profile_seq");
    super.new(name);
  endfunction

  virtual task body();
    yapp_traffic_seq traffic;

    traffic = yapp_traffic_seq::type_id::create("traffic");
    traffic.packet_count       = packet_count;
    traffic.bad_parity_percent = bad_parity_percent;
    traffic.payload_profile    = yapp_pkg::YAPP_PAYLOAD_RANDOM;
    traffic.allow_illegal_addr = 0;

    case (profile)
      ROUTER_TRAFFIC_BACK_TO_BACK: begin
        traffic.min_length = 1;
        traffic.max_length = 40;
        traffic.min_gap    = 0;
        traffic.max_gap    = 0;
      end

      ROUTER_TRAFFIC_LONG_PACKET: begin
        traffic.min_length = 41;
        traffic.max_length = 63;
        traffic.min_gap    = 0;
        traffic.max_gap    = 1;
      end

      ROUTER_TRAFFIC_SAME_CHANNEL: begin
        traffic.min_length        = 1;
        traffic.max_length        = 63;
        traffic.min_gap           = 0;
        traffic.max_gap           = 3;
        traffic.fixed_addr_enable = 1;
        traffic.fixed_addr        = target_addr;
      end

      ROUTER_TRAFFIC_MULTI_CHANNEL: begin
        traffic.min_length        = 1;
        traffic.max_length        = 63;
        traffic.min_gap           = 0;
        traffic.max_gap           = 5;
        traffic.fixed_addr_enable = 0;
      end

      default: begin
        traffic.min_length = 1;
        traffic.max_length = 40;
        traffic.min_gap    = 1;
        traffic.max_gap    = 8;
      end
    endcase

    if (force_target_addr) begin
      traffic.fixed_addr_enable = 1;
      traffic.fixed_addr        = target_addr;
    end

    if (length_range_override) begin
      traffic.min_length = override_min_length;
      traffic.max_length = override_max_length;
    end

    traffic.start(m_sequencer);
  endtask

endclass : router_traffic_profile_seq


// Deterministic stimulus used by the counter and reset-default scenarios.
// Keeping this in the project sequence layer makes the intent visible without
// embedding HBUS or channel coordination in a reusable YAPP VIP sequence.
class router_counter_stimulus_seq extends yapp_base_seq;

  `uvm_object_utils(router_counter_stimulus_seq)

  function new(string name = "router_counter_stimulus_seq");
    super.new(name);
  endfunction

  task send_packet(bit [1:0]        addr,
                   bit [5:0]        length,
                   yapp_pkg::parity_t parity_type,
                   bit              allow_illegal_addr = 0);
    yapp_send_one_seq packet_seq;

    packet_seq = yapp_send_one_seq::type_id::create(
      $sformatf("packet_addr%0d_len%0d", addr, length)
    );
    packet_seq.target_addr        = addr;
    packet_seq.target_length      = length;
    packet_seq.target_parity      = parity_type;
    packet_seq.target_gap         = 1;
    packet_seq.payload_profile    = yapp_pkg::YAPP_PAYLOAD_INCREMENTING;
    packet_seq.allow_illegal_addr = allow_illegal_addr;
    packet_seq.start(m_sequencer);
  endtask

  virtual task body();
    // Four forwarded packets: ch0=1, ch1=2, ch2=1.
    send_packet(2'd0, 6'd5,  yapp_pkg::GOOD_PARITY);
    send_packet(2'd1, 6'd5,  yapp_pkg::GOOD_PARITY);
    send_packet(2'd2, 6'd5,  yapp_pkg::GOOD_PARITY);

    // Three independent counter events. Bad parity is still routed to ch1;
    // oversized and illegal-address packets are dropped.
    send_packet(2'd3, 6'd5,  yapp_pkg::GOOD_PARITY, 1'b1);
    send_packet(2'd0, 6'd21, yapp_pkg::GOOD_PARITY);
    send_packet(2'd1, 6'd5,  yapp_pkg::BAD_PARITY);
  endtask

endclass : router_counter_stimulus_seq
