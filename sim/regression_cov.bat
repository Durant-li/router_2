@echo off
setlocal enabledelayedexpansion

echo ==================================================
echo YAPP Router UVM Coverage Regression
echo ==================================================

if not exist ..\results mkdir ..\results
if not exist ..\results\logs mkdir ..\results\logs
if not exist ..\results\coverage mkdir ..\results\coverage

echo.
echo [1] Clean work library
if exist work rmdir /s /q work

echo.
echo [2] Create work library
vlib work
vmap work work

echo.
echo [3] Compile design and testbench
vlog -sv -L mtiUvm "+incdir+%UVMHOME%\src" -f flist.f

if errorlevel 1 (
  echo.
  echo COMPILE FAILED. Stop regression.
  exit /b 1
)

echo.
echo [4] Run coverage regression

set TESTS=router_smoke_test router_routing_test router_length_test router_error_test router_register_test router_counter_test router_counter_gating_test router_counter_interrupt_test router_reset_test router_reset_register_test router_reset_in_packet_test router_memory_test router_disabled_branch_test router_backpressure_test router_random_test

for %%T in (%TESTS%) do (
  echo.
  echo --------------------------------------------------
  echo Running test: %%T
  echo --------------------------------------------------

  vsim -c -coverage -L mtiUvm work.hw_top work.tb_top ^
    +UVM_TESTNAME=%%T ^
    +UVM_VERBOSITY=UVM_LOW ^
    -sv_seed random ^
    -l ..\results\logs\%%T_cov.log ^
    -do "coverage save -onexit ../results/coverage/%%T.ucdb; run -all; quit -f"

  if errorlevel 1 (
    echo Test %%T FAILED at simulator level.
    exit /b 1
  )

  

  echo Test %%T completed.
)

echo.
echo [5] Merge UCDB files

vcover merge ..\results\coverage\yapp_merged.ucdb ^
  ..\results\coverage\router_smoke_test.ucdb ^
  ..\results\coverage\router_routing_test.ucdb ^
  ..\results\coverage\router_length_test.ucdb ^
  ..\results\coverage\router_error_test.ucdb ^
  ..\results\coverage\router_register_test.ucdb ^
  ..\results\coverage\router_counter_test.ucdb ^
  ..\results\coverage\router_counter_gating_test.ucdb ^
  ..\results\coverage\router_counter_interrupt_test.ucdb ^
  ..\results\coverage\router_reset_test.ucdb ^
  ..\results\coverage\router_reset_register_test.ucdb ^
  ..\results\coverage\router_reset_in_packet_test.ucdb ^
  ..\results\coverage\router_memory_test.ucdb ^
  ..\results\coverage\router_disabled_branch_test.ucdb ^
  ..\results\coverage\router_backpressure_test.ucdb ^
  ..\results\coverage\router_random_test.ucdb

if errorlevel 1 (
  echo UCDB merge failed.
  exit /b 1
)

echo.
echo [6] Generate text coverage report

vcover report -details -output ..\results\coverage\yapp_merged_report.txt ..\results\coverage\yapp_merged.ucdb

echo.
echo ==================================================
echo Coverage regression completed successfully.
echo Logs:     ..\results\logs
echo Coverage: ..\results\coverage
echo ==================================================

endlocal
