#!/usr/bin/perl -w 

my(%Routes);

open(ROUTING, "|sh -x ");
select(ROUTING); $| = 1; select(STDOUT);

sub route_add {
	($ip, $gw) = @_;

	print ROUTING "/sbin/route add $ip gw $gw\n";

	$Routes{$ip} = $gw;
	return;
}

sub route_del {
	($ip) = @_;

	return unless defined $Routes{$ip};

	print ROUTING "/sbin/route delete $ip\n";
	delete $Routes{$ip};
	return;
}

1;
