#!/usr/bin/perl -w 

open(ROUTING, "|sh -x ");
select(ROUTING); $| = 1; select(STDOUT);

sub route_add {
	($ip, $gw) = @_;

	print ROUTING "/sbin/route add $ip gw $gw\n";
	return;
}

sub route_del {
	($ip) = @_;

	print ROUTING "/sbin/route delete $ip";
	return;
}

1;
