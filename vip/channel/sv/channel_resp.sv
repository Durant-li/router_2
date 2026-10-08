// One receiver response: hold suspend for resp_delay output clock cycles.
class channel_resp extends uvm_sequence_item;

  rand int unsigned resp_delay;

  constraint delay_c { resp_delay inside {[0:100]}; }

  `uvm_object_utils_begin(channel_resp)
    `uvm_field_int(resp_delay, UVM_DEFAULT | UVM_DEC)
  `uvm_object_utils_end

  function new(string name = "channel_resp");
    super.new(name);
  endfunction

endclass : channel_resp
