// A single configurable response primitive plus small named profiles.

class channel_rx_profile_seq extends uvm_sequence #(channel_resp);

  `uvm_object_utils(channel_rx_profile_seq)
  `uvm_declare_p_sequencer(channel_rx_sequencer)

  rand int unsigned delay_min;
  rand int unsigned delay_max;
  rand int unsigned response_count;

  // response_count=0 means a background responder that runs forever.
  constraint profile_c {
    delay_min <= delay_max;
    delay_max <= 100;
    response_count <= 200;
  }

  function new(string name = "channel_rx_profile_seq");
    super.new(name);
    delay_min      = 0;
    delay_max      = 7;
    response_count = 0;
  endfunction

  protected task send_one_response();
    channel_resp response;

    @(posedge p_sequencer.vif.clock
      iff p_sequencer.vif.data_vld === 1'b1);

    response = channel_resp::type_id::create("response");
    start_item(response);
    if (!response.randomize() with {
          resp_delay inside {[local::delay_min:local::delay_max]};
        })
      `uvm_fatal(get_type_name(), "Unable to randomize channel response")
    finish_item(response);
  endtask

  task body();
    if (response_count == 0)
      forever send_one_response();
    else
      repeat (response_count) send_one_response();
  endtask

endclass : channel_rx_profile_seq


// Default randomized response used by legacy background tests.
class channel_rx_resp_seq extends channel_rx_profile_seq;
  `uvm_object_utils(channel_rx_resp_seq)
  function new(string name = "channel_rx_resp_seq");
    super.new(name);
    delay_min = 0;
    delay_max = 7;
  endfunction
endclass


class channel_rx_long_resp_seq extends channel_rx_profile_seq;
  `uvm_object_utils(channel_rx_long_resp_seq)
  function new(string name = "channel_rx_long_resp_seq");
    super.new(name);
    delay_min = 0;
    delay_max = 65;
  endfunction
endclass


class channel_rx_moderate_resp_seq extends channel_rx_profile_seq;
  `uvm_object_utils(channel_rx_moderate_resp_seq)
  function new(string name = "channel_rx_moderate_resp_seq");
    super.new(name);
    delay_min = 5;
    delay_max = 15;
  endfunction
endclass


class channel_rx_strong_backpressure_seq extends channel_rx_profile_seq;
  `uvm_object_utils(channel_rx_strong_backpressure_seq)
  function new(string name = "channel_rx_strong_backpressure_seq");
    super.new(name);
    delay_min = 18;
    delay_max = 25;
  endfunction
endclass


// Finite form used by virtual sequences so fork...join has a clean endpoint.
class channel_rx_configurable_resp_seq extends channel_rx_profile_seq;
  `uvm_object_utils(channel_rx_configurable_resp_seq)
  function new(string name = "channel_rx_configurable_resp_seq");
    super.new(name);
    delay_min      = 0;
    delay_max      = 0;
    response_count = 1;
  endfunction
endclass
