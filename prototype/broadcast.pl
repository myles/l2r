
sub broadcast {
	my($dev, $ip, $port);

	my(%interface) = discover();

	socket(Sock, PF_INET, SOCK_DGRAM,getprotobyname("udp"));
	setsockopt(Sock, SOL_SOCKET, SO_BROADCAST, 1);

	foreach $dev (sort keys %interface) {
		$ip = inet_aton($interface{$dev});

		$port = sockaddr_in(2, $ip);

		send(Sock, "@_", 0, $port);
#		print "sent $dev->$interface{$dev}: @_\n";
	}
}

1;
