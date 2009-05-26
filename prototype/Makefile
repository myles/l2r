default:

backup:
	rsync -v -e ssh -a . dsl.ss.org:l2r

ci:
	ci -l Makefile l2b l2r l2send  *.pl

print:
	a2ps -4 --file-align=fill Makefile l2b l2r l2send  *.pl
