/*-----------------------------------------------------------------
File name     : router_fifo_scoreboard.sv
Developers    : Kathleen Meade, Brian Dickinson
Created       : 01/04/11
Description   : lab09_sbd router scoreboard using analysis fifos
Notes         : From the Cadence "SystemVerilog Accelerated Verification with UVM" training
-------------------------------------------------------------------
Copyright Cadence Design Systems (c)2015
-----------------------------------------------------------------*/
//------------------------------------------------------------------------------
//
// CLASS: router_scoreboard
//
//------------------------------------------------------------------------------

// Implementation:
// update_regr() :
//   Scoreboard executes blocking get on HBUS transaction analysis FIFO.
//   When HBUS write transaction is received, scoreboard updates local enable/max packet registers
// check_packet() :
//   Scoreboard executes blocking get on YAPP packet analysis FIFO
//   When YAPP packet is received, scoreboard checks validity:
//     - Address is not 3
//     - Local enable register is high
//     - Packet length < local max packet register 
//   If packet valid, scoreboard checks address; executes blocking get on matching channel analysis FIFO and compares packets
// update_regr() and check_packet() are run concurrently (with fork-join) 
//   as HBUS transactions and YAPP packets can be received simultaneously


// enum type for comparer policy 
typedef enum bit {EQUALITY, UVM} comp_t;

class router_fifo_scoreboard extends uvm_scoreboard;

   // analysis fifo components
   uvm_tlm_analysis_fifo #(yapp_packet) yapp_fifo;
   uvm_tlm_analysis_fifo #(channel_packet) chan0_fifo, chan1_fifo, chan2_fifo;
   uvm_tlm_analysis_fifo #(hbus_transaction) hbus_fifo;

   // Semantic coverage is published after the scoreboard has associated the
   // relevant state and transactions.  Coverage does not need to guess timing
   // relationships between independent monitor streams.
   uvm_analysis_port #(router_decision_cov_item) decision_cov_port;
   uvm_analysis_port #(router_route_cov_item)    route_cov_port;
   
   // Reset interface for reset-aware scoreboard flushing
   virtual clock_and_reset_if clk_rst_vif;
   bit reset_aware = 1;

   // variable for comparer policy 
   comp_t compare_policy = UVM; 
   
   // Scoreboard Statistics
   int packets_in = 0;
   int packets_ch [2:0];
   int compare_ch [2:0];
   int miscompare_ch [2:0];
   int packets_dropped   = 0;
   int packets_valid     = 0;
   int jumbo_packets     = 0;
   int bad_addr_packets  = 0;
   int disabled_packets  = 0;

   // Router registers
   bit [7:0] max_pktsize_reg = 8'h3F;
   bit 		 router_enable_reg = 1'b1;
   int unsigned reset_epoch;


   // Constructor
   function new(string name="", uvm_component parent=null);
     super.new(name, parent);
     yapp_fifo = new("yapp_fifo", this);
     chan0_fifo = new("chan0_fifo", this);
     chan1_fifo = new("chan1_fifo", this);
     chan2_fifo = new("chan2_fifo", this);
     hbus_fifo = new("hbus_fifo", this);
     decision_cov_port = new("decision_cov_port", this);
     route_cov_port    = new("route_cov_port", this);
   endfunction
   
   function void build_phase(uvm_phase phase);
	 super.build_phase(phase);

     void'(uvm_config_db#(virtual clock_and_reset_if)::get(this, "","clk_rst_vif",clk_rst_vif));

     void'(uvm_config_int::get(this,"","reset_aware",reset_aware));
   endfunction : build_phase
      
   `uvm_component_utils_begin(router_fifo_scoreboard)
     `uvm_field_enum(comp_t, compare_policy, UVM_ALL_ON)
   `uvm_component_utils_end
   
   // custom packet compare function using inequality operators
   function bit comp_equal (input yapp_packet yp, input channel_packet cp);
      // returns first mismatch only
      if (yp.addr != cp.addr) begin
        `uvm_error("PKT_COMPARE",$sformatf("Address mismatch YAPP %0d Chan %0d",yp.addr,cp.addr))
        return(0);
      end
      if (yp.length != cp.length) begin
        `uvm_error("PKT_COMPARE",$sformatf("Length mismatch YAPP %0d Chan %0d",yp.length,cp.length))
        return(0);
      end
      foreach (yp.payload [i])
        if (yp.payload[i] != cp.payload[i]) begin
          `uvm_error("PKT_COMPARE",$sformatf("Payload[%0d] mismatch YAPP %0d Chan %0d",i,yp.payload[i],cp.payload[i]))
          return(0);
        end
      if (yp.parity != cp.parity) begin
        `uvm_error("PKT_COMPARE",$sformatf("Parity mismatch YAPP %0d Chan %0d",yp.parity,cp.parity))
        return(0);
      end
      return(1);
   endfunction

   // custom packet compare function using uvm_comparer methods
  function bit comp_uvm(input yapp_packet yp, input channel_packet cp, uvm_comparer comparer = null);
    string str;
    if (comparer == null)
      comparer = new();
    comp_uvm = comparer.compare_field("addr", yp.addr, cp.addr,2);
    comp_uvm &= comparer.compare_field("length", yp.length, cp.length,6);
    foreach (yp.payload [i]) begin
      str.itoa(i);
      comp_uvm &= comparer.compare_field({"payload[",str,"]"}, yp.payload[i], cp.payload[i],8);
    end
    comp_uvm &= comparer.compare_field("parity", yp.parity, cp.parity,8);
  endfunction

  function router_length_relation_e get_length_relation(
    int unsigned packet_length,
    int unsigned configured_max
  );
    if (packet_length < configured_max)
      return ROUTER_LEN_BELOW_MAX;
    else if (packet_length == configured_max)
      return ROUTER_LEN_EQUAL_MAX;
    else
      return ROUTER_LEN_ABOVE_MAX;
  endfunction

  function void publish_decision_event(
    yapp_packet          pkt,
    bit                  valid,
    router_drop_reason_e drop_reason
  );
    router_decision_cov_item event_item;

    event_item = router_decision_cov_item::type_id::create("decision_event");
    event_item.request_addr       = pkt.addr;
    event_item.packet_length      = pkt.length;
    event_item.parity_type        = pkt.parity_type;

    // These two values are the configuration snapshot for this packet.  They
    // are copied now, so a later HBUS write cannot change the sampled meaning.
    event_item.enable_at_accept   = router_enable_reg;
    event_item.max_size_at_accept = max_pktsize_reg;
    event_item.length_relation    =
      get_length_relation(pkt.length, max_pktsize_reg);
    event_item.expected_action = valid ? ROUTER_ACTION_FORWARDED
                                       : ROUTER_ACTION_DROPPED;
    event_item.drop_reason = drop_reason;
    decision_cov_port.write(event_item);
  endfunction

  function void publish_route_event(
    yapp_packet    expected_pkt,
    channel_packet actual_pkt,
    bit            compare_pass
  );
    router_route_cov_item event_item;

    event_item = router_route_cov_item::type_id::create("route_event");
    event_item.request_addr     = expected_pkt.addr;
    event_item.expected_channel = expected_pkt.addr;
    event_item.actual_channel   = actual_pkt.observed_channel;
    event_item.packet_length    = expected_pkt.length;
    event_item.compare_pass     = compare_pass;
    route_cov_port.write(event_item);
  endfunction
  
  function void flush_scoreboard_fifos();

     yapp_fifo.flush();
     hbus_fifo.flush();

     chan0_fifo.flush();
     chan1_fifo.flush();
     chan2_fifo.flush();

    `uvm_info(get_type_name(), "Scoreboard FIFOs flushed due to reset",UVM_LOW)
endfunction : flush_scoreboard_fifos


   task run_phase(uvm_phase phase);

     fork
       check_packet();
       update_regr();
	   
	   if (reset_aware && (clk_rst_vif != null)) begin
			monitor_reset_flush();
		end
     join
   endtask 

   task update_regr();
     hbus_transaction hb;
     forever begin
       // get transaction from hbus
       hbus_fifo.get_peek_export.get(hb);
       `uvm_info(get_type_name(), $sformatf("Scoreboard: Received HBUS Transaction: \n%s", hb.sprint()), UVM_MEDIUM)
       // capture the max_pktsize_reg and router_enable_reg
       // values whenever a hbus transaction is written
       if (hb.hwr_rd == HBUS_WRITE)
         case (hb.haddr)
           'h1000 : max_pktsize_reg = hb.hdata;
           'h1001 : router_enable_reg = hb.hdata[0];
         endcase
     end 
   endtask
     
   task check_packet();
     yapp_packet yapp_pkt;
     channel_packet chan_pkt;
     bit valid;
     bit pktcompare;
     bit got_channel_packet;
     logic [1:0] paddr;
     int unsigned packet_epoch;
     router_drop_reason_e drop_reason;
     forever begin
       do begin
         // get packet from yapp
         yapp_fifo.get_peek_export.get(yapp_pkt);
         packet_epoch = reset_epoch;
         `uvm_info(get_type_name(), $sformatf("Scoreboard: Packet got from yapp analysis fifo\n%s",yapp_pkt.sprint()), UVM_MEDIUM)
         packets_in++;
         // check validity
         valid = 1'b1;
         drop_reason = ROUTER_DROP_NONE;
         if (yapp_pkt.addr == 3) begin
           bad_addr_packets++;
           packets_dropped++;
           `uvm_info(get_type_name(), "Scoreboard: YAPP Packet Dropped [BAD ADDRESS]", UVM_LOW)
           valid = 1'b0;
           drop_reason = ROUTER_DROP_BAD_ADDRESS;
         end
         else if ((router_enable_reg == 1) && (yapp_pkt.length > max_pktsize_reg))begin
           jumbo_packets++;
           packets_dropped++;
           `uvm_info(get_type_name(), "Scoreboard: YAPP Packet Dropped [OVERSIZED]", UVM_LOW)
           valid = 1'b0;
           drop_reason = ROUTER_DROP_OVERSIZED;
         end
         else if (router_enable_reg == 0) begin
           disabled_packets++;
           packets_dropped++;
           `uvm_info(get_type_name(), "Scoreboard: YAPP Packet Dropped [DISABLED]", UVM_LOW)
           valid = 1'b0;
           drop_reason = ROUTER_DROP_DISABLED;
         end

         publish_decision_event(yapp_pkt, valid, drop_reason);
       end
       while (valid == 1'b0);
       paddr = yapp_pkt.addr;

       // A reset can invalidate an expected packet while this thread is
       // blocked on an output FIFO.  Race the output get against the reset
       // epoch; FIFO flush alone cannot remove a transaction already held in
       // this task's local variable.
       got_channel_packet = 0;
       if (reset_aware && (clk_rst_vif != null)) begin
         fork : channel_or_reset
           begin
             case (yapp_pkt.addr)
               0 : chan0_fifo.get_peek_export.get(chan_pkt);
               1 : chan1_fifo.get_peek_export.get(chan_pkt);
               2 : chan2_fifo.get_peek_export.get(chan_pkt);
             endcase
             got_channel_packet = 1;
           end
           begin
             wait (reset_epoch != packet_epoch);
           end
         join_any
         disable channel_or_reset;

         if (reset_epoch != packet_epoch)
           got_channel_packet = 0;
       end
       else begin
         case (yapp_pkt.addr)
           0 : chan0_fifo.get_peek_export.get(chan_pkt);
           1 : chan1_fifo.get_peek_export.get(chan_pkt);
           2 : chan2_fifo.get_peek_export.get(chan_pkt);
         endcase
         got_channel_packet = 1;
       end

       if (!got_channel_packet) begin
         `uvm_info(get_type_name(),
                   "Reset invalidated an in-flight expected packet",
                   UVM_LOW)
         continue;
       end

       packets_valid++;
       packets_ch[yapp_pkt.addr]++;
       `uvm_info(get_type_name(), "Scoreboard: Packet got from chan analysis fifo", UVM_LOW)
       // compare packets
       if (compare_policy == UVM)
         // use custom comparer with UVM methods
         pktcompare =  comp_uvm(yapp_pkt, chan_pkt);
       else
         // use custom comparer with equality operators
         pktcompare =  comp_equal(yapp_pkt, chan_pkt);

       publish_route_event(yapp_pkt, chan_pkt, pktcompare);
    
       if( pktcompare ) begin
          `uvm_info(get_type_name(), $sformatf("Scoreboard Compare Match: Channel_%0d", paddr), UVM_LOW)
          `uvm_info(get_type_name(), $sformatf("Scoreboard Matched Packet: \n%s", chan_pkt.sprint()), UVM_MEDIUM)
          compare_ch[paddr]++;
       end
       else begin
          `uvm_warning(get_type_name(), $sformatf("Scoreboard Error [MISCOMPARE]: Received Channel Packet:\n%s\nExpected YAPP Packet:\n%s", chan_pkt.sprint(), yapp_pkt.sprint()))
           miscompare_ch[paddr]++;
       end
     end // forever
   endtask : check_packet 
   
   
task monitor_reset_flush();

  forever begin

    @(posedge clk_rst_vif.reset);

    `uvm_info(get_type_name(),
              "Reset asserted: flushing scoreboard FIFOs",
              UVM_LOW)

    reset_epoch++;

    flush_scoreboard_fifos();

    // Reset also starts a new configuration epoch in the DUT.
    max_pktsize_reg   = 8'h3f;
    router_enable_reg = 1'b1;

    @(negedge clk_rst_vif.reset);

    // Give monitors a few cycles to settle after reset release.
    repeat (5) @(posedge clk_rst_vif.clock);

    flush_scoreboard_fifos();

  end

endtask : monitor_reset_flush


// UVM check_phase
function void check_phase(uvm_phase phase);
  `uvm_info(get_type_name(), "Scoreboard: Checking Router Scoreboard", UVM_LOW)
  if (yapp_fifo.is_empty() && chan0_fifo.is_empty() && chan1_fifo.is_empty() && chan2_fifo.is_empty())
   `uvm_info(get_type_name(), "Check:\n\n   Router Scoreboard Empty!\n", UVM_LOW)
  else
  `uvm_error(get_type_name(), $sformatf( { "Check:\n\nWARNING: Router Scoreboard FIFO's NOT Empty:\n", 
    "     YAPP : %0d     Chan0 : %0d     Chan1 : %0d     Chan2 : %0d" } , 
    yapp_fifo.size(), chan0_fifo.size(), chan1_fifo.size(), chan2_fifo.size()))
endfunction : check_phase

// UVM report() phase
function void report_phase(uvm_phase phase);
  `uvm_info(get_type_name(), $sformatf( { "Report:\n\n   Scoreboard: Packet Statistics \n     " , 
    "     Packets In:\t%0d\n" , 
    "     Packets Dropped:\t%0d\n" , 
    "       - Address 3 packets:\t%0d\n" ,
    "       - Oversized packets:\t%0d\n" ,
    "       - Disabled packets:\t%0d\n" ,
    "     Packets Valid:\t%0d\n\n" , 
    "     Channel 0 Total: %0d  Pass: %0d  Miscompare: %0d\n" , 
    "     Channel 1 Total: %0d  Pass: %0d  Miscompare: %0d\n" , 
    "     Channel 2 Total: %0d  Pass: %0d  Miscompare: %0d\n\n" }, 
    packets_in, packets_dropped, bad_addr_packets, jumbo_packets, disabled_packets, packets_valid,
    packets_ch[0], compare_ch[0], miscompare_ch[0], 
    packets_ch[1], compare_ch[1], miscompare_ch[1], 
    packets_ch[2], compare_ch[2], miscompare_ch[2]), UVM_LOW)
  if ((miscompare_ch[0] + miscompare_ch[1] + miscompare_ch[2]) > 0)
    `uvm_error(get_type_name(),"Status:\n\nSimulation FAILED\n")
  else
    `uvm_info(get_type_name(),"Status:\n\nSimulation PASSED\n", UVM_NONE)
endfunction : report_phase

endclass : router_fifo_scoreboard
       
