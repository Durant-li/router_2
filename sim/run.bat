@echo off

if exist work rmdir /s /q work

vlib work
vmap work work

vlog -sv -L mtiUvm "+incdir+%UVMHOME%\src" -f flist.f

vsim -c -L mtiUvm work.hw_top work.tb_top +UVM_TESTNAME=router_smoke_test +UVM_VERBOSITY=UVM_LOW -l ../results/logs/router_smoke_test.log -do "run -all; quit -f"
