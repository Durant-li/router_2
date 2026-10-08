-timescale 1ns/1ns

+incdir+../vip/yapp/sv
+incdir+../vip/channel/sv
+incdir+../vip/hbus/sv
+incdir+../vip/clock_and_reset/sv


//tb_top.sv include

+incdir+../tb/env
+incdir+../tb/tests
+incdir+../tb/sequences
+incdir+../tb/scoreboard
+incdir+../tb/coverage
+incdir+../tb/top

+incdir+../tb/checkers


../vip/yapp/sv/yapp_pkg.sv
../vip/yapp/sv/yapp_if.sv

../vip/channel/sv/channel_pkg.sv
../vip/channel/sv/channel_if.sv

../vip/hbus/sv/hbus_pkg.sv
../vip/hbus/sv/hbus_if.sv

../vip/clock_and_reset/sv/clock_and_reset_pkg.sv
../vip/clock_and_reset/sv/clock_and_reset_if.sv



../tb/top/router_error_if.sv

../tb/top/clkgen.sv
../tb/top/tb_top.sv
../tb/top/hw_top.sv


//cd ..\sim
//if exist work rmdir /s /q work
//vlib work
//vmap work work
//vlog -sv -L mtiUvm "+incdir+%UVMHOME%\src" -f flist.f
//vsim -c -L mtiUvm work.hw_top work.tb_top +UVM_TESTNAME=router_smoke_test +UVM_VERBOSITY=UVM_LOW -do "run -all; quit -f"
