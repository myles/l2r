#!/usr/bin/perl

unless (caller()) {
	mac_test();
}

sub mac_get_name {
	open(IF, "/sbin/ifconfig |") or die;
	while (<IF>) {
		chomp;
		if (/HWaddr (\S+)/) {
			close(IF);
			return mac_2_name($1);
		}
	}
	close(IF);
	die "Who am I?  I have no mac address to convert to a name\n";
}

sub mac_2_name {
	my($mac) = @_;

	$mac=~s/://g;

	$mac_bin = pack('H*',$mac);	
	$mac_bin = pack('u',$mac_bin); chomp($mac_bin);

	print "$mac ->  $mac_bin -> " if $Debug;
#	$mac_bin =~ tr/'-~/_a-zA-Z0-9./;
	$mac_bin =~ tr|` -~|00-9A-Za-z_.|;

	print "$mac_bin\n" if $Debug;

	return substr($mac_bin, 1);	# don't include length (6)
}


#eth0      Link encap:Ethernet  HWaddr 00:50:BF:3A:1C:F4  
#          inet addr:192.168.1.6  Bcast:192.168.1.255  Mask:255.255.255.0
#          UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
#          RX packets:293503 errors:161 dropped:0 overruns:0 frame:0
#          TX packets:746710 errors:1 dropped:0 overruns:0 carrier:2
#          collisions:266896 txqueuelen:100 
#          Interrupt:11 Base address:0x6000 

sub mac_test {
	if (@ARGV) {
		foreach (@ARGV) {
			print "$_ -> ", mac_2_name($_), "\n";
		}
		exit 0;
	}


	open(IF, "/sbin/ifconfig |") or die;
	while (<IF>) {
		chomp;
		if (/HWaddr (\S+)/) {
			print "$1 -> ", mac_2_name($1), "\n";
		}
	}
	close(IF);
}

1;
