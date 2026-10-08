@echo off
setlocal enabledelayedexpansion

echo ============================================================
echo YAPP Router Code Coverage Regression
echo ============================================================

set TESTS=router_smoke_test router_routing_test router_length_test router_error_test router_register_test router_counter_test router_counter_gating_test router_counter_interrupt_test router_reset_test router_reset_register_test router_reset_in_packet_test router_memory_test router_disabled_branch_test router_backpressure_test router_random_test

echo.
echo [1] Clean work library
if exist work rmdir /s /q work

echo.
echo [2] Clean old code coverage results
if not exist ..\results\code_coverage mkdir ..\results\code_coverage
if not exist ..\results\logs mkdir ..\results\logs

if exist ..\results\logs\*_codecov.log del /q ..\results\logs\*_codecov.log
if exist ..\results\code_coverage\*.ucdb del /q ..\results\code_coverage\*.ucdb
if exist ..\results\code_coverage\codecov_report.txt del /q ..\results\code_coverage\codecov_report.txt
if exist ..\results\code_coverage\codecov_detail_full.txt del /q ..\results\code_coverage\codecov_detail_full.txt
if exist ..\results\code_coverage\html rmdir /s /q ..\results\code_coverage\html
if exist ..\results\code_coverage\html_detail rmdir /s /q ..\results\code_coverage\html_detail

echo.
echo [3] Create work library
vlib work
vmap work work

echo.
echo [4.1] Compile DUT with code coverage enabled
vlog -sv -cover bcesft ../rtl/yapp_router.sv

echo.
echo [4.2] Compile VIP and TB without code coverage
vlog -sv -L mtiUvm "+incdir+%UVMHOME%\src" -f flist_tb_only.f

if errorlevel 1 (
  echo.
  echo Compile failed.
  exit /b 1
)

echo.
echo [5] Run tests with coverage enabled

for %%T in (%TESTS%) do (
  echo.
  echo ------------------------------------------------------------
  echo Running test: %%T
  echo ------------------------------------------------------------

  vsim -c -coverage -L mtiUvm work.hw_top work.tb_top ^
    +UVM_TESTNAME=%%T ^
    +UVM_VERBOSITY=UVM_LOW ^
    -sv_seed random ^
    -l ..\results\logs\%%T_codecov.log ^
    -do "coverage save -onexit ../results/code_coverage/%%T_code.ucdb; run -all; quit -f"

  if errorlevel 1 (
    echo.
    echo Test %%T failed.
    exit /b 1
  )
)

echo.
echo [5.1] Run random stress tests with multiple seeds

for %%S in (11 22 33) do (
  echo.
  echo ------------------------------------------------------------
  echo Running router_random_test seed %%S
  echo ------------------------------------------------------------

  vsim -c -coverage -L mtiUvm work.hw_top work.tb_top ^
    +UVM_TESTNAME=router_random_test ^
    +UVM_VERBOSITY=UVM_LOW ^
    -sv_seed %%S ^
    -l ..\results\logs\router_random_test_seed%%S_codecov.log ^
    -do "coverage save -onexit ../results/code_coverage/router_random_test_seed%%S_code.ucdb; run -all; quit -f"

  if errorlevel 1 (
    echo.
    echo router_random_test seed %%S failed.
    exit /b 1
  )
)

echo.
echo [6] Merge UCDB files

vcover merge ..\results\code_coverage\yapp_code_merged.ucdb ^
  ..\results\code_coverage\router_smoke_test_code.ucdb ^
  ..\results\code_coverage\router_routing_test_code.ucdb ^
  ..\results\code_coverage\router_length_test_code.ucdb ^
  ..\results\code_coverage\router_error_test_code.ucdb ^
  ..\results\code_coverage\router_register_test_code.ucdb ^
  ..\results\code_coverage\router_counter_test_code.ucdb ^
  ..\results\code_coverage\router_counter_gating_test_code.ucdb ^
  ..\results\code_coverage\router_counter_interrupt_test_code.ucdb ^
  ..\results\code_coverage\router_reset_test_code.ucdb ^
  ..\results\code_coverage\router_reset_register_test_code.ucdb ^
  ..\results\code_coverage\router_reset_in_packet_test_code.ucdb ^
  ..\results\code_coverage\router_memory_test_code.ucdb ^
  ..\results\code_coverage\router_disabled_branch_test_code.ucdb ^
  ..\results\code_coverage\router_backpressure_test_code.ucdb ^
  ..\results\code_coverage\router_random_test_code.ucdb ^
  ..\results\code_coverage\router_random_test_seed11_code.ucdb ^
  ..\results\code_coverage\router_random_test_seed22_code.ucdb ^
  ..\results\code_coverage\router_random_test_seed33_code.ucdb
  
if errorlevel 1 (
  echo.
  echo UCDB merge failed.
  exit /b 1
)

echo.
echo [7] Generate summary text report
vcover report ..\results\code_coverage\yapp_code_merged.ucdb > ..\results\code_coverage\codecov_report.txt

if errorlevel 1 (
  echo.
  echo Summary text report generation failed.
  exit /b 1
)

echo.
echo [8] Generate detailed text report
vcover report -details -output ..\results\code_coverage\codecov_detail_full.txt ..\results\code_coverage\yapp_code_merged.ucdb

if errorlevel 1 (
  echo.
  echo Detailed text report generation failed.
  exit /b 1
)

echo.
echo [9] Generate summary HTML report
vcover report -html -htmldir ..\results\code_coverage\html ..\results\code_coverage\yapp_code_merged.ucdb

if errorlevel 1 (
  echo.
  echo Summary HTML report generation failed.
  exit /b 1
)

echo.
echo [10] Generate detailed HTML report
vcover report -html -details -htmldir ..\results\code_coverage\html_detail ..\results\code_coverage\yapp_code_merged.ucdb

if errorlevel 1 (
  echo.
  echo Detailed HTML report generation failed.
  exit /b 1
)

echo.
echo ============================================================
echo Code coverage regression completed.
echo Summary text report:
echo   ..\results\code_coverage\codecov_report.txt
echo Detailed text report:
echo   ..\results\code_coverage\codecov_detail_full.txt
echo Summary HTML report:
echo   ..\results\code_coverage\html\index.html
echo Detailed HTML report:
echo   ..\results\code_coverage\html_detail\index.html
echo ============================================================

endlocal
