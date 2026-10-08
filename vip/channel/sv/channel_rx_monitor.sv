// Reconstructs output packets and records the backpressure actually observed.
// Project functional coverage consumes these transactions in router_coverage.
class channel_rx_monitor extends uvm_monitor;

  int unsigned channel_id;

  `uvm_component_utils_begin(channel_rx_monitor)
    `uvm_field_int(channel_id, UVM_DEFAULT)
  `uvm_component_utils_end

  virtual channel_if vif;
  int unsigned num_packets;

  uvm_analysis_port #(channel_packet) item_collected_port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!channel_vif_config::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", {"Channel virtual interface is not set for ",
                            get_full_name()})
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      channel_packet packet;
      bit completed;

      wait (vif.reset === 1'b0);
      packet = channel_packet::type_id::create("packet", this);
      packet.observed_channel = channel_id;

      vif.monitor_packet(packet.length,
                         packet.addr,
                         packet.payload,
                         packet.parity,
                         packet.stall_cycles,
                         completed);

      // A reset can abort an in-flight collection. Partial packets are not
      // protocol transactions and must never reach scoreboard or coverage.
      if (!completed)
        continue;

      packet.parity_type =
        (packet.parity == packet.calc_parity()) ? GOOD_PARITY : BAD_PARITY;

      if (packet.addr != channel_id)
        `uvm_error("CHANNEL_ID",
                   $sformatf("packet address %0d observed on channel %0d",
                             packet.addr, channel_id))

      item_collected_port.write(packet);
      num_packets++;
      `uvm_info(get_type_name(),
                {"Observed output packet:\n", packet.sprint()},
                UVM_HIGH)
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(),
              $sformatf("Channel %0d monitor collected %0d packets",
                        channel_id, num_packets),
              UVM_LOW)
  endfunction

endclass : channel_rx_monitor
