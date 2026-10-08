@echo off

echo ============================================================
echo Running known-fail tests
echo These tests are expected to expose RTL/spec mismatches.
echo They are NOT part of main passing regression.
echo ============================================================

vsim -c -coverage -L mtiUvm work.hw_top work.tb_top ^
  +UVM_TESTNAME=router_disable_test ^
  +UVM_VERBOSITY=UVM_LOW ^
  -sv_seed 12345 ^
  -l ..\results\logs\router_disable_test_known_fail.log ^
  -do "run -all; quit -f"