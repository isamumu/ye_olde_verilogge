# These first few variables are for IP packaging

dst_dir=$(HOME)/ip_repo
src_dir=.
ip_name=star_arb
part_no=xczu19eg-ffvc1760-2-i
# Makes Makefile easier to read
out_dir=${dst_dir}/${ip_name}

MODULE := star_arb
MODULE_CAPS := STAR_ARB

default:	$(MODULE).vcd

$(MODULE).vcd:	$(MODULE).vvp
	vvp $(MODULE).vvp

$(MODULE).vvp:	$(MODULE).v $(MODULE)_tb.v $(MODULE)_drivers.mem
	iverilog -DFROM_$(MODULE_CAPS) -I../buffered_handshake -g2012 -o $(MODULE).vvp $(MODULE)_tb.v

open:	$(MODULE).vcd
	gtkwave $(MODULE).vcd --autosavename &

clean:
	rm -rf $(MODULE).vvp
	rm -rf $(MODULE).vcd
	rm -rf ${out_dir}
	rm -rf ${ip_name}_tmp_proj

# Packages into a Vivado IP
ip: clean
	rm -rf ${out_dir}
	mkdir -p ${out_dir}/src
	cp star_arb.v ../buffered_handshake/bhand.v ${out_dir}/src
	vivado -nolog -nojournal -notrace -mode batch -source ip_maker.tcl -tclargs ${out_dir} ${ip_name} ${part_no}
	rm -rf ${ip_name}_tmp_proj
	rm -f *log
	rm -rf .Xil
	rm -f vivado*

force:
	touch $(MODULE)_tb.v
	make
