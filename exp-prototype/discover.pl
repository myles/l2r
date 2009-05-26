#!/usr/bin/perl 

unless (caller() ) {
	test();
}

sub wireless {

	my $if = shift;
#	print "$if\n";
# Remove this when real wireless interfaces happen
	return 1;

	open (IF,"/sbin/iwconfig $if | ");
	$xix=<IF>;
	if ($xix=~/no wireless extensions/) {
		return 0;
	}
	return 1;
}


my %if_list=();
my $done = 0;

sub discover_new {
	$done = 0;
}

sub discover {
	my($ip, $interface);

	return %if_list if $done++;

	open(IF,"/sbin/ifconfig | ");

	while (<IF>) {
		if ($_ =~ /Link encap:/) {
			($interface,$garbage)= split(/ /,$_,2);
		}elsif ($_ =~ /inet addr:/) {
			($trash,$ip,$bip,$garbage)=split(/:/,$_);
			if ( wireless($interface) ){
				($ip,$trash) =split(/ /,$bip);
				$if_list{$interface}=$ip unless $interface eq "lo";
			}
			$interface="";
		} else {
			next;
		}
	}
	return %if_list;
}


sub test {
	# Test script

	%x=discover();
	foreach $i (keys(%x) ) {
		print "$i = $x{$i}\n";
	}

}

1;
