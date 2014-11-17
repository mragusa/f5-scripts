#!/usr/bin/perl

use warnings;
use strict;
use SOAP::Lite;
use Data::Dumper;

my($client, $soapResponse, $user, $password, $server, $partition);
my $password_file = "$ENV{HOME}/.f5_login";
if (-e $password_file)
{
	open(LOGIN, "<", $password_file) or warn $!;
	my @login_creds = <LOGIN>;
	($user,$password) = split(/\s/, $login_creds[0]);
} else {print "error in opening file\n";}

print "F5 Interactive Shell\n";
print ">";

while (my $command = <STDIN>)
{
	chomp($command);

	if($command =~ m/^login/)
	{
		if ($password_file)
		{
			(undef, $server) = split(/\s/, $command);
		} else {
			(undef, $server, $user, $password) = split(/\s/, $command);
		}
		sub SOAP::Transport::HTTP::Client::get_basic_credentials {
			return $user => $password;
		}
		# define client proxy
		$client = SOAP::Lite->proxy("http://$server/iControl/iControlPortal.cgi");
		# Grab current active partition
		$partition = &get_active_partition;
	}
	elsif ($command eq 'exit')
	{
		exit();
	}
	elsif ($command eq 'system_information')
	{
		&system_information;
	}
	elsif ($command eq 'add')
	{
		my ($virtual_server_status) = &create_virtual;
		print $virtual_server_status,"\n";
	}
	elsif ($command eq 'list_partition')
	{
		&list_partition;
	}
	elsif ($command eq 'set_partition')
	{
		&set_partition;
		$partition = &get_active_partition;
	}
	elsif ($command eq 'get_active_partition')
	{
		&get_active_partition;
	}
	elsif ($command eq 'list_virtual_servers')
	{
		&list_virtual_servers;
	}
	elsif ($command eq 'list_rules')
	{
		&list_virtual_rules;
	}
	else
	{
		print "Error: Command not found\n";
	}
	print "$server -> $partition>";
}

sub system_information
{
	# Used for basic connectivity testing
	# once user logs into the system, they run system_information and the basic info of the system should be displayed
	# Refer to URL_HERE for more information and adding functionality.
	#	my $SystemInfo = SOAP::Lite
	#		-> uri('urn:iControl:System/SystemInfo')
	#		-> proxy("http://$server/iControl/iControlPortal.cgi");
	my $SystemInfo = $client->uri('urn:iControl:System/SystemInfo');
	# The line below is used to encode username and password with the http requests
	eval { $SystemInfo->transport->http_request->header ( 'Authorization' => 'Basic ' . MIME::Base64::encode("$user:$password", '')); };

	$soapResponse = $SystemInfo->get_version();
	my ($version) = $soapResponse->result;
	print "Version: $version\n";
	$soapResponse = $SystemInfo->get_system_id();
	my ($system_id) = $soapResponse->result;
	print "System ID: $system_id\n";
	$soapResponse = $SystemInfo->get_uptime();
	my (@uptime) = $soapResponse->result;
	printf("Uptime: %ld\n", $uptime[0]);
	$soapResponse = $SystemInfo->get_system_information();
	# System information is returned as an array of hashes
	my (@system_information) = $soapResponse->result;
	print "System Information:\n";
	print "\tHostname: $system_information[0]->{host_name}\n";
	print "\tSystem Name: $system_information[0]->{system_name}\n";
	print "\tPlatform: $system_information[0]->{platform}\n";
}

sub checkResponse()
{
	my ($soapResponse) = (@_);
	if ( $soapResponse->fault )
	{
		print $soapResponse->faultcode, " ", $soapResponse->faultstring, "\n";
		exit();
	}
}

sub list_partition
{
	my ($listPartition) = $client->uri('urn:iControl:Management/Partition');
	eval { $listPartition->transport->http_request->header ( 'Authorization' => 'Basic ' . MIME::Base64::encode("$user:$password", '')); };
	$soapResponse = $listPartition->get_partition_list();
	&checkResponse($soapResponse);
	my $partition_list = $soapResponse->result;
	my (@partitions) = @{$partition_list};
	foreach (@partitions)
	{
		print "\t", $_->{partition_name}," : ", $_->{description}, "\n";
	}
}

sub set_partition
{
	my ($partition);
	print "Enter partition name: ";
	$partition = <STDIN>; 
	chomp($partition);
	print "Partition: $partition\n";

	my $setPartition= $client->uri('urn:iControl:Management/Partition');
	eval { $setPartition->transport->http_request->header ( 'Authorization' => 'Basic ' . MIME::Base64::encode("$user:$password", '')); };
	$soapResponse = $setPartition->set_active_partition(SOAP::Data->name('active_partition')->value($partition));
	&checkResponse($soapResponse);
	my ($active_partition) = $soapResponse->result;
#	print Dumper $active_partition;
}

sub get_active_partition
{
	my ($activePartition) = $client->uri('urn:iControl:Management/Partition');
	eval { $activePartition->transport->http_request->header ( 'Authorization' => 'Basic ' . MIME::Base64::encode("$user:$password", '')); };
	$soapResponse = $activePartition->get_active_partition();
	&checkResponse($soapResponse);

	return ($soapResponse->result);
}

sub create_virtual
{
	# Declare virtual server variables
	my ($name, $address, $port, $protocal, $pool, $existing_pool);
	print "Name of Virtual Server: ";
	$name = <STDIN>;
	print "Address of Virtual Server: ";
	$address = <STDIN>;
	unless ($address =~ m/[1,3].[1,3].[1,3].[1,3]/) { print "address is invalid\n";return "invalid IP address";};
	print "Port of Virtual Server: ";
	$port = <STDIN>;
	print "Protocal of Virtual Server: ";
	$protocal = <STDIN>;
	print "Pool assignment: ";
	$pool = <STDIN>;
	print "Does $pool exist? ";
	$existing_pool = <STDIN>;
	unless ($existing_pool eq 'yes') { &create_pool($pool)} else {chomp($pool);};
	chomp($name, $address, $port, $protocal);
	print $pool,"\n" if ($existing_pool eq 'yes');
	print $name,"\n";
	print $address,"\n";
	print $port,"\n";
	print $protocal,"\n";
}

sub create_pool
{
	my ($new_pool) = $_[0];
	print "New Pool: $new_pool\n";
}

sub list_virtual_servers
{
	my ($vs_list) = $client->uri('urn:iControl:LocalLB/VirtualServer');
	eval { $vs_list->transport->http_request->header ( 'Authorization' => 'Basic ' . MIME::Base64::encode("$user:$password", '')); };
	$soapResponse = $vs_list->get_list();
	
	&checkResponse($soapResponse);
	my ($virtual_server_list) = $soapResponse->result;
	my (@virtual_servers) = @{$virtual_server_list};
	foreach (@virtual_servers)
	{
		print "\t$_\n";
	}
}

sub list_virtual_rules
{
	my ($virtual_server);
	print "Enter virtual server name: ";
	$virtual_server = <STDIN>;
	chomp($virtual_server);
	my ($vs_rule_list) = $client->uri('urn:iControl:LocalLB/VirtualServer');
	eval { $vs_rule_list->transport->http_request->header ( 'Authorization' => 'Basic ' . MIME::Base64::encode("$user:$password", '')); };
	$soapResponse = $vs_rule_list->get_rule(SOAP::Data->name('virtual_servers')->value([$virtual_server]));
	&checkResponse($soapResponse);
	my ($vs_irules) = $soapResponse->result;
	foreach my $irules (@{$vs_irules})
	{
		foreach (@{$irules})
		{
			print "\t$_->{priority} : $_->{rule_name}\n"
		}
	}
}
