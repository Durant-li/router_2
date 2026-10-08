typedef enum bit {HBUS_READ, HBUS_WRITE} hbus_read_write_enum;

// One HBUS register or memory access.
class hbus_transaction extends uvm_sequence_item;

  rand bit [15:0]           haddr;
  rand bit [7:0]            hdata;
  rand hbus_read_write_enum hwr_rd;
  rand int unsigned         wait_between_cycle;

  constraint idle_cycles_c {
    wait_between_cycle inside {[0:3]};
  }

  `uvm_object_utils_begin(hbus_transaction)
    `uvm_field_int(haddr, UVM_DEFAULT)
    `uvm_field_int(hdata, UVM_DEFAULT)
    `uvm_field_enum(hbus_read_write_enum, hwr_rd, UVM_DEFAULT)
    `uvm_field_int(wait_between_cycle,
                   UVM_DEFAULT | UVM_NOPACK | UVM_NOCOMPARE)
  `uvm_object_utils_end

  function new(string name = "hbus_transaction");
    super.new(name);
  endfunction

endclass : hbus_transaction
