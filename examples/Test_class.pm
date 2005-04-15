# $Id: Test_class.pm,v 1.1 2005/04/15 21:10:20 joern Exp $

#-----------------------------------------------------------------------
# Copyright (C) 2002-2005 Jörn Reder <joern AT zyn.de>.
# All Rights Reserved. See file COPYRIGHT for details.
# 
# This module is part of Event::RPC, which is free software; you can
# redistribute it and/or modify it under the same terms as Perl itself.
#-----------------------------------------------------------------------

package Test_class;

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
		after	=> 3,
		cb	=> sub { $rpc_server->stop },
	);
	
	return "Server stops in 3 seconds";
}

1;

