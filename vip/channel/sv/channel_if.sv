// Router output-channel interface.
// suspend=1 applies backpressure; suspend=0 allows the DUT FIFO to advance.

interface channel_if (input logic clock, input logic reset);

  logic       data_vld;
  logic       suspend;
  logic [7:0] data;

  task automatic drive_response(input int unsigned stall_cycles);
    fork
      begin : response_thread
        @(negedge clock iff data_vld === 1'b1);

        repeat (stall_cycles) begin
          suspend <= 1'b1;
          @(negedge clock);
        end

        suspend <= 1'b0;
        @(negedge clock iff data_vld === 1'b0);
        suspend <= 1'b1;
      end

      begin : reset_thread
        @(posedge reset);
        suspend <= 1'b1;
      end
    join_any
    disable fork;
  endtask

  task automatic monitor_packet(
    output bit [5:0]      length,
    output bit [1:0]      addr,
    output bit [7:0]      payload[],
    output bit [7:0]      parity,
    output int unsigned   observed_stall_cycles,
    output bit            completed
  );
    bit packet_done;

    packet_done           = 1'b0;
    completed             = 1'b0;
    observed_stall_cycles = 0;

    fork
      begin : collect_thread
        // Start timing as soon as a packet is visible, including the cycles
        // for which the receiver keeps suspend asserted.
        @(posedge clock iff data_vld === 1'b1);
        while ((data_vld === 1'b1) && (suspend === 1'b1)) begin
          observed_stall_cycles++;
          @(posedge clock);
        end

        // The FIFO is synchronous. The first non-stalled edge advances the
        // header to data; sample it on the following edge.
        @(posedge clock iff suspend === 1'b0);
        {length, addr} = data;
        payload = new[length];

        for (int i = 0; i < length; i++) begin
          @(posedge clock iff suspend === 1'b0);
          payload[i] = data;
        end

        @(posedge clock);
        parity = data;
        packet_done = 1'b1;
      end

      begin : reset_thread
        @(posedge reset);
      end
    join_any
    disable fork;

    completed = packet_done;
  endtask

endinterface : channel_if
