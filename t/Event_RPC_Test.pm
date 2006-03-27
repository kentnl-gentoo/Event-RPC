# $Id: Event_RPC_Test.pm,v 1.3 2006/02/24 14:28:44 joern Exp $

#-----------------------------------------------------------------------
# Copyright (C) 2002-2005 Jörn Reder <joern AT zyn.de>.
# All Rights Reserved. See file COPYRIGHT for details.
# 
# This module is part of Event::RPC, which is free software; you can
# redistribute it and/or modify it under the same terms as Perl itself.
#-----------------------------------------------------------------------

package Event_RPC_Test;

use strict;

sub get_data			{ shift->{data}				}
sub set_data			{ shift->{data}			= $_[1]	}

sub new {
	my $class = shift;
	my %par = @_;
	my ($data) = $par{'data'};

	my $self = bless {
		data	=> $data,
	}, $class;
	
	return $self;
}

sub hello {
	my $self = shift;
	
	return "I hold this data: '".$self->get_data."'";
}

sub quit {
	my $self = shift;
	
	my $rpc_server = Event::RPC::Server->instance;
	
	$rpc_server->get_loop->add_timer (
		after	=> 1,
		cb	=> sub { $rpc_server->stop },
	);
	
	return "Server stops in one second";
}

sub clone {
	my $self = shift;
	
	my $clone = (ref $self)->new (
		data => $self->get_data
	);
	
	return $clone;
}

sub multi {
	my $self = shift;
	my ($num) = @_;
	
	my (@list, %hash);
	while ($num) {
		push @list, $hash{$num} = (ref $self)->new ( data => $num );
		--$num;
	}

	return (\@list, \%hash);
}

sub echo {
	my $self = shift;
	my (@params) = @_;
	return @params;
}

sub get_cid {
        my $self = shift;
        my $connection = Event::RPC::Server->instance->get_active_connection;
        my $cid = $connection->get_cid;
        return $cid;
}

sub get_object_cnt {
        my $self = shift;
        my $connection = Event::RPC::Server->instance->get_active_connection;
        my $client_oids = $connection->get_client_oids;
        my $cnt = keys %{$client_oids};
        return $cnt;
}

sub get_undef_object {
        return undef;
}

1;

