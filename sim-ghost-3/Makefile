default:
	rm -f Simulation.log
	./sim 2>&1 | tee Simulation.log

ci:
	ci -l Makefile sim *.pl

print:
	a2ps -4 --file-align=fill Makefile l2b l2r l2send  *.pl
