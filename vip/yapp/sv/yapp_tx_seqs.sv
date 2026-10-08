/*-----------------------------------------------------------------
File name     : yapp_tx_seqs.sv
Developers    : Kathleen Meade, Brian Dickinson
Created       : 01/04/11
Description   : yapp UVC TX sequences from lab07_integ for accelerated UVM
Notes         : From the Cadence "SystemVerilog Accelerated Verification with UVM" training
-------------------------------------------------------------------
Copyright Cadence Design Systems (c)2015
-----------------------------------------------------------------*/

//------------------------------------------------------------------------------
//
// SEQUENCE: base yapp sequence - base sequence with objections from which 
// all sequences can be derived
//
//------------------------------------------------------------------------------
class yapp_base_seq extends uvm_sequence#(yapp_packet);
  
  // Required macro for sequences automation
  `uvm_object_utils(yapp_base_seq)

  // Constructor
  function new(string name="yapp_base_seq");
    super.new(name);
  endfunction

  task pre_body();
    uvm_phase phase;
    `ifdef UVM_VERSION_1_2
      // in UVM1.2, get starting phase from method
      phase = get_starting_phase();
    `else
      phase = starting_phase;
    `endif
    if (phase != null) begin
      phase.raise_objection(this, get_type_name());
      `uvm_info(get_type_name(), "raise objection", UVM_MEDIUM)
    end
  endtask : pre_body

  task post_body();
    uvm_phase phase;
    `ifdef UVM_VERSION_1_2
      // in UVM1.2, get starting phase from method
      phase = get_starting_phase();
    `else
      phase = starting_phase;
    `endif
    if (phase != null) begin
      phase.drop_objection(this, get_type_name());
      `uvm_info(get_type_name(), "drop objection", UVM_MEDIUM)
    end
  endtask : post_body

endclass : yapp_base_seq



//------------------------------------------------------------------------------
// Configurable protocol-level sequences used by project virtual sequences
//------------------------------------------------------------------------------

typedef enum int {
  YAPP_PAYLOAD_RANDOM,
  YAPP_PAYLOAD_INCREMENTING,
  YAPP_PAYLOAD_CONSTANT
} yapp_payload_profile_e;


// Send exactly one packet.  This is the small reusable protocol primitive;
// project sequences decide which values to put in these knobs.
class yapp_send_one_seq extends yapp_base_seq;

  `uvm_object_utils(yapp_send_one_seq)

  rand bit [1:0]              target_addr;
  rand bit [5:0]              target_length;
  rand parity_t               target_parity;
  rand int unsigned           target_gap;
  rand yapp_payload_profile_e payload_profile;
  rand bit [7:0]              constant_payload;

  bit allow_illegal_addr = 0;

  constraint legal_length_c {
    target_length inside {[1:63]};
  }

  constraint legal_addr_c {
    if (!allow_illegal_addr)
      target_addr inside {[0:2]};
  }

  constraint gap_c {
    target_gap inside {[0:20]};
  }

  function new(string name = "yapp_send_one_seq");
    super.new(name);
  endfunction

  virtual task body();

    `uvm_create(req)

    // The reusable packet item is legal by default.  Negative tests must make
    // the illegal-address intent explicit through allow_illegal_addr.
    if (allow_illegal_addr)
      req.default_addr.constraint_mode(0);

    if (!req.randomize() with {
      addr         == local::target_addr;
      length       == local::target_length;
      parity_type  == local::target_parity;
      packet_delay == local::target_gap;
    }) begin
      `uvm_error(get_type_name(),
                 $sformatf("Unable to create packet addr=%0d len=%0d",
                           target_addr, target_length))
      return;
    end

    case (payload_profile)
      YAPP_PAYLOAD_INCREMENTING:
        foreach (req.payload[i]) req.payload[i] = i;

      YAPP_PAYLOAD_CONSTANT:
        foreach (req.payload[i]) req.payload[i] = constant_payload;

      default: begin
        // yapp_packet randomization already produced random payload bytes.
      end
    endcase

    // Payload may have been edited after randomization.
    req.set_parity();

    `uvm_info(get_type_name(),
              $sformatf("Send one packet: addr=%0d len=%0d parity=%s gap=%0d",
                        req.addr, req.length, req.parity_type.name(),
                        req.packet_delay),
              UVM_MEDIUM)

    `uvm_send(req)

  endtask : body

endclass : yapp_send_one_seq


// Generate a configurable stream on the YAPP input interface.  The sequence
// owns protocol-level distributions only; system-level coordination belongs in
// a router virtual sequence.
class yapp_traffic_seq extends yapp_base_seq;

  `uvm_object_utils(yapp_traffic_seq)

  rand int unsigned packet_count;
  rand bit [5:0]    min_length;
  rand bit [5:0]    max_length;
  rand int unsigned min_gap;
  rand int unsigned max_gap;
  rand int unsigned bad_parity_percent;

  bit       fixed_addr_enable = 0;
  bit [1:0] fixed_addr        = 0;
  bit       allow_illegal_addr = 0;
  yapp_payload_profile_e payload_profile = YAPP_PAYLOAD_RANDOM;

  constraint count_c {
    packet_count inside {[1:200]};
  }

  constraint length_range_c {
    min_length inside {[1:63]};
    max_length inside {[1:63]};
    min_length <= max_length;
  }

  constraint gap_range_c {
    min_gap <= max_gap;
    max_gap <= 100;
  }

  constraint parity_weight_c {
    bad_parity_percent inside {[0:100]};
  }

  function new(string name = "yapp_traffic_seq");
    super.new(name);
  endfunction

  virtual task body();

    repeat (packet_count) begin
      yapp_send_one_seq send_one;
      int unsigned      parity_pick;

      send_one = yapp_send_one_seq::type_id::create("send_one");
      send_one.allow_illegal_addr = allow_illegal_addr;

      if (!send_one.randomize() with {
        target_length inside {[local::min_length:local::max_length]};
        target_gap    inside {[local::min_gap:local::max_gap]};
        if (local::fixed_addr_enable)
          target_addr == local::fixed_addr;
        else if (!local::allow_illegal_addr)
          target_addr inside {[0:2]};
        payload_profile == local::payload_profile;
      }) begin
        `uvm_error(get_type_name(), "Unable to randomize YAPP traffic packet")
        return;
      end

      parity_pick = $urandom_range(0, 99);
      send_one.target_parity =
        (parity_pick < bad_parity_percent) ? BAD_PARITY : GOOD_PARITY;

      send_one.start(m_sequencer);
    end

  endtask : body

endclass : yapp_traffic_seq





// //------------------------------------------------------------------------------
// //
// // SEQUENCE: yapp_012_seq - send random packets to channel 0, 1, 2 in order
// //
// //------------------------------------------------------------------------------
// class yapp_012_seq extends yapp_base_seq;
  
//   // Required macro for sequences automation
//   `uvm_object_utils(yapp_012_seq)

//   // Constructor
//   function new(string name="yapp_012_seq");
//     super.new(name);
//   endfunction

//   // Sequence body definition
//   virtual task body();
//     `uvm_info(get_type_name(), "Executing YAPP_012_SEQ", UVM_LOW)
//     `uvm_do_with(req, {req.addr == 2'b00;})
//     `uvm_do_with(req, {req.addr == 2'b01;})
//     `uvm_do_with(req, {req.addr == 2'b10;})
//   endtask
  
// endclass : yapp_012_seq

// //------------------------------------------------------------------------------
// //
// // SEQUENCE: yapp_1_seq - send a random packet to Channel 1
// //
// //------------------------------------------------------------------------------
// class yapp_1_seq extends yapp_base_seq;
  
//   // Required macro for sequences automation
//   `uvm_object_utils(yapp_1_seq)

//   // Constructor
//   function new(string name="yapp_1_seq");
//     super.new(name);
//   endfunction

//   // Sequence body definition
//   virtual task body();
//     `uvm_info(get_type_name(), "Executing YAPP_1_SEQ", UVM_LOW)
//    `uvm_do_with(req, {req.addr == 2'b01;})
//   endtask
  
// endclass : yapp_1_seq

// //------------------------------------------------------------------------------
// //
// // SEQUENCE: yapp_111_seq - send three random packets to channel 1
// //
// //------------------------------------------------------------------------------
// class yapp_111_seq extends yapp_base_seq;
  
//   // Required macro for sequences automation
//   `uvm_object_utils(yapp_111_seq)

//   // Nested Sequence - executes yapp_1_seq three times
//   yapp_1_seq addr_1_seq;

//   // Constructor
//   function new(string name="yapp_111_seq");
//     super.new(name);
//   endfunction

//   // Sequence body definition
//   virtual task body();
//     `uvm_info(get_type_name(), "Executing YAPP_111_SEQ", UVM_LOW)
//     repeat (3) 
//     `uvm_do(addr_1_seq)
//   endtask
  
// endclass : yapp_111_seq

//------------------------------------------------------------------------------
//
// SEQUENCE: yapp_incr_payload_seq - sends single packet with incrementing payload
//
//------------------------------------------------------------------------------
class yapp_incr_payload_seq extends yapp_base_seq;
  
  // Required macro for sequences automation
  `uvm_object_utils(yapp_incr_payload_seq)

  // Constructor
  function new(string name="yapp_incr_payload_seq");
    super.new(name);
  endfunction

  // Sequence body definition
  virtual task body();
    `uvm_info(get_type_name(), "Executing YAPP_INCR_PAYLOAD_SEQ", UVM_LOW)


    //`uvm_do_with(req, {foreach (payload[i]) payload[i] == i ; })
  
    `uvm_create(req)
    assert(req.randomize());
    for (int i=0;i<req.length;i++)
      req.payload[i] = i;
    req.set_parity();  // recalculate parity taking into account parity_type
    `uvm_send(req)
  endtask
endclass : yapp_incr_payload_seq
  
// //------------------------------------------------------------------------------
// //
// // SEQUENCE: yapp_rnd_seq
// //
// //------------------------------------------------------------------------------

// class yapp_rnd_seq extends yapp_base_seq;

//   // Required macro for sequences automation
//   `uvm_object_utils(yapp_rnd_seq)

//   // Parameter for this sequence
//   rand int count;

//   // Sequence Constraints
//   constraint count_limit { count inside {[1:10]}; }

//   // Constructor
//   function new(string name="yapp_rnd_seq");
//     super.new(name);
//   endfunction

//   // Sequence body definition
//   virtual task body();
//     `uvm_info(get_type_name(), $sformatf("Executing YAPP_RND_SEQ %0d times...", count), UVM_LOW)
//     repeat (count) begin
//       `uvm_do(req)
//     end
//   endtask

// endclass : yapp_rnd_seq

// //------------------------------------------------------------------------------
// //
// // SEQUENCE: six_yapp_seq
// //
// //------------------------------------------------------------------------------

// class six_yapp_seq extends yapp_base_seq;

//   // Required macro for sequences automation
//   `uvm_object_utils(six_yapp_seq)

//   // Parameter for this sequence
//   yapp_rnd_seq yss;

//   // Constructor
//   function new(string name="six_yapp_seq");
//     super.new(name);
//   endfunction

//   // Sequence body definition
//   virtual task body();
//     `uvm_info(get_type_name(), "Executing SIX_YAPP_SEQ" , UVM_LOW)
//     `uvm_do_with(yss, {count==6;})
//   endtask

// endclass : six_yapp_seq

// //------------------------------------------------------------------------------
// //
// // SEQUENCE: yapp_exhaustive_seq
// //
// //------------------------------------------------------------------------------

// class yapp_exhaustive_seq extends yapp_base_seq;

//   // Required macro for sequences automation
//   `uvm_object_utils(yapp_exhaustive_seq)

//   // handles for all lab05 sequences
//   yapp_012_seq y012;
//   yapp_1_seq y1;
//   yapp_111_seq y111;
//   yapp_incr_payload_seq yinc;
//   six_yapp_seq ysix;

//   // Constructor
//   function new(string name="yapp_exhaustive_seq");
//     super.new(name);
//   endfunction

//   // Sequence body definition
//   virtual task body();
//     `uvm_info(get_type_name(), "Executing YAPP_EXHAUSTIVE_SEQ" , UVM_LOW)
//     `uvm_do(y012)
//     `uvm_do(y1)
//     `uvm_do(y111)
//     `uvm_do(yinc)
//     `uvm_do(ysix)
//   endtask

// endclass : yapp_exhaustive_seq

