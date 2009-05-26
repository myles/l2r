package Radio;

use strict;

# status F, M, B, S, A

#	transmit($radio, "I name status [master]");
#	transmit($radio, "M master slave");
#	transmit($radio, "B $name $from $master");
#	transmit($radio, "S slave master");
#	transmit($radio, "C frommaster tomaster slavesoffrom");

# external transmit($radio, $msg);

sub new {
	my($mac, $name, $width) = @_; 

	my $radio = {
		mac   => $mac,
		name  => $name,
		width => $width,
	}; 
	bless $radio;
	
	$radio->{x} = int(rand($width));
	$radio->{y} = int(rand($width));

	$radio->{dx} = int(rand(20)) - 10;
	$radio->{dy} = int(rand(20)) - 10;

	$radio->{status} = 'F';
	$radio->{master} = '';
	$radio->{clock} = int(rand(1000));

	return $radio;
}

sub receive {
	my($radio, $from, $msg) = @_;

	print "Receive  $from => $radio->{mac} msg: $msg\n";

	if ($radio->{mac} eq $from) {
		main::abort("I am not allowed to receive my own transmits");
		return;
	}

	$msg =~ /^. (\S+)/; 
	$radio->{arp}{$1} = $from;

	if ($msg =~ /^I (\S+) (\S+) (.*)/) {
		heard_iam($radio, $from, $1, $2, split(' ', $3));
		return;
	}

	if ($msg =~ /^M (\S+) (\S+)/) {
		heard_be_master($radio, $from, $1, $2);
		return;
	}

	if ($msg =~ /^S (\S+) (\S+)/) {
		heard_be_slave($radio, $from, $1, $2);
		return;
	}

	if ($msg =~ /^B (\S+) (\S+) (\S+)/) {
		heard_be_bond($radio, $from, $1, $2, $3);
		return;
	}

	if ($msg =~ /^F (\S+)/) {
		heard_be_free($radio, $from, $1);
		return;
	}

	if ($msg =~ /^A (\S+) (\S+)/) {
		heard_be_apprentice($radio, $from, $1, $2);
		return;
	}

	if ($msg =~ /^C (\S+) (\S+) (\S+)/) {
		heard_count_request($radio, $1, $2, $3);
		return;
	}
	main::abort("Unknown message $msg");
}

sub tick {
	my($radio) = @_;

	$radio->{clock} = 1000;
	clean_tables($radio);

	if ($radio->{status} eq 'S' || $radio->{status} eq 'B') {
		unless ($radio->{arp}{$radio->{master}}) {
			print "I $radio->{name} am free from $radio->{master}\n";
			$radio->{master} = '';
			$radio->{status} = 'F';
		}
	}

	if ($radio->{status} eq 'M') {
		$radio->{status} = 'F' unless have_slaves($radio);
	}

		
	if ($radio->{status} eq 'S') {
		return if $radio->{ping}-- > 0;

		$radio->{ping} = 10;
	}

	my($masters) = list_masters($radio);

	transmit($radio, "I $radio->{name} $radio->{status} $masters");
}

sub list_masters {
	my($radio) = @_;

	my($master) = $radio->{master};
	
	return join(' ', $master, grep !/^$master$/, keys %{ $radio->{masters} });
}

sub clean_tables {
	my($radio) = @_;
	my($name) = $radio->{name};
	my($key, $other, $link, $mac, $cnt);

	foreach $key (qw(bond link)) {
		$cnt = 0;
		foreach $other (keys %{ $radio->{$key} }) {
			$link = $radio->{$key}{$other};
			$mac = $radio->{arp}{$link};

			++$cnt, next if defined $mac && inrange($radio, $mac);

			print "Lost $key connection from $name to $other\n";
			delete $radio->{$key}{$other};
		}
		delete $radio->{$key} unless $cnt;
	}

	foreach $key (qw(bond link masters slaves arp)) {
		$cnt = 0;
		foreach $other (keys %{ $radio->{$key} }) {
			$mac = $radio->{arp}{$other};

			++$cnt, next if defined $mac && inrange($radio, $mac);

			print "Lost $key connection from $name to $other\n";
			delete $radio->{$key}{$other};
		}
		delete $radio->{$key} unless $cnt;
	}

}

sub heard_iam {
	my($radio, $mac, $from, $status, $master, @masters) = @_;

	my($name)  = $radio->{name};
	my($iam)   = $radio->{status};

	if ($iam eq 'F' || $iam eq 'A') {
		if ($status eq 'M' or $status eq 'F' or $status eq 'A') {
			transmit($radio, "M $name $from");
			return;
		}

		if ($status eq 'S' || $status eq 'B') {
			return;
		}

		main::abort("Iam $name heard unknown status $status");
		return;
	}

	if ($iam eq 'S' || $iam eq 'B') {
		if ($status eq 'F' or $status eq 'A') {
			transmit($radio, "A $name $from");
			return;
		}

		if ($status eq 'S' || $status eq 'B') {
			build_links($radio, $from, $master, @masters);
			return;
		}

		if ($status eq 'M') {
			build_links($radio, $name, $master, @masters);
			return;
		}
	}

	if ($iam eq 'M') {
		if ($status eq 'F' or $status eq 'A') {
			make_slave($radio, $from);
			return;
		}

		if ($status eq 'S' or $status eq 'B') {
			build_bonds($radio, $from, $master, @masters);
			return;
		}

		if ($status eq 'M') {
			my($slaves) = have_slaves();
			transmit($radio, "C $name $from $slaves");
			return;
		}
	}

	main::abort("Don't know how to map iam $iam heard $status message");
}

sub build_bonds {
	my($radio, $slave, @masters) = @_;
	my($master);
	my($name) = $radio->{name};

	foreach $master (@masters) {
		next unless defined $master and $master;
		next if $master eq $name;	# its me

		next if defined $radio->{link}{$master};

		print "Build new bond to $name => $slave => $master\n";

		$radio->{link}{$master} = $slave;
		transmit($radio, "B $name $slave $master");
	}
}

sub build_links {
	my($radio, $slave, @masters) = @_;
	my($master);
	my($name) = $radio->{name};
	my($mymaster) = $radio->{master};

	foreach $master (@masters) {
		next unless defined $master and $master;
		next if $master eq $mymaster;	# its to my master

		next if defined $radio->{link}{$master};

		print "Maybe link $mymaster => $slave => $name => $master\n";

		$radio->{link}{$master} = $slave;
#		transmit($radio, "L $mymaster $slave $name $master");
	}
}

sub heard_be_master {
	my($radio, $mac, $from_slave, $to_master) = @_;

	my($name) = $radio->{name};

	# message not for me
	if ($name ne $to_master) {
		if ($radio->{status} eq 'F') {
#			transmit($radio, "M $name $to_master");
			return;
		}
			
		return;
	}

	print "Me ($name) got slave: $mac $from_slave\n";

	$radio->{status} = 'M';
	make_slave($radio, $from_slave);
}

sub heard_be_slave {
	my($radio, $mac, $from_master, $to_slave) = @_;

	$radio->{masters}{$from_master} = 1;

	my($name) = $radio->{name};

	# message not for me
	if ($name ne $to_slave) {
		if ($radio->{status} eq 'F') {
			transmit($radio, "M $name $from_master");
		}
		return;
	}

	if ($radio->{status} eq 'M') {
		print "Me ($name) now forced slave of? $mac $from_master\n";
		main::dump_all('Simulation.Force');

#		$radio->{status} = 'S';
#		$radio->{master} = $from_master;
#		transmit($radio, "F $name");
		return;
	}

	print "Me ($name) now slave of: $from_master\n";

	$radio->{status} = 'S';
	$radio->{master} = $from_master;
	$radio->{clock} = 1000;
}

sub heard_be_bond {
	my($radio, $mac, $from, $me, $to) = @_;

	my($name) = $radio->{name};

	print "bond? me=$name,  $from -> $me -> $to\n";

	# message not for me
	return if $name ne $me;

	if ($from eq $radio->{master}) {
		print "bond? my master asked me to bond\n";
	} else {
		print "bond? bonding for other master\n";
	}

	print "Me ($me) bond for $from and $to\n";

	$radio->{status} = 'B';
	$radio->{bond}{$to} = $from;
	$radio->{master} ||= $from;
}

sub heard_be_free {
	my($radio, $mac, $master) = @_;

	if ($radio->{master} ne $master) {
		return;
	}

	print "Me ($radio->{name}) has been freed from $master\n";

	$radio->{status} = 'F';
	$radio->{master} = '';

	transmit($radio, "I $radio->{name} $radio->{status} $radio->{master}");
}

sub heard_be_apprentice {
	my($radio, $mac, $from_slave, $to_freeman) = @_;

	return if $radio->{name} ne $to_freeman;

	$radio->{status} = 'A' if $radio->{status} eq 'F';
	$radio->{status} = 'M' if $radio->{status} eq 'A' && $radio->{help}++ > 5;
	transmit($radio, "I $radio->{name} $radio->{status} ");
}

sub heard_count_request {
	my($radio, $from_master, $to_master, $slave_count) = @_;

	my($name) = $radio->{name};
	my($nslaves) = $radio->have_slaves();

	# message not for me
	return if $name ne $to_master;

	if ($slave_count < $nslaves) {
print "Won count me=$name has $nslaves, he $from_master has $slave_count\n";
		transmit($radio, "C $name $from_master $nslaves");
	} else {
print "Lost count me=$name has $nslaves, he $from_master has $slave_count\n";
		$radio->{status} = 'F';
		transmit($radio, "F $name");
		transmit($radio, "M $name $from_master");
	}
}

sub have_slaves {
	my($radio) = @_;
	my($slave);
	my($nslaves) = 0;

	foreach $slave (keys %{ $radio->{slaves} }) {
		++$nslaves;
	}
	$radio->{nslaves} = $nslaves;
	return $nslaves;
}


sub make_slave {
	my($radio, $slave) = @_;

	my($name) = $radio->{name};

	$radio->{slaves}{$slave} = 10_000;
	transmit($radio, "S $name $slave");
}

# external transmit($radio, $msg);
1;
