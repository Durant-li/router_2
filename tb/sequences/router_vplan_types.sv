//------------------------------------------------------------------------------
// Router verification-plan semantic types
//
// These types describe verification intent rather than pin-level protocol
// details.  Tests and virtual sequences use the scenario enums as high-level
// knobs; the scoreboard publishes the coverage event objects after it has
// correlated monitor transactions.
//------------------------------------------------------------------------------

typedef enum int {
  ROUTER_TRAFFIC_NORMAL_RANDOM,
  ROUTER_TRAFFIC_BACK_TO_BACK,
  ROUTER_TRAFFIC_LONG_PACKET,
  ROUTER_TRAFFIC_SAME_CHANNEL,
  ROUTER_TRAFFIC_MULTI_CHANNEL
} router_traffic_profile_e;

typedef enum int {
  ROUTER_ERROR_NONE,
  ROUTER_ERROR_BAD_PARITY,
  ROUTER_ERROR_ILLEGAL_ADDRESS,
  ROUTER_ERROR_OVERSIZED,
  ROUTER_ERROR_DISABLED
} router_error_kind_e;

typedef enum int {
  ROUTER_PRESSURE_NONE,
  ROUTER_PRESSURE_LIGHT,
  ROUTER_PRESSURE_MODERATE,
  ROUTER_PRESSURE_HEAVY
} router_pressure_mode_e;

typedef enum int {
  ROUTER_RESET_IDLE,
  ROUTER_RESET_IN_PACKET
} router_reset_context_e;

typedef enum int {
  ROUTER_LEN_BELOW_MAX,
  ROUTER_LEN_EQUAL_MAX,
  ROUTER_LEN_ABOVE_MAX
} router_length_relation_e;

typedef enum int {
  ROUTER_ACTION_FORWARDED,
  ROUTER_ACTION_DROPPED
} router_packet_action_e;

typedef enum int {
  ROUTER_DROP_NONE,
  ROUTER_DROP_BAD_ADDRESS,
  ROUTER_DROP_OVERSIZED,
  ROUTER_DROP_DISABLED
} router_drop_reason_e;


// One event is emitted for every packet decision.  Configuration fields are
// snapshots: they are copied when the input packet is consumed by the
// scoreboard and therefore remain associated with that packet even if HBUS
// changes the live configuration later.
class router_decision_cov_item extends uvm_object;

  bit [1:0]                request_addr;
  int unsigned             packet_length;
  yapp_pkg::parity_t       parity_type;
  bit                      enable_at_accept;
  int unsigned             max_size_at_accept;
  router_length_relation_e length_relation;
  router_packet_action_e   expected_action;
  router_drop_reason_e     drop_reason;

  `uvm_object_utils_begin(router_decision_cov_item)
    `uvm_field_int(request_addr,       UVM_ALL_ON)
    `uvm_field_int(packet_length,      UVM_ALL_ON)
    `uvm_field_enum(yapp_pkg::parity_t, parity_type, UVM_ALL_ON)
    `uvm_field_int(enable_at_accept,   UVM_ALL_ON)
    `uvm_field_int(max_size_at_accept, UVM_ALL_ON)
    `uvm_field_enum(router_length_relation_e, length_relation, UVM_ALL_ON)
    `uvm_field_enum(router_packet_action_e, expected_action, UVM_ALL_ON)
    `uvm_field_enum(router_drop_reason_e, drop_reason, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "router_decision_cov_item");
    super.new(name);
  endfunction

endclass : router_decision_cov_item


// Emitted only after the scoreboard has associated an input packet with the
// corresponding output transaction.  This event is the safe place to combine
// request-side and response-side information.
class router_route_cov_item extends uvm_object;

  bit [1:0]    request_addr;
  int unsigned expected_channel;
  int unsigned actual_channel;
  int unsigned packet_length;
  bit          compare_pass;

  `uvm_object_utils_begin(router_route_cov_item)
    `uvm_field_int(request_addr,     UVM_ALL_ON)
    `uvm_field_int(expected_channel, UVM_ALL_ON)
    `uvm_field_int(actual_channel,   UVM_ALL_ON)
    `uvm_field_int(packet_length,    UVM_ALL_ON)
    `uvm_field_int(compare_pass,     UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "router_route_cov_item");
    super.new(name);
  endfunction

endclass : router_route_cov_item

