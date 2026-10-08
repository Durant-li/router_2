// Reusable HBUS protocol sequences.
//
// The base sequence owns the transaction handshake. Derived sequences expose
// only useful Router-level knobs: address, data and optional idle cycles.

class hbus_base_seq extends uvm_sequence #(hbus_transaction);

  `uvm_object_utils(hbus_base_seq)

  function new(string name = "hbus_base_seq");
    super.new(name);
  endfunction

  task pre_body();
    uvm_phase phase;
    `ifdef UVM_VERSION_1_2
      phase = get_starting_phase();
    `else
      phase = starting_phase;
    `endif
    if (phase != null)
      phase.raise_objection(this, get_type_name());
  endtask

  task post_body();
    uvm_phase phase;
    `ifdef UVM_VERSION_1_2
      phase = get_starting_phase();
    `else
      phase = starting_phase;
    `endif
    if (phase != null)
      phase.drop_objection(this, get_type_name());
  endtask

  protected task send_access(
    input bit [15:0]           address,
    input hbus_read_write_enum direction,
    inout bit [7:0]            data_value,
    input int unsigned         idle_cycles = 0
  );
    hbus_transaction access;

    access = hbus_transaction::type_id::create("access");
    start_item(access);
    access.haddr              = address;
    access.hwr_rd             = direction;
    access.hdata              = data_value;
    access.wait_between_cycle = idle_cycles;
    finish_item(access);

    // For reads the driver writes the sampled bus value back into the item.
    data_value = access.hdata;
  endtask

endclass : hbus_base_seq


class hbus_write_seq extends hbus_base_seq;

  `uvm_object_utils(hbus_write_seq)

  rand bit [15:0]   address;
  rand bit [7:0]    data;
  rand int unsigned idle_cycles;

  constraint idle_c { idle_cycles inside {[0:3]}; }

  function new(string name = "hbus_write_seq");
    super.new(name);
  endfunction

  task body();
    bit [7:0] write_data = data;
    send_access(address, HBUS_WRITE, write_data, idle_cycles);
    `uvm_info(get_type_name(),
              $sformatf("WRITE [0x%04h] = 0x%02h", address, data),
              UVM_MEDIUM)
  endtask

endclass : hbus_write_seq


class hbus_read_seq extends hbus_base_seq;

  `uvm_object_utils(hbus_read_seq)

  rand bit [15:0]   address;
  bit [7:0]         data;
  rand int unsigned idle_cycles;

  constraint idle_c { idle_cycles inside {[0:3]}; }

  function new(string name = "hbus_read_seq");
    super.new(name);
  endfunction

  task body();
    data = '0;
    send_access(address, HBUS_READ, data, idle_cycles);
    `uvm_info(get_type_name(),
              $sformatf("READ  [0x%04h] = 0x%02h", address, data),
              UVM_MEDIUM)
  endtask

endclass : hbus_read_seq


// Configure the two Router control registers as one reusable protocol sequence.
class hbus_set_yapp_regs_seq extends hbus_base_seq;

  `uvm_object_utils(hbus_set_yapp_regs_seq)

  rand bit [7:0] max_pkt_reg;
  rand bit [7:0] enable_reg;

  constraint max_pkt_c { max_pkt_reg inside {[1:63]}; }
  constraint enable_c  { enable_reg inside {[0:1]}; }

  function new(string name = "hbus_set_yapp_regs_seq");
    super.new(name);
  endfunction

  task body();
    bit [7:0] value;

    value = max_pkt_reg;
    send_access(16'h1000, HBUS_WRITE, value);

    value = enable_reg;
    send_access(16'h1001, HBUS_WRITE, value);
  endtask

endclass : hbus_set_yapp_regs_seq


class hbus_get_yapp_regs_seq extends hbus_base_seq;

  `uvm_object_utils(hbus_get_yapp_regs_seq)

  bit [7:0] max_pkt_reg;
  bit [7:0] enable_reg;

  function new(string name = "hbus_get_yapp_regs_seq");
    super.new(name);
  endfunction

  task body();
    send_access(16'h1000, HBUS_READ, max_pkt_reg);
    send_access(16'h1001, HBUS_READ, enable_reg);
  endtask

endclass : hbus_get_yapp_regs_seq


// // Compatibility wrappers used by the original course tests. The project-level
// // virtual sequences normally use hbus_write_seq/hbus_read_seq directly.
// class hbus_small_packet_seq extends hbus_base_seq;
//   `uvm_object_utils(hbus_small_packet_seq)
//   function new(string name = "hbus_small_packet_seq"); super.new(name); endfunction
//   task body();
//     bit [7:0] value;
//     value = 8'd20; send_access(16'h1000, HBUS_WRITE, value);
//     value = 8'h01; send_access(16'h1001, HBUS_WRITE, value);
//   endtask
// endclass


// class hbus_set_default_regs_seq extends hbus_base_seq;
//   `uvm_object_utils(hbus_set_default_regs_seq)
//   function new(string name = "hbus_set_default_regs_seq"); super.new(name); endfunction
//   task body();
//     bit [7:0] value;
//     value = 8'd63; send_access(16'h1000, HBUS_WRITE, value);
//     value = 8'h01; send_access(16'h1001, HBUS_WRITE, value);
//   endtask
// endclass


// class hbus_read_max_pkt_seq extends hbus_base_seq;
//   `uvm_object_utils(hbus_read_max_pkt_seq)
//   bit [7:0] max_pkt_reg;
//   function new(string name = "hbus_read_max_pkt_seq"); super.new(name); endfunction
//   task body(); send_access(16'h1000, HBUS_READ, max_pkt_reg); endtask
// endclass


// class hbus_read_enable_seq extends hbus_base_seq;
//   `uvm_object_utils(hbus_read_enable_seq)
//   bit [7:0] enable_reg;
//   function new(string name = "hbus_read_enable_seq"); super.new(name); endfunction
//   task body(); send_access(16'h1001, HBUS_READ, enable_reg); endtask
// endclass


// class hbus_set_get_regs_seq extends hbus_base_seq;
//   `uvm_object_utils(hbus_set_get_regs_seq)
//   function new(string name = "hbus_set_get_regs_seq"); super.new(name); endfunction
//   task body();
//     bit [7:0] value;
//     value = 8'd63; send_access(16'h1000, HBUS_WRITE, value);
//     value = 8'h01; send_access(16'h1001, HBUS_WRITE, value);
//     send_access(16'h1000, HBUS_READ, value);
//     send_access(16'h1001, HBUS_READ, value);
//   endtask
// endclass
