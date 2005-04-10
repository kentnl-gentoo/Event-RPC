# $Id: Client.pm,v 1.1 2005/04/10 21:07:12 joern Exp $

#-----------------------------------------------------------------------
# Copyright (C) 2002-2005 Jörn Reder <joern AT zyn.de>.
# All Rights Reserved. See file COPYRIGHT for details.
# 
# This module is part of Event::RPC, which is free software; you can
# redistribute it and/or modify it under the same terms as Perl itself.
#-----------------------------------------------------------------------

package Event::RPC::Client;

use Event::RPC;
use Event::RPC::Message;

use Carp;
use strict;
use IO::Socket;

sub get_server			{ shift->{server}			}
sub get_port			{ shift->{port}				}
sub get_sock			{ shift->{sock}				}
sub get_loaded_classes		{ shift->{loaded_classes}		}
sub get_error_cb		{ shift->{error_cb}			}
sub get_ssl			{ shift->{ssl}				}
sub get_auth_user		{ shift->{auth_user}			}
sub get_auth_pass		{ shift->{auth_pass}			}
sub get_connected		{ shift->{connected}			}

sub set_server			{ shift->{server}		= $_[1]	}
sub set_port			{ shift->{port}			= $_[1]	}
sub set_sock			{ shift->{sock}			= $_[1]	}
sub set_loaded_classes		{ shift->{loaded_classes}	= $_[1]	}
sub set_error_cb		{ shift->{error_cb}		= $_[1]	}
sub set_ssl			{ shift->{ssl}			= $_[1]	}
sub set_auth_user		{ shift->{auth_user}		= $_[1]	}
sub set_auth_pass		{ shift->{auth_pass}		= $_[1]	}
sub set_connected		{ shift->{connected}		= $_[1]	}

sub new {
	my $class = shift;
	my %par = @_;
	my  ($server, $port, $error_cb, $ssl, $auth_user, $auth_pass) =
	@par{'server','port','error_cb','ssl','auth_user','auth_pass'};
	
	my $self = bless {
		server	        => $server,
		port  	        => $port,
		ssl		=> $ssl,
		auth_user	=> $auth_user,
		auth_pass	=> $auth_pass,
		error_cb        => $error_cb,
		loaded_classes  => {},
		connected       => 0,
	}, $class;

	return $self;
}

sub connect {
	my $self = shift;
	
	croak "Client is already connected" if $self->get_connected;

	my $ssl    = $self->get_ssl;
	my $server = $self->get_server;
	my $port   = $self->get_port;

	if ( $ssl ) {
		eval { require IO::Socket::SSL };
		croak "SSL requested, but IO::Socket::SSL not installed" if $@;
	}
	
	my $sock;
	if ( $ssl ) {
		$sock = IO::Socket::SSL->new(
			Proto     => 'tcp',
        		PeerPort  => $port,
        		PeerAddr  => $server,
			Type      => SOCK_STREAM
		) or croak "Can't open SSL connection to $server:$port: $IO::Socket::SSL::ERROR";
	} else {
		$sock = IO::Socket::INET->new(
			Proto     => 'tcp',
        		PeerPort  => $port,
        		PeerAddr  => $server,
			Type      => SOCK_STREAM
		) or croak "Can't open connection to $server:$port - $!";
	}

	$sock->autoflush(1);

	$self->set_sock($sock);

	my $auth_user = $self->get_auth_user;
	my $auth_pass = $self->get_auth_pass;

	if ( $auth_user ) {
		my $rc = $self->send_request ({
			cmd  => 'auth',
			user => $auth_user,
			pass => $auth_pass,
		});
		croak $rc->{msg} if not $rc->{ok};
	}
	
	$self->load_all_classes;
	
	$self->set_connected(1);
	
	1;
}

sub log_connect {
	my $class = shift;
	my %par = @_;
	my ($server, $port) = @par{'server','port'};
	
	my $sock = IO::Socket::INET->new(
		Proto     => 'tcp',
        	PeerPort  => $port,
        	PeerAddr  => $server,
		Type      => SOCK_STREAM
	) or croak "Can't open connection to $server:$port - $!";

	return $sock;
}

sub disconnect {
	my $self = shift;

	close ($self->get_sock) if $self->get_sock;
	$self->set_connected(0);

	1;
}

sub DESTROY {
	shift->disconnect;
}

sub error {
	my $self = shift;
	my ($message) = @_;

	my $error_cb = $self->get_error_cb;
	
	if ( $error_cb ) {
		&$error_cb($self, $message);
	} else {
		croak "Unhandled error in client/server communication";
	}
	
	1;
}

sub load_all_classes {
	my $self = shift;
	
	my $rc = $self->send_request ({
		cmd   => 'classes_list',
	});
	
	foreach my $class ( @{$rc->{classes}} ) {
		$self->load_class ($class);
	}
	
	1;
}

sub load_class {
	my $self = shift;
	my ($class) = @_;

	my $loaded_classes = $self->get_loaded_classes;

	return 1 if $loaded_classes->{$class};

	$loaded_classes->{$class} = 1;

	my $rc = $self->send_request ({
		cmd   => 'class_info',
		class => $class,
	});
	
	my $local_method;
	my $local_class = $class;
	my $methods = $rc->{methods};

	# create local destructor for this class
	if ( 1 ) {
		no strict 'refs';
		my $local_method = $local_class.'::'."DESTROY";
		*$local_method = sub {
			return if not $self->get_connected;
			my $oid_ref = shift;
			$self->send_request ({
				cmd    => "client_destroy",
				oid    => ${$oid_ref},
			});
		};
	}

	# create local methods for this class
	foreach my $method ( keys %{$methods} ) {
		$local_method = $local_class.'::'.$method;

		my $method_type = $methods->{$method};

		# print "Registering local method: $local_method / type=$method_type\n";
		
		if ( $method_type eq '_constructor' ) {
			# this is a constructor for this class
			my $request_method = $class.'::'.$method;
			no strict 'refs';
			*$local_method = sub {
				shift;
				my $rc = $self->send_request ({
					cmd    => 'new',
					method => $request_method,
					params => \@_,
				});
				my $oid = $rc->{oid};
				return bless \$oid, $local_class;
			};

		} elsif ( $method_type eq '1' ){
			# this is a simple method
			my $request_method = $method;
			no strict 'refs';
			*$local_method = sub {
				my $oid_ref = shift;
				my $rc = $self->send_request ({
					cmd    => 'exec',
					oid    => ${$oid_ref},
					method => $request_method,
					params => \@_,
				})->{rc};
				return @{$rc} if wantarray;
				return $rc->[0];
			};

		} else {
			# this is a object returner
			my $request_method = $method;
			no strict 'refs';
			*$local_method = sub {
				my $oid_ref = shift;
				my $rc = $self->send_request ({
					cmd    => 'exec',
					oid    => ${$oid_ref},
					method => $request_method,
					params => \@_,
				})->{rc};

				foreach my $val ( @{$rc} ) {
					if ( ref $val eq 'ARRAY' ) {
						foreach my $list_elem ( @{$val} ) {
							my ($class) = split("=","$list_elem",2);
							$self->load_class($class)
								unless $loaded_classes->{$class};
							my $list_elem_copy = $list_elem;
							$list_elem = \$list_elem_copy;
							bless $list_elem, $class;
						}
					} elsif ( ref $val eq 'HASH' ) {
						foreach my $hash_elem ( values %{$val} ) {
							my ($class) = split("=","$hash_elem",2);
							$self->load_class($class)
								unless $loaded_classes->{$class};
							my $hash_elem_copy = $hash_elem;
							$hash_elem = \$hash_elem_copy;
							bless $hash_elem, $class;
						}
					} else{
						my ($class) = split("=","$val",2);
						$self->load_class($class)
							unless $loaded_classes->{$class};
						my $val_copy = $val;
						$val = \$val_copy;
						bless $val, $class;
					}
				}
				return @{$rc} if wantarray;
				return $rc->[0];
			};
		}
	}

	return $local_class;
}

sub send_request {
	my $self = shift;
	my ($request) = @_;
	
	my $message = Event::RPC::Message->new ($self->get_sock);

	$message->write_blocked($request);

	my $rc = eval { $message->read_blocked };

	if ( $@ ) {
		$self->error($@);
		return;
	}

	if ( not $rc->{ok} ) {
		$rc->{msg} .= "\n" if not $rc->{msg} =~ /\n$/;
		croak "$rc->{msg}".
		      "Called via Event::RPC::Client";
	}

	return $rc;
}

1;

__END__

=head1 NAME

Event::RPC::Client - Client API to connect to Event::RPC Servers

=head1 SYNOPSIS

  use Event::RPC::Client;

  my $client = Event::RPC::Client->new (
    #-- Required arguments
    server   => "localhost",
    port     => 5555,
    
    #-- Optional arguments
    ssl      => 1,

    auth_user => "fred",
    auth_pass => Event::RPC->crypt("fred",$password),

    error_cb => sub {
      my ($client, $error) = @_;
      print "An RPC error occured: $error\n";
      $client->disconnect;
      exit;
    },
  );

  $client->connect;
  
  #-- And now use classes and methods the server
  #-- allows to access via RPC, here My::TestModule
  #-- from the Event::RPC::Server manpage SYNPOSIS.
  my $obj = My::TestModule->new( data => "foobar" );
  print "obj says hello: ".$obj->hello."\n";
  $obj->set_data("new foobar");
  print "updated data: ".$obj->get_data."\n";

  $client->disconnect;

=head1 DESCRIPTION

Use this module to write clients accessing objects and methods
exported by a Event::RPC driven server.

Just connect to the server over the network, optionally with
SSL and user authentication, and then simply use the exported classes
and methods like having them locally in the client.

General information about the architecture of Event::RPC driven
applications is collected in the Event::RPC manpage.

The following documentation describes the client connection
options in detail.

=head1 CONFIGURATION OPTIONS

You need to specify at least the server hostname and TCP port
to connect a Event::RPC server instance. If the server requires
a SSL connection or user authentication you need to supply
the corresponding options as well, otherwise connecting will
fail.

=head2 REQUIRED OPTIONS

These are necessary to connect the server:

=over 4

=item B<server>

This is the hostname of the server running Event::RPC::Server.
Use a IP address or DNS name here.

=item B<port>

This is the TCP port the server is listening to.

=back

=head2 SSL OPTIONS

If the server accepts only SSL connections you need to enable
ssl here in the client as well:

=over 4

=item B<ssl>

Set this option to 1 to encrypt the network connection using SSL.

=back

=head2 AUTHENTICATION OPTIONS

If the server requires user authentication you need to set
the following options:

=over 4

=item B<auth_user>

A valid username.

=item B<auth_pass>

The corresponding password, encrypted using Perl's crypt() function,
using the username as the salt.

Event::RPC has a convenience function for generating such a crypted
password, although it's currently just a 1:1 wrapper around Perl's
builtin crypt() function, but probably this changes someday, so better
use this method:

  $crypted_pass = Event::RPC->crypt($user, $pass);

=back

If the passed credentials are invalid the Event::RPC::Client->connect()
method throws a correspondent exception.

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

