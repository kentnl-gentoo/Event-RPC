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
	$self->get_server->get_logger->remove_fh($sock);
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

