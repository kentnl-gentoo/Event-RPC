package Event::RPC::LogConnection;

use Carp;
use Socket;

my $LOG_CONNECTION_ID;

sub get_cid			{ shift->{cid}				}
sub get_sock			{ shift->{sock}				}
sub get_server			{ shift->{server}			}

sub get_watcher			{ shift->{watcher}			}
sub set_watcher			{ shift->{watcher}		= $_[1]	}

sub new {
	my $class = shift;
	my ($server, $sock) = @_;

	my $cid = ++$LOG_CONNECTION_ID;
	
	my $self = bless {
		cid     => $cid,
		sock    => $sock,
		server  => $server,
		watcher => undef,
	}, $class;

	$self->{watcher} = $server->get_loop->add_io_watcher(
		fh   => $sock,
		poll => 'r',
		cb   => sub { $self->input; 1 },
		desc => "log reader $cid",
	);

	$self->get_server->log (2,
		"Got new logger connection. Connection ID is $cid"
	);

	return $self;
}

sub disconnect {
	my $self = shift;

	my $sock = $self->get_sock;
	$self->get_server->get_logger->remove_fh($sock)
		if $self->get_server->get_logger;
	$self->get_server->get_loop->del_io_watcher($self->get_watcher);
	$self->set_watcher(undef);
	close $sock;

	$self->get_server->set_log_clients_connected ( $self->get_server->get_log_clients_connected - 1 );
	delete $self->get_server->get_logging_clients->{$self->get_cid};
	$self->get_server->log(2, "Log client disconnected");

	1;
}

sub input {
	my $self = shift;

	my $buffer;

	$self->disconnect
		if not sysread($self->get_sock, $buffer, 4096);
	
	1;
}

1;

__END__

=head1 NAME

Event::RPC::LogConnection - Represents a logging connection

=head1 SYNOPSIS

  # Internal module. No documented public interface.

=head1 DESCRIPTION

Objects of this class are created by Event::RPC server if a
client connects to the logging port of the server. It's an
internal module and has no public interface.

=head1 AUTHORS

  Jörn Reder <joern at zyn dot de>

=head1 COPYRIGHT AND LICENSE

Copyright 2002-2005 by Jörn Reder.

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU Library General Public License as
published by the Free Software Foundation; either version 2.1 of the
License, or (at your option) any later version.

This library is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
Library General Public License for more details.

You should have received a copy of the GNU Library General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307
USA.

=cut

