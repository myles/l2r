package Radio;

use strict;

use constant EGON	=> 'F';
use constant VENKMANN	=> 'S';
use constant CLORTHO	=> 'M';
use constant ZUUL	=> 'B';
use constant WEAKZUUL	=> 'W';

# action values
use constant SMSG	=> 'S';		# send S message;

# I name F                                ### venkman request
# S me-clortho you-venkmann               ### clortho request
# M me-venkman you-clortho                ### venkman reply
# P me-venkman you-clortho                ### clortho pink
# B me-venkman to-myclortho for-clortho

# external $radio->transmit($msg);

my %Messages = (
	'A' => \&venkmann_acknowledge,
	'C' => \&clortho_reply,
	'E' => \&egonize,
	'G' => \&clortho_greeting,
	'L' => \&venkmann_list,
	'M' => \&merge_request,
	'O' => \&venkmann_pong,
	'P' => \&clortho_ping,
	'R' => \&clortho_promotion,
	'S' => \&venkmann_request,
	'T' => \&split_cluster,
	'W' => \&weak_zuul_announcement,
	'Y' => \&weak_zuul_acknowledge,
	'Z' => \&zuul_announcement,
);

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

	$radio->{status} = EGON;
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

	$radio->{clock} = 1000;
	clean_tables($radio);

	my($name) = $radio->{name};
	my($status) = $radio->{status};

	if (defined $radio->{action}) {
		if ($radio->{action} eq SMSG) {
			delete $radio->{action};
			$radio->transmit("S $name");	# venkmann_request
			return;
		}
	}

	if ($status eq EGON) {
		$radio->transmit("S $name");	# venkmann_request
		return;
	}

	if ($status eq CLORTHO) {
		my($slaves) = $radio->have_slaves();

		unless ($slaves) {
			become_egon($radio);
			$radio->transmit("S $name");	# venkmann_request
			return;
		}

		poll_slaves($radio);
		return;
	}

	# otherwise VENKMANN ZUUL or WEAKZUUL

	unless ($radio->{arp}{$radio->{master}}) {
		print "I $name am free from $radio->{master}\n";

		become_egon($radio);
		return;
	}

	my($links) = count_link($radio);
	my($bonds) = count_bond($radio);
print "$name links=$links, bonds=$bonds\n";
	if ($links == 0 && $bonds == 0) {
		$radio->{status} = VENKMANN;
		return;
	}
	if ($links) {
		$radio->{status} = WEAKZUUL;
		return;
	}
		
	if ($bonds) {
		$radio->{status} = ZUUL;
		return;
	}
}

sub count_link {
	my($radio) = @_;

	return scalar keys %{$radio->{link}};
}

sub count_bond {
	my($radio) = @_;

	return scalar keys %{$radio->{bond}};
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

sub poll_slaves {
	my($radio) = @_;
	my($name) = $radio->{name};
	my($tick) = $radio->{timer};

	my($slaves) = $radio->{slaves};
	my($slave);
	foreach $slave (keys %$slaves) {
		if ($slaves->{$slave} -= $tick) {
			$slaves->{$slave} = 10_000;
			$radio->transmit("P $name $slave");	# clortho_ping
		}
	}
	$radio->{timer} = 0;
}

# A me-venkmann you-clortho                       -- venkmann_acknowledge
# 	egon,venkmann ->  clortho
# 		add venkmann to slaves
sub venkmann_acknowledge {
	my($radio, $venkmann, $clortho) = @_;

	my($name) = $radio->{name};
	my($status) = $radio->{status};

	if ($name eq $clortho) {
		$radio->{status} = CLORTHO;
		$radio->{slaves}{$venkmann} = 10_000;
		return;
	}
	if ($status eq CLORTHO && $name eq $clortho) {
		$radio->{slaves}{$venkmann} = 10_000;
		return;
	}
}

# C me-clortho you-venkmann                       -- clortho_reply
# 	clortho -> egon
# 		promote to venkmann
# 		send A message
sub clortho_reply {
	my($radio, $clortho, $venkmann) = @_;

	my($name) = $radio->{name};
	my($status) = $radio->{status};

	if ($status eq EGON) {
		$radio->{status} = VENKMANN;
		$radio->{master} = $clortho;
		$radio->transmit("A $name $clortho");	# venkmann_acknowledge
		return;
	}
	# no other state changes
}

# E me-clortho timeout                            -- egonize (free venkmann)
# 	clortho -> venkmann
# 		change to egon
# 		set timeout before broadcasting S-message wait for a C-message
sub egonize {
	my($radio, $master, $time) = @_;

	if ($radio->{master} ne $master) {
		return;
	}

	print "Me ($radio->{name}) has been freed from $master (now an egon)\n";

	become_egon($radio);
}

# G me-clortho uptime venkmann-number             -- clortho_greeting
# 	clortho -> clortho
# 		check if merge is desirable (see rules), if so send M-message.
sub clortho_greeting {
	my($radio, $uptime, $nslaves) = @_;

	my($name) = $radio->{name};
	my($status) = $radio->{status};

#	main::abort("merge not supported");
}

# L me-clortho {venkmann list}                    -- venkmann_list
# 	clortho -> venkmann
# 		add venkmann list to routing table
# 
# 	clortho -> zuul
# 		add venkmann list to routing table
# 		and send L-message to foreign clortho/zuul.
# 
# 	zuul -> foreign zuul
# 		add venkmann list to routing table
# 		and send L-message to clortho.
# 
# 	weak zuul -> clortho
# 		add venkmann list to routing table.
sub venkmann_list {
	my($radio, $clortho, @list) = @_;

	my($name) = $radio->{name};
	my($status) = $radio->{status};
	my($master) = $radio->{master};

	if ($status eq VENKMANN) {
		# add to routing table
		return;
	}
	if ($status eq ZUUL) {
		if ($clortho eq $master) {
			# ***BUG** L not coded
		} else { # Foreign zuul
			# ***BUG** L not coded
		}
	}
	if ($status eq CLORTHO) {
		# add to routing table
		return;
	}
	return;
}

# M me-clortho you-clortho                        -- merge_request
# 	clortho -> clortho
# 		send N-message
sub merge_request {
	my($radio, $from, $to) = @_;

	my($name) = $radio->{name};
	return if $name ne $to;

	my($status) = $radio->{status};
	if ($status ne CLORTHO) {
		main::abort("M request, $name not CLORTHO");
		return;
	}
	$radio->transmit("N $name $from");
}

# N me-clortho you-clortho 			-- merge_accept
# 	clortho -> clortho
# 		send S-message
# 		send E-message
# 		demote yourself to egon
sub merge_accept {
	my($radio, $from, $to) = @_;

	my($name) = $radio->{name};
	my($status) = $radio->{status};

	return if $name ne $to;

	$radio->transmit("S $name ");
	$radio->transmit("E $name");

	become_egon($radio);
}


# O me-venkmann you-clortho                       -- venkmann_pong
# 
# O me-venkmann you-clortho
# 	venkmann -> clortho
# 		cancel remove timeout for venkmann
# 
# O me-venkmann you-clortho
# 	venkmann -> foreign venkmann
# 		promote to zuul
# 		and send a W-message to foreign venkmann
# 		and a Y message to your clortho
sub venkmann_pong {
	my($radio, $venkmann, $clortho) = @_;

	my($name) = $radio->{name};
	my($status) = $radio->{status};

	if ($name eq $clortho) {
		$radio->{slaves}{$venkmann} = 10_000;
		return;
	}
	if ($status eq VENKMANN or $status eq ZUUL or $status eq WEAKZUUL) {
		my($master) = $radio->{master};
main::abort("Bad master($master) for $name") unless $master;
		return if $master eq $clortho;

		$radio->{status} = ZUUL;
		$radio->{bond}{$clortho} = $master;
		$radio->transmit("W $name $venkmann $master");
		$radio->transmit("Y $name $master $clortho");
		return;
	}
}

# P me-clortho you-venkmann {list of venkmann}    -- clortho_ping
# 
# P me-clortho you-venkmann (optional list of venkmann)
# 	clortho -> foreign venkmann
# 		promote to zuul and send Z-message
# 
# P me-clortho you-venkmann (optional list of venkmann)
# 	clortho -> venkmann
# 		reset timeout for ping message. 
# 		if message for you return O message else do nothing.
# 
# P me-clortho you-venkmann (optional list of venkmann)
# 	clortho -> egon
# 		promote yourself to venkmann and send A message
# 
# P me-clortho you-venkmann (optional list of venkmann)
# 	clortho -> clortho
# 		send G-message
# 
# P me-clortho you-venkmann (optional list of venkmann)
# 	clortho -> zuul
# 		send Z-message
sub clortho_ping {
	my($radio, $clortho, $to, @venkmann) = @_;

	my($name) = $radio->{name};
	my($status) = $radio->{status};

	if ($status eq EGON) {
		$radio->{master} = $clortho;
		$radio->{status} = VENKMANN;
		$radio->transmit("A $name $clortho");
		return;
	}

	if ($status eq CLORTHO) {
		my($uptime) = $name; $uptime =~ s/^u-//;
		my($nslaves) = $radio->have_slaves();
		$radio->transmit("G $name $uptime $nslaves");
		return;
	}

	# otherwise
	my($master) = $radio->{master};

	if ($master ne $clortho) {
		$radio->{status} = ZUUL;
		$radio->transmit("Z $name $master $clortho");
		return;
	}

	if ($name eq $to) {
		$radio->transmit("O $name $clortho");
		return;
	}
}

# R me-zuul you-clortho my-clortho                   -- clortho_promotion
# 	venkmann -> egon
# 		promote yourself to a clortho
# 		add venkmann to zuul list as foreign zuul.
sub clortho_promotion {
	my($radio, $zuul, $egon, $my_clortho) = @_;

	my($name) = $radio->{name};
	my($status) = $radio->{status};

	if ($name ne $egon) {
		$radio->{status} = CLORTHO;
		$radio->{bond}{$zuul} = $my_clortho;
	}
}

# S me-name                                       -- venkmann_request
# 	egon -> {clortho}
# 		send C message
# 
# S me-name
# 	egon -> {egons}
# 		promote yourself to clortho set timeout for A message
# 		and send a C message
# 
sub venkmann_request {
	my($radio, $egon) = @_;

	my($name) = $radio->{name};
	my($status) = $radio->{status};

	if ($status eq CLORTHO) {
		$radio->transmit("C $name $egon");	# clortho_reply
		return;
	}
	if ($status eq EGON) {
		$radio->{status} = CLORTHO;
		$radio->{clock} = int(rand(1000));
		$radio->transmit("C $name $egon");	# clortho_reply
		return;
	}
	
	# otherwise 
	my($master) = $radio->{master};

	$radio->{status} = ZUUL;
	$radio->transmit("R $name $egon $master");	# clortho_promotion
	# R me-zuul you-clortho my-clortho
}

# T me-clortho you-clortho1 you-clortho2 timeout  -- split_cluster
# T me-clortho you-clortho1 you-clortho2 timeout (to be looked at later)
# 	clortho -> venkmann
# 		if you are one of the two venkmann in the list promote
# 		yourself to clortho else become an egon and send
# 		S-messages after timeout.
# 
sub split_cluster {
	my($radio, $arg) = @_;

	my($name) = $radio->{name};
	my($status) = $radio->{status};

	$radio->{action} = SMSG;
	main::abort("Not yet T message for $name");
}

# W me-zuul you-zuul he-foreign-clortho        -- weak_zuul_announcement
# W me-zuul you-zuul he-foreign-clortho
# 	venkmann -> venkmann
# 		promote yourself to weak zuul
# 		send Y-message to your clortho.
# 
sub weak_zuul_announcement {
	my($radio, $from, $to, $clortho) = @_;

	my($name) = $radio->{name};
	my($status) = $radio->{status};
	my($master) = $radio->{master};

	if ($name ne $to) {
		return;
	}

	if ($status eq EGON or $status eq CLORTHO) {
		main::abort("Weak zuul announcement to non VENKMANN");
		return;
	}

	if ($clortho eq $master) {
		main::abort("Weak zuul announcemnet me=$name master=$master to=$to from=$from clortho=$clortho");
		return;
	}
	$radio->{status} = WEAKZUUL;
	$radio->{link}{$from} = $clortho;
	$radio->transmit("Y $name $master $clortho");
}

# Y me-zuul you-clortho he-zuul
# 	weak zuul -> clortho
# 		Add zuul to zuul list and send a L-message
# 
sub weak_zuul_acknowledge {
	my($radio, $zuul, $clortho, $he_zuul) = @_;

	my($name) = $radio->{name};
	my($status) = $radio->{status};

	return unless $name eq $clortho;
	$radio->{bond}{$he_zuul} = $clortho;

	my($zuullist) = join(' ', keys(%{$radio->{bond}}));
	$radio->transmit("L $name $zuullist");
}

# Z me-zuul you-clortho he-foreign-clortho        -- zuul_announcement
# 	venkmann -> clortho
# 		Add zuul to zuul list and send a L-message
# 
sub zuul_announcement {
	my($radio, $venkmann, $clortho, $foreign) = @_;

	my($name) = $radio->{name};
	my($status) = $radio->{status};

	if ($name ne $clortho) {
		return;
	}
	if ($status ne CLORTHO) {
		main::abort('zull_announce to non CLORTHO');
		return;
	}
	$radio->{bond}{$venkmann} = $foreign;
	my($zuullist) = join(' ', keys(%{$radio->{bond}}));
	$radio->transmit("L $name $zuullist");
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

sub become_egon {
	my($radio) = @_;
	$radio->{status} = EGON;
	$radio->{master} = '';
	$radio->{clock} = 1_000;

	delete $radio->{bond};
	delete $radio->{link};
	delete $radio->{slaves};
}

# external $radio->transmit($msg);
1;

