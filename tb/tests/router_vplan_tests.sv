//------------------------------------------------------------------------------
// Verification-plan-oriented test library
//
// Tests select a scenario and set only scenario-level knobs.  VIP details are
// owned by interface sequences; cross-interface scheduling is owned by the
// selected virtual sequence.
//------------------------------------------------------------------------------

class router_vplan_test_base extends base_test;

  `uvm_component_utils(router_vplan_test_base)

  function new(string name = "router_vplan_test_base",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    // Clock/reset remains a reusable VIP default sequence.  Channel response
    // sequences are not defaults here; each virtual sequence starts exactly
    // the responders required by its scenario.
    uvm_config_wrapper::set(
      this,
      "tb.clock_and_reset.agent.sequencer.run_phase",
      "default_sequence",
      clk10_rst5_seq::get_type()
    );
    super.build_phase(phase);
  endfunction

  virtual task run_scenario();
    `uvm_fatal(get_type_name(), "Derived test must implement run_scenario()")
  endtask

  task run_phase(uvm_phase phase);
    super.run_phase(phase);
    phase.raise_objection(this, get_type_name());
    run_scenario();
    // Allow the final monitor publications and coverage samples to drain.
    #1000ns;
    phase.drop_objection(this, get_type_name());
  endtask

endclass : router_vplan_test_base


class router_smoke_test extends router_vplan_test_base;
  `uvm_component_utils(router_smoke_test)

  function new(string name = "router_smoke_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_scenario();
    router_smoke_vseq scenario;
    scenario = router_smoke_vseq::type_id::create("scenario");
    scenario.packet_length = 6'd5;
    scenario.check_default_registers = 1;
    scenario.start(tb.mcsequencer);
  endtask
endclass


class router_routing_test extends router_vplan_test_base;
  `uvm_component_utils(router_routing_test)

  function new(string name = "router_routing_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_one_length(bit [5:0] packet_length);
    router_routing_vseq scenario;
    scenario = router_routing_vseq::type_id::create(
      $sformatf("scenario_len_%0d", packet_length)
    );
    scenario.packets_per_address = 2;
    scenario.packet_length       = packet_length;
    scenario.pressure_mode       = ROUTER_PRESSURE_NONE;
    scenario.address_pattern.push_back(2'd0);
    scenario.address_pattern.push_back(2'd0);
    scenario.address_pattern.push_back(2'd1);
    scenario.address_pattern.push_back(2'd2);
    scenario.address_pattern.push_back(2'd1);
    scenario.address_pattern.push_back(2'd0);
    scenario.address_pattern.push_back(2'd2);
    scenario.address_pattern.push_back(2'd0);
    scenario.start(tb.mcsequencer);
  endtask

  task run_scenario();
    // Deterministically close every legal address x length-class target and
    // exercise same-channel as well as channel-switch transitions.
    run_one_length(1);
    run_one_length(8);
    run_one_length(20);
    run_one_length(50);
    run_one_length(63);
  endtask
endclass


class router_length_test extends router_vplan_test_base;
  `uvm_component_utils(router_length_test)

  function new(string name = "router_length_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_one_boundary(int unsigned max_size, bit [1:0] target_addr);
    router_length_control_vseq scenario;
    scenario = router_length_control_vseq::type_id::create(
      $sformatf("scenario_max_%0d", max_size)
    );
    scenario.max_size     = max_size;
    scenario.target_addr  = target_addr;
    scenario.do_readback  = 1;
    scenario.start(tb.mcsequencer);
  endtask


  task run_scenario();
    // Small/medium configuration classes, each with N-1/N/N+1 relation.
    run_one_boundary(20, 0);
    run_one_boundary(40, 1);
    run_one_boundary(62, 2);
  endtask
endclass


class router_error_test extends router_vplan_test_base;
  `uvm_component_utils(router_error_test)

  function new(string name = "router_error_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_one_error(router_error_kind_e error_kind,
                     bit [1:0] target_addr);
    router_error_drop_vseq scenario;
    scenario = router_error_drop_vseq::type_id::create(
      $sformatf("scenario_%0d", error_kind)
    );
    scenario.error_kind  = error_kind;
    scenario.target_addr = target_addr;
    scenario.max_size    = 20;
    scenario.legal_length = 8;
    scenario.start(tb.mcsequencer);
  endtask

  task run_scenario();
    // Router-disabled behavior is kept in its dedicated known-RTL-mismatch
    // regression.  This main error test contains the supported sign-off cases.
    run_one_error(ROUTER_ERROR_BAD_PARITY,      0);
    run_one_error(ROUTER_ERROR_ILLEGAL_ADDRESS, 1);
    run_one_error(ROUTER_ERROR_OVERSIZED,       2);
  endtask
endclass


class router_register_test extends router_vplan_test_base;
  `uvm_component_utils(router_register_test)

  function new(string name = "router_register_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_one_value(bit [7:0] max_size_value, bit [7:0] enable_value);
    router_register_vseq scenario;
    scenario = router_register_vseq::type_id::create(
      $sformatf("scenario_max%0d_en%0h", max_size_value, enable_value)
    );
    scenario.max_size_value = max_size_value;
    scenario.enable_value   = enable_value;
    scenario.start(tb.mcsequencer);
  endtask

  task run_scenario();
    run_one_value(8'd10, 8'h00);
    run_one_value(8'd40, 8'h01);
    run_one_value(8'd63, 8'hf7);
  endtask
endclass


class router_counter_interrupt_test extends router_vplan_test_base;
  `uvm_component_utils(router_counter_interrupt_test)

  function new(string name = "router_counter_interrupt_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_scenario();
    router_counter_interrupt_vseq scenario;
    scenario = router_counter_interrupt_vseq::type_id::create("scenario");
    scenario.check_interrupt_and_clear = 1;
    scenario.start(tb.mcsequencer);
  endtask
endclass


class router_counter_test extends router_vplan_test_base;
  `uvm_component_utils(router_counter_test)

  function new(string name = "router_counter_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_scenario();
    router_counter_interrupt_vseq scenario;
    scenario = router_counter_interrupt_vseq::type_id::create("scenario");
    scenario.check_interrupt_and_clear = 0;
    scenario.start(tb.mcsequencer);
  endtask
endclass


class router_counter_gating_test extends router_vplan_test_base;
  `uvm_component_utils(router_counter_gating_test)

  function new(string name = "router_counter_gating_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_scenario();
    router_counter_gating_vseq scenario;
    scenario = router_counter_gating_vseq::type_id::create("scenario");
    scenario.start(tb.mcsequencer);
  endtask
endclass


class router_reset_test extends router_vplan_test_base;
  `uvm_component_utils(router_reset_test)

  function new(string name = "router_reset_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_scenario();
    router_reset_recovery_vseq idle_reset;

    idle_reset = router_reset_recovery_vseq::type_id::create("idle_reset");
    idle_reset.reset_during_packet = 0;
    idle_reset.start(tb.mcsequencer);
  endtask
endclass


class router_reset_register_test extends router_vplan_test_base;
  `uvm_component_utils(router_reset_register_test)

  function new(string name = "router_reset_register_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_scenario();
    router_reset_registers_vseq scenario;
    scenario = router_reset_registers_vseq::type_id::create("scenario");
    scenario.start(tb.mcsequencer);
  endtask
endclass


// Kept separate because reset during an in-flight transfer needs reset-aware
// monitor/checker handling and is a stronger scenario than ordinary recovery.
class router_reset_in_packet_test extends router_vplan_test_base;
  `uvm_component_utils(router_reset_in_packet_test)

  function new(string name = "router_reset_in_packet_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    uvm_config_int::set(this, "tb.error_checker", "check_enable", 0);
    super.build_phase(phase);
  endfunction

  task run_scenario();
    router_reset_recovery_vseq scenario;
    scenario = router_reset_recovery_vseq::type_id::create("scenario");
    scenario.reset_during_packet = 1;
    scenario.start(tb.mcsequencer);
  endtask
endclass


class router_memory_test extends router_vplan_test_base;
  `uvm_component_utils(router_memory_test)

  function new(string name = "router_memory_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_scenario();
    router_memory_vseq scenario;
    scenario = router_memory_vseq::type_id::create("scenario");
    scenario.start(tb.mcsequencer);
  endtask
endclass


// Passing code-coverage companion for the disabled path implemented by the
// training RTL. This is distinct from the spec-level known-fail test below.
class router_disabled_branch_test extends router_vplan_test_base;
  `uvm_component_utils(router_disabled_branch_test)

  function new(string name = "router_disabled_branch_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_scenario();
    router_disabled_branch_vseq scenario;
    scenario = router_disabled_branch_vseq::type_id::create("scenario");
    scenario.start(tb.mcsequencer);
  endtask
endclass


// Expected to fail with the unmodified training RTL: router_en=0 does not
// globally suppress otherwise legal packets. Kept out of passing regressions.
class router_disable_test extends router_vplan_test_base;
  `uvm_component_utils(router_disable_test)

  function new(string name = "router_disable_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_scenario();
    router_disable_known_fail_vseq scenario;
    scenario = router_disable_known_fail_vseq::type_id::create("scenario");
    scenario.start(tb.mcsequencer);
  endtask
endclass


class router_backpressure_test extends router_vplan_test_base;
  `uvm_component_utils(router_backpressure_test)

  function new(string name = "router_backpressure_test",
               uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_one_pressure(bit [1:0]              target_channel,
                        router_pressure_mode_e pressure_mode,
                        int unsigned           packet_length);
    router_backpressure_vseq scenario;
    scenario = router_backpressure_vseq::type_id::create(
      $sformatf("scenario_ch%0d_pressure%0d", target_channel, pressure_mode)
    );
    scenario.target_channel  = target_channel;
    scenario.pressure_mode   = pressure_mode;
    scenario.traffic_profile = ROUTER_TRAFFIC_BACK_TO_BACK;
    scenario.packet_count    = 3;
    scenario.length_range_override = 1;
    scenario.min_packet_length = packet_length;
    scenario.max_packet_length = packet_length;
    scenario.start(tb.mcsequencer);
  endtask


  task run_scenario();
    // Every output channel sees light/moderate/heavy pressure.  Lengths are
    // rotated so the regression also closes length-class x observed-stall.
    run_one_pressure(0, ROUTER_PRESSURE_LIGHT,    8);
    run_one_pressure(1, ROUTER_PRESSURE_LIGHT,   25);
    run_one_pressure(2, ROUTER_PRESSURE_LIGHT,   50);
    run_one_pressure(0, ROUTER_PRESSURE_MODERATE, 8);
    run_one_pressure(1, ROUTER_PRESSURE_MODERATE,25);
    run_one_pressure(2, ROUTER_PRESSURE_MODERATE,50);
    run_one_pressure(0, ROUTER_PRESSURE_HEAVY,    8);
    run_one_pressure(1, ROUTER_PRESSURE_HEAVY,   25);
    run_one_pressure(2, ROUTER_PRESSURE_HEAVY,   50);
  endtask
endclass


class router_random_test extends router_vplan_test_base;
  `uvm_component_utils(router_random_test)

  function new(string name = "router_random_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task run_scenario();
    router_random_system_vseq scenario;
    scenario = router_random_system_vseq::type_id::create("scenario");
    if (!scenario.randomize() with {
      rounds            == 4;
      packets_per_round == 15;
    })
      `uvm_fatal(get_type_name(), "Unable to randomize random-system scenario")
    scenario.start(tb.mcsequencer);
  endtask
endclass
