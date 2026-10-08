typedef enum bit {BAD_PARITY, GOOD_PARITY} parity_e;

// Output packet reconstructed from pins by channel_rx_monitor.
class channel_packet extends uvm_sequence_item;

  bit [5:0] length;
  bit [1:0] addr;
  bit [7:0] payload[];
  bit [7:0] parity;

  parity_e     parity_type;
  int unsigned stall_cycles;
  int unsigned observed_channel;

  `uvm_object_utils_begin(channel_packet)
    `uvm_field_int(length, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_array_int(payload, UVM_DEFAULT)
    `uvm_field_int(parity, UVM_DEFAULT)
    `uvm_field_enum(parity_e, parity_type, UVM_DEFAULT)
    `uvm_field_int(stall_cycles, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
    `uvm_field_int(observed_channel, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
  `uvm_object_utils_end

  function new(string name = "channel_packet");
    super.new(name);
  endfunction

  function bit [7:0] calc_parity();
    calc_parity = {length, addr};
    foreach (payload[i])
      calc_parity ^= payload[i];
  endfunction

endclass : channel_packet
