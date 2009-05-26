package Radio;

use strict;

# status F, M, B, S, A

use constant FREEMAN	=> 'F';
use constant SLAVE	=> 'S';
use constant MASTER	=> 'M';
use constant BOND	=> 'B';
use constant LINK	=> 'W';

my %Messages = (
	'I' => \&heard_iam,
	'M' => \&heard_be_master,
	'S' => \&heard_be_slave,
	'B' => \&heard_be_bond,
	'F' => \&heard_be_free,
	'A' => \&heard_be_apprentice,
	'C' => \&heard_count_request,
);

# external $radio->transmit($msg);

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

	$radio->{status} = FREEMAN;
	$radio->{master} = '';
	$radio->{clock} = int(rand(1000));

	return $radio;
}

sub receive {
	my($radio, $frommac, $msg) = @_;
	my($func);

	print "Receive  $frommac => $radio->{mac} msg: $msg\n";

	if ($radio->{mac} eq $frommac) {
		main::abort("I am not allowed to receive my own transmits");
		return;
	}

	my($mid, $from, @arg) = split(' ', $msg);

	unless (defined ($func=$Messages{$mid})) {
		main::abort("Unknown message: $msg");
		return;
	}

	$radio->{arp}{$from} = $frommac;

	&$func($radio, $from, @arg);
}


sub tick {
	my($radio) = @_;

	clean_tables($radio);

	my($status) = $radio->{status};

	if ($status eq SLAVE or $status eq BOND or $status eq LINK) {
		check_state($radio);

		unless ($radio->{arp}{$radio->{master}}) {
			print "I $radio->{name} am free from $radio->{master}\n";
			become_free($radio);
		}
	}

	if ($radio->{status} eq MASTER) {
		become_free($radio) unless have_slaves($radio);
	}

		
	unless ($radio->{arp}{$radio->{master}}) {
		print "I $radio->{name} am free from $radio->{master}\n";

		become_free($radio);
	}

	if ($radio->{status} eq SLAVE) {
		return if $radio->{ping}-- > 0;

		$radio->{ping} = 10;
	}


	my($masters) = list_masters($radio);

	$radio->transmit("I $radio->{name} $radio->{status} $masters");
	$radio->{clock} = 1000;
}

sub check_state {
	my($radio) = @_;

	my($links) = count_link($radio);
	my($bonds) = count_bond($radio);

	print "$radio->{name} links=$links, bonds=$bonds\n";
	if ($links == 0 && $bonds == 0) {
		$radio->{status} = SLAVE;
		return;
	}
	if ($links) {
		$radio->{status} = BOND;
		return;
	}
		
	if ($bonds) {
		$radio->{status} = LINK;
		return;
	}
}

sub list_masters {
	my($radio) = @_;

	my($master) = $radio->{master};
	
	return join(' ', $master, grep !/^$master$/, keys %{ $radio->{masters} });
}

sub count_link {
	my($radio) = @_;

	return scalar keys %{$radio->{link}};
}

sub count_bond {
	my($radio) = @_;

	return scalar keys %{$radio->{bond}};
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

			print "Lost $name $key from $link to $other\n";
			delete $radio->{$key}{$other};
		}
		delete $radio->{$key} unless $cnt;
	}

	foreach $key (qw(bond link masters slaves arp)) {
		$cnt = 0;
		foreach $other (keys %{ $radio->{$key} }) {
			$mac = $radio->{arp}{$other};

			++$cnt, next if defined $mac && inrange($radio, $mac);

			print "Lost $name $key to $other\n";
			delete $radio->{$key}{$other};
		}
		delete $radio->{$key} unless $cnt;
	}

}


sub heard_iam {
	my($radio, $from, $status, $master, @masters) = @_;

	my($name)  = $radio->{name};
	my($iam)   = $radio->{status};

	if ($iam eq FREEMAN) {
		if ($status eq MASTER or $status eq FREEMAN) {
			$radio->transmit("M $name $from");
			return;
		}

		if ($status eq SLAVE or $status eq BOND or $status eq LINK) {
			return;
		}

		main::abort("Iam $name heard unknown status $status");
		return;
	}

	if ($iam eq SLAVE or $iam eq BOND or $iam eq LINK) {
		if ($status eq FREEMAN) {
			$radio->transmit("A $name $from");
			return;
		}

		if ($status eq SLAVE or $status eq BOND or $iam eq LINK) {
			build_links($radio, $from, $master, @masters);
			return;
		}

		if ($status eq MASTER) {
			build_links($radio, $name, $master, @masters);
			return;
		}
	}

	if ($iam eq MASTER) {
		if ($status eq FREEMAN) {
			make_slave($radio, $from);
			return;
		}

		if ($status eq SLAVE or $status eq BOND) {
			build_bonds($radio, $from, $master, @masters);
			return;
		}

		if ($status eq MASTER) {
			my($slaves) = have_slaves();
			$radio->transmit("C $name $from $slaves");
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
		$radio->transmit("B $name $slave $master");
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
#		$radio->transmit("L $mymaster $slave $name $master");
	}
}

sub heard_be_master {
	my($radio, $from_slave, $to_master) = @_;

	my($name) = $radio->{name};

	# message not for me
	if ($name ne $to_master) {
		if ($radio->{status} eq FREEMAN) {
#			$radio->transmit("M $name $to_master");
			return;
		}
			
		return;
	}

	print "Me ($name) got slave: $from_slave\n";

	$radio->{status} = MASTER;
	make_slave($radio, $from_slave);
}

sub heard_be_slave {
	my($radio, $from_master, $to_slave) = @_;

	$radio->{masters}{$from_master} = 1;

	my($name) = $radio->{name};

	# message not for me
	if ($name ne $to_slave) {
		if ($radio->{status} eq FREEMAN) {
			$radio->transmit("M $name $from_master");
		}
		return;
	}

	if ($radio->{status} eq MASTER) {
		print "Me ($name) now forced slave of? $from_master\n";
		main::dump_all('Simulation.Force');

#		$radio->{status} = SLAVE;
#		$radio->{master} = $from_master;
#		$radio->transmit("F $name");
		return;
	}

	print "Me ($name) now slave of: $from_master\n";

	$radio->{status} = SLAVE;
	$radio->{master} = $from_master;
	$radio->{clock} = 1000;
}

sub heard_be_bond {
	my($radio, $from, $me, $to) = @_;

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

	$radio->{status} = BOND;
	$radio->{bond}{$to} = $from;
	$radio->{master} ||= $from;
}

sub heard_be_free {
	my($radio, $master) = @_;

	if ($radio->{master} ne $master) {
		return;
	}

	print "Me ($radio->{name}) has been freed from $master\n";

	become_free($radio);
}

sub heard_be_apprentice {
	my($radio, $from_slave, $to_freeman) = @_;

	return if $radio->{name} ne $to_freeman;

	$radio->{status} = MASTER;
	$radio->{slave}{$from_slave} = 10_000;
	$radio->transmit("I $radio->{name} $radio->{status} ");
}

sub heard_count_request {
	my($radio, $from_master, $to_master, $slave_count) = @_;

	my($name) = $radio->{name};
	my($nslaves) = $radio->have_slaves();

	# message not for me
	return if $name ne $to_master;

	if ($slave_count < $nslaves) {
print "Won count me=$name has $nslaves, he $from_master has $slave_count\n";
		$radio->transmit("C $name $from_master $nslaves");
	} else {
print "Lost count me=$name has $nslaves, he $from_master has $slave_count\n";
		$radio->transmit("F $name");
		$radio->transmit("M $name $from_master");
		become_free($radio);
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
	$radio->transmit("S $name $slave");
}

sub become_free {
	my($radio) = @_;
	$radio->{status} = FREEMAN;
	$radio->{master} = '';
	$radio->{clock} = int(rand(100));

	delete $radio->{bond};
	delete $radio->{link};
	delete $radio->{slaves};
}

# external $radio->transmit($msg);
1;
