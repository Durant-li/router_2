// Router-project HBUS interface.
//
// The DUT is the only HBUS slave, so this interface implements only the
// single-master transfers required by the verification plan. All stimulus is
// driven on the falling edge and sampled by the DUT/monitor on the rising edge.

interface hbus_if (input logic clock, input logic reset);

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import hbus_pkg::*;

  logic        hen;
  logic        hwr_rd;
  logic [15:0] haddr;
  logic [7:0]  hdata;

  // Resolve the master's write data and the DUT's read data on one bus.
  wire [7:0] hdata_w;
  assign hdata_w = hdata;

  task automatic drive_idle();
    hen    <= 1'b0;
    hwr_rd <= 1'b0;
    haddr  <= 'z;
    hdata  <= 'z;
  endtask

  task automatic drive_transfer(
    input bit [15:0]           address,
    input hbus_read_write_enum direction,
    inout bit [7:0]            data_value,
    input int unsigned         idle_cycles
  );
    repeat (idle_cycles) @(negedge clock);

    @(negedge clock);
    if (reset === 1'b1)
      return;

    hen    <= 1'b1;
    haddr  <= address;
    hwr_rd <= (direction == HBUS_WRITE);

    if (direction == HBUS_WRITE) begin
      hdata <= data_value;
      @(negedge clock);
    end
    else begin
      hdata <= 'z;
      // The DUT read protocol keeps HEN active for two clock cycles.
      repeat (2) @(negedge clock);
      data_value = hdata_w;
    end

    drive_idle();
  endtask

  task automatic monitor_transfer(
    output bit [15:0]           address,
    output hbus_read_write_enum direction,
    output bit [7:0]            data_value,
    output bit                  completed
  );
    bit transfer_done;

    transfer_done = 1'b0;
    completed     = 1'b0;

    fork
      begin : collect_thread
        @(posedge clock iff ((reset === 1'b0) && (hen === 1'b1)));

        address   = haddr;
        direction = hwr_rd ? HBUS_WRITE : HBUS_READ;

        if (direction == HBUS_WRITE)
          data_value = hdata;
        else begin
          // Read data is valid in the second enabled cycle.
          @(posedge clock);
          data_value = hdata_w;
        end

        transfer_done = 1'b1;
      end

      begin : reset_thread
        @(posedge reset);
      end
    join_any
    disable fork;

    completed = transfer_done;
  endtask

endinterface : hbus_if
