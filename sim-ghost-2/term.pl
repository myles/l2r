#!/usr/bin/perl

die unless $ENV{LINES};

package term;

my($ROWS) = $ENV{LINES};
my($COLS) = $ENV{COLUMNS};

unless (caller()) {
	term::test();
}

sub clear {
	print "\e[H\e[J";
}

sub goto {
	my($row, $col) = @_;

	print "\e[${row};${col}H";
}

sub test {
	$| = 1;

	clear();

	term::goto($ROWS, 1);        print "Lower Left";
	term::goto(1, $COLS-10);     print "Upper Right";
	term::goto($ROWS, $COLS-10); print "Lower Right";
	term::goto(1, 1);            print "Upper Left";
	term::goto($ROWS, 20);
}
1;
