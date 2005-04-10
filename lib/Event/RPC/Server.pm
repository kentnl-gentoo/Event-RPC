# $Id: Server.pm,v 1.1 2005/04/10 21:07:12 joern Exp $

#-----------------------------------------------------------------------
# Copyright (C) 2002-2005 Jörn Reder <joern AT zyn.de>.
# All Rights Reserved. See file COPYRIGHT for details.
# 
# This module is part of Event::RPC, which is free software; you can
# redistribute it and/or modify it under the same terms as Perl itself.
#-----------------------------------------------------------------------

package Event::RPC::Server;

use Event::RPC;
use Event::RPC::Message;

use Carp;
use strict;
use IO::Socket::INET;
use Sys::Hostname;

sub get_port			{ shift->{port}				}
sub get_name			{ shift->{name}				}
sub get_loop			{ shift->{loop}				}
sub get_classes			{ shift->{classes}			}
sub get_loaded_classes		{ shift->{loaded_classes}		}
sub get_clients_connected	{ shift->{clients_connected}		}
sub get_log_clients_connected	{ shift->{log_clients_connected}	}
sub get_logging_clients		{ shift->{logging_clients}		}
sub get_logger			{ shift->{logger}			}
sub get_start_log_listener	{ shift->{start_log_listener}		}
sub get_objects			{ shift->{objects}			}
sub get_rpc_socket		{ shift->{rpc_socket}			}
sub get_ssl			{ shift->{ssl}				}
sub get_ssl_key_file		{ shift->{ssl_key_file}			}
sub get_ssl_cert_file		{ shift->{ssl_cert_file}		}
sub get_ssl_passwd_cb		{ shift->{ssl_passwd_cb}		}
sub get_auth_required		{ shift->{auth_required}		}
sub get_auth_passwd_href	{ shift->{auth_passwd_href}		}
sub get_listeners_started	{ shift->{listeners_started}		}

sub set_port			{ shift->{port}			= $_[1]	}
sub set_name			{ shift->{name}			= $_[1]	}
sub set_loop			{ shift->{loop}			= $_[1]	}
sub set_classes			{ shift->{classes}		= $_[1]	}
sub set_loaded_classes		{ shift->{loaded_classes}	= $_[1]	}
sub set_clients_connected	{ shift->{clients_connected}	= $_[1]	}
sub set_log_clients_connected	{ shift->{log_clients_connected}= $_[1]	}
sub set_logging_clients		{ shift->{logging_clients}	= $_[1]	}
sub set_logger			{ shift->{logger}		= $_[1]	}
sub set_start_log_listener	{ shift->{start_log_listener}	= $_[1]	}
sub set_objects			{ shift->{objects}		= $_[1]	}
sub set_rpc_socket		{ shift->{rpc_socket}		= $_[1]	}
sub set_ssl			{ shift->{ssl}			= $_[1]	}
sub set_ssl_key_file		{ shift->{ssl_key_file}		= $_[1]	}
sub set_ssl_cert_file		{ shift->{ssl_cert_file}	= $_[1]	}
sub set_ssl_passwd_cb		{ shift->{ssl_passwd_cb}	= $_[1]	}
sub set_auth_required		{ shift->{auth_required}	= $_[1]	}
sub set_auth_passwd_href	{ shift->{auth_passwd_href}	= $_[1]	}
sub set_listeners_started	{ shift->{listeners_started}	= $_[1]	}

my $INSTANCE;
sub instance { $INSTANCE }

sub new {
	my $class = shift;
	my %par = @_;
	my  ($port, $classes, $name, $logger, $start_log_listener) =
	@par{'port','classes','name','logger','start_log_listener'};
	my  ($ssl, $ssl_key_file, $ssl_cert_file, $ssl_passwd_cb) =
	@par{'ssl','ssl_key_file','ssl_cert_file','ssl_passwd_cb'};
	my  ($auth_required, $auth_passwd_href, $loop) =
	@par{'auth_required','auth_passwd_href','loop'};
	
	$name ||= "Event-RPC-Server";
	
	if ( not $loop ) {
		eval {
		    require Event::RPC::Loop::Event;
		    $loop = Event::RPC::Loop::Event->new;
		};
		if ( $@ ) {
		    eval {
			require Event::RPC::Loop::Glib;
			$loop = Event::RPC::Loop::Glib->new;
		    };
		    if ( $@ ) {
		    	die "It seems neither Event nor Glib are installed";
		    }
		}
	}

	my $self = bless {
		port			=> $port,
		name			=> $name,
		classes			=> $classes,
		logger			=> $logger,
		start_log_listener	=> $start_log_listener,
		loop			=> $loop,

		ssl			=> $ssl,
		ssl_key_file		=> $ssl_key_file,
		ssl_cert_file		=> $ssl_cert_file,
		ssl_passwd_cb		=> $ssl_passwd_cb,

		auth_required		=> $auth_required,
		auth_passwd_href	=> $auth_passwd_href,

		rpc_socket		=> undef,
		loaded_classes		=> {},
		objects			=> {},
		logging_clients		=> {},
		clients_connected	=> 0,
		listeners_started	=> 0,
	}, $class;

	$INSTANCE = $self;

	$self->log ($self->get_name." started");

	return $self;
}

sub DESTROY {
	my $self = shift;
	
	my $rpc_socket = $self->get_rpc_socket;
	close ($rpc_socket) if $rpc_socket;
	
	1;
}

sub setup_listeners {
	my $self = shift;

	my $port = $self->get_port;

	#-- load event loop manager
	my $loop = $self->get_loop;
	
	#-- setup rpc listener
	my $rpc_socket;
	if ( $self->get_ssl ) {
		eval { require IO::Socket::SSL };
		croak "SSL requested, but IO::Socket::SSL not installed" if $@;
		croak "ssl_key_file not set"  unless $self->get_ssl_key_file;
		croak "ssl_cert_file not set" unless $self->get_ssl_cert_file;

		$rpc_socket = IO::Socket::SSL->new (
			Listen    	=> SOMAXCONN,
			LocalPort 	=> $port,
			Proto     	=> 'tcp',
			SSL_verify_mode => 0x00,
			SSL_key_file	=> $self->get_ssl_key_file,
			SSL_cert_file	=> $self->get_ssl_cert_file,
			SSL_passwd_cb	=> $self->get_ssl_passwd_cb,
		) or die "can't start SSL RPC listener: $IO::Socket::SSL::ERROR";
	} else {
		$rpc_socket = IO::Socket::INET->new (
			Listen    => SOMAXCONN,
			LocalPort => $port,
			Proto     => 'tcp',
		) or die "can't start RPC listener: $!";
	}

	$self->set_rpc_socket($rpc_socket);

	$loop->add_io_watcher (
		fh	=> $rpc_socket,
		poll	=> 'r',
		cb	=> sub { $self->accept_new_client($rpc_socket); 1 },
		desc	=> "rpc listener port $port",
	);

	if ( $self->get_ssl ) {
		$self->log ("Started SSL RPC listener on port $port");
	} else {
		$self->log ("Started RPC listener on port $port");
	}

	# setup log listener
	if ( $self->get_start_log_listener ) {
		my $log_socket = IO::Socket::INET->new (
			Listen    => SOMAXCONN,
			LocalPort => $port + 1,
			Proto     => 'tcp',
		) or die "can't start log listener: $!";

		$loop->add_io_watcher (
			fh	=> $log_socket,
			poll	=> 'r',
			cb	=> sub { $self->accept_new_log_client($log_socket); 1 },
			desc	=> "log listener port ".($port+1),
		);

		$self->log ("Started log listener on port ".($port+1));
	}

	$self->set_listeners_started(1);

	1;
}

sub start {
	my $self = shift;

	$self->setup_listeners
		unless $self->get_listeners_started;

	my $loop = $self->get_loop;

	$self->log ("Enter main loop using $loop");

	$loop->enter;

	$self->log ("Server stopped");

	1;
}

sub stop {
	my $self = shift;

	$self->get_loop->leave;
	
	1;
}

sub accept_new_client {
	my $self = shift;
	my ($rpc_socket) = @_;

	my $client_socket = $rpc_socket->accept or return;

	Event::RPC::Server::Connection->new ($self, $client_socket);

	$self->set_clients_connected ( 1 + $self->get_clients_connected );

	1;
}

sub accept_new_log_client {
	my $self = shift;
	my ($log_socket) = @_;
	
	my $client_socket = $log_socket->accept or return;

	my $log_client =
		Event::RPC::Server::LogConnection->new($self, $client_socket);

	$self->set_log_clients_connected ( 1 + $self->get_log_clients_connected );
	$self->get_logging_clients->{$log_client->get_cid} = $log_client;

	$self->get_logger->add_fh($client_socket);

	$self->log(2, "New log client connected");

	1;
}

sub load_class {
	my $self = shift;
	my ($class) = @_;

	Event::RPC::Server::Connection->new ($self)->load_class($class);

	return $class;
}

sub log {
	my $self = shift;
	my $logger = $self->get_logger;
	return unless $logger;
	$logger->log(@_);
	1;
}

sub remove_object {
	my $self = shift;
	my ($object) = @_;
	
	my $objects = $self->get_objects;

	die "Object $object not registered" if not $objects->{"$object"};

	delete $objects->{"$object"};
	
	$self->log(5, "Object '$object' removed");

	1;
}

sub register_object {
	my $self = shift;
	my ($object, $class) = @_;
	
	my $objects = $self->get_objects;

	my $refcount;
	if ( $objects->{"$object"} ) {
		$refcount = ++$objects->{"$object"}->{refcount};
	} else {
		$refcount = 1;
		$objects->{"$object"} = {
			object   => $object,
			class    => $class,
			refcount => 1,
		};
	}
	
	$self->log(5, "Object '$object' registered. Refcount=$refcount");
	
	1;
}

sub deregister_object {
	my $self = shift;
	my ($object) = @_;
	
	my $objects = $self->get_objects;

	die "Object $object not registered" if not $objects->{"$object"};
	
	my $refcount = --$objects->{"$object"}->{refcount};

	$self->log(5, "Object '$object' deregistered. Refcount=$refcount");

	$self->remove_object($object) if $refcount == 0;
		
	1;
}

sub print_object_register {
	my $self = shift;
	
	print "-"x70,"\n";

	my $objects = $self->get_objects;
	foreach my $oid ( sort keys %{$objects} ) {
		print "$oid\t$objects->{$oid}->{refcount}\n";
	}
	
	1;
}

package Event::RPC::Server::Connection;

use Carp;
use Socket;

my $CONNECTION_ID;

sub get_cid			{ shift->{cid}				}
sub get_sock			{ shift->{sock}				}
sub get_server			{ shift->{server}			}
sub get_watcher			{ shift->{watcher}			}

sub get_classes			{ shift->{server}->{classes}		}
sub get_loaded_classes		{ shift->{server}->{loaded_classes}	}
sub get_objects			{ shift->{server}->{objects}		}
sub get_client_objects		{ shift->{client_objects}		}

sub set_watcher			{ shift->{watcher}		= $_[1]	}

sub get_message			{ shift->{message}			}
sub get_is_authorized		{ shift->{is_authorized}		}
sub get_auth_user		{ shift->{auth_user}			}

sub set_message			{ shift->{message}		= $_[1]	}
sub set_is_authorized		{ shift->{is_authorized}	= $_[1]	}
sub set_auth_user		{ shift->{auth_user}		= $_[1]	}

sub new {
	my $class = shift;
	my  ($server, $sock) = @_;

	my $cid = ++$CONNECTION_ID;
	
	my $self = bless {
		cid     		=> $cid,
		sock    		=> $sock,
		server  		=> $server,
		is_authorized		=> (!$server->get_auth_required),
		auth_user		=> "",
		watcher 		=> undef,
		message 		=> undef,
		client_objects		=> {},
	}, $class;

	if ( $sock ) {
		$self->log (2,
			"Got new RPC connection. Connection ID is $cid"
		);
		$self->{watcher} = $self->get_server->get_loop->add_io_watcher (
			fh   => $sock,
			poll => 'r',
			cb   => sub { $self->input; 1 },
			desc => "rpc client cid=$cid",
		);
	}
	
	return $self;
}

sub disconnect {
	my $self = shift;

	close $self->get_sock;
	$self->get_server->get_loop->del_io_watcher($self->get_watcher);
	$self->set_watcher(undef);

	my $server = $self->get_server;

	$server->set_clients_connected ( $self->get_server->get_clients_connected - 1 );

	foreach my $oid ( keys %{$self->get_client_objects} ) {
		$server->deregister_object($oid);
	}

	$self->log(2, "Client disconnected");

	1;
}

sub log {
	my $self = shift;

	my ($level, $msg);
	if ( @_ == 2 ) {
		($level, $msg) = @_;
	} else {
		($msg) = @_;
		$level = 1;
	}

	$msg = "cid=".$self->get_cid.": $msg";
	
	return $self->get_server->log ($level, $msg);
}

sub input {
	my $self = shift;
	my ($e) = @_;

	my $server  = $self->get_server;
	my $message = $self->get_message;

	if ( not $message ) {
		$message = Event::RPC::Message->new ($self->get_sock);
		$self->set_message($message);
	}

	my $request = eval { $message->read } || '';
	my $error = $@;

	return if not defined $request and not $error;

	$self->set_message(undef);

	return $self->disconnect
		if $request eq "DISCONNECT\n" or
		   $error =~ /DISCONNECTED/;

	my ($cmd, $rc);
	$cmd = $request->{cmd} if not $error;
	
	if ( $error ) {
		$self->log ("Unexpected error on incoming RPC call: $@");
		$rc = {
			ok  => 0,
			msg => "Unexpected error on incoming RPC call: $@",
		};

	} elsif ( $cmd eq 'auth' ) {
		$rc = $self->authorize_user ($request);

	} elsif ( $server->get_auth_required && !$self->get_is_authorized ) {
		$rc = {
			ok  => 0,
			msg => "Authorization required",			
		};

	} elsif ( $cmd eq 'new' ) {
		$rc = $self->create_new_object ($request);

	} elsif ( $cmd eq 'exec' ) {
		$rc = $self->execute_object_method ($request);

	} elsif ( $cmd eq 'classes_list' ) {
		$rc = $self->get_classes_list ($request);

	} elsif ( $cmd eq 'class_info' ) {
		$rc = $self->get_class_info ($request);

	} elsif ( $cmd eq 'client_destroy' ) {
		$rc = $self->object_destroyed_on_client ($request);

	} else {
		$self->log ("Unknown request command '$cmd'");
		$rc = {
			ok  => 0,
			msg => "Unknown request command '$cmd'",
		};
	}

	$message->write($rc) and return;

	my $watcher;
	$watcher = $self->get_server->get_loop->add_io_watcher (
		fh	=> $self->get_sock,
		poll	=> 'w',
		cb	=> sub {
		    $self->get_server->get_loop->del_io_watcher($watcher)
		    	if $message->write;
		    1;
		},
	);

	1;
}

sub authorize_user {
	my $self = shift;
	my ($request) = @_;
	
	my $user = $request->{user};
	my $pass = $request->{pass};
	
	my $auth_passwd_href = $self->get_server->get_auth_passwd_href;
	my $server_pass = $auth_passwd_href->{$user} || '';

	if ( $server_pass eq $pass ) {
		$self->set_auth_user($user);
		$self->set_is_authorized(1);
		$self->log("User '$user' successfully authorized");
		return {
			ok  => 1,
			msg => "Credentials Ok",
		};
	} else {
		$self->log("Illegal credentials for user '$user'");
		return {
			ok  => 0,
			msg => "Illegal credentials",
		};
	}
}

sub create_new_object {
	my $self = shift;
	my ($request) = @_;

	# Let's create a new object
	my $class_method = $request->{method};
	my $class = $class_method;
	$class =~ s/::[^:]+$//;
	$class_method =~ s/^.*:://;

	# check if access to this class/method is allowed
	if ( not defined $self->get_classes->{$class}->{$class_method} or
	     $self->get_classes->{$class}->{$class_method} ne '_constructor' ) {
		$self->log ("Illegal constructor access to $class->$class_method");
		return {
			ok  => 0,
			msg => "Illegal constructor access to $class->$class_method"
		};

	}
	
	# load the class if not done yet
	$self->load_class($class);

	# resolve object params
	$self->resolve_object_params ($request->{params});

	# ok, the class is there, let's execute the method
	my $object = eval {
		$class->$class_method (@{$request->{params}})
	};

	# report error
	if ( $@ ) {
		$self->log ("Error: can't create object ".
			    "($class->$class_method): $@");
		return {
			ok  => 0,
			msg => $@,
		};
	}

	# register object
	$self->get_server->register_object ($object, $class);
	$self->get_client_objects->{"$object"} = 1;

	# log and return
	$self->log (5,
		"Created new object $class->$class_method with oid '$object'",
	);

	return {
		ok  => 1,
		oid => "$object",
	};
}

sub load_class {
	my $self = shift;
	my ($class) = @_;
	
	my $mtime;
	my $load_class_info = $self->get_loaded_classes->{$class};

	if ( not $load_class_info or
	     ( $mtime = (stat($load_class_info->{filename}))[9])
		> $load_class_info->{mtime} ) {
	
		if ( not $load_class_info->{filename} ) {
			my $filename;
			my $rel_filename = $class;
			$rel_filename =~ s!::!/!g;
			$rel_filename .= ".pm";

			foreach my $dir ( @INC ) {
				$filename = "$dir/$rel_filename", last
					if -f "$dir/$rel_filename";
			}

			croak "File for class '$class' not found"
				if not $filename;
			
			$load_class_info->{filename} = $filename;
			$load_class_info->{mtime} = 0;
		}
	
		$mtime ||= 0;

		$self->log (3, "Class '$class' ($load_class_info->{filename}) changed on disk. Reloading...")
			if $mtime > $load_class_info->{mtime};

		do $load_class_info->{filename};

		if ( $@ ) {
			$self->log ("Can't load class '$class': $@");
			$load_class_info->{mtime} = 0;

			return {
				ok  => 0,
				msg => "Can't load class $class: $@",
			};

		} else {
			$self->log (3, "Class '$class' successfully loaded");
			$load_class_info->{mtime} = time;
		}
	}
	
	$self->log (5, "filename=".$load_class_info->{filename}.
		    ", mtime=".$load_class_info->{mtime} );

	$self->get_loaded_classes->{$class} ||= $load_class_info;

	1;
}

sub execute_object_method {
	my $self = shift;
	my ($request) = @_;

	# Method call of an existent object
	my $oid = $request->{oid};
	my $object_entry = $self->get_objects->{$oid};
	my $method = $request->{method};

	if ( not defined $object_entry ) {
		# object does not exists
		$self->log ("Illegal access to unknown object with oid=$oid");
		return {
			ok  => 0,
			msg => "Illegal access to unknown object with oid=$oid"
		};

	}
	
	my $class = $object_entry->{class};
	if ( not defined $self->get_classes->{$class}->{$method} ) {
		# illegal access to this method
		$self->log ("Illegal access to $class->$method");
		return {
			ok  => 0,
			msg => "Illegal access to $class->$method"
		};

	}
	
	# (re)load the class if not done yet
	$self->load_class($class);

	# resolve object params
	$self->resolve_object_params ($request->{params});

	# ok, try executing the method
	my @rc = eval {
		$object_entry->{object}->$method (@{$request->{params}})
	};

	# report error
	if ( $@ ) {
		$self->log ("Error: can't call '$method' of object ".
			    "with oid=$oid: $@");
		return {
			ok  => 0,
			msg => $@,
		};
	}
	
	# log
	$self->log (4, "Called method '$method' of object ".
		       "with oid=$oid");

	# check if objects are returned by this method
	# and register them in our internal object table
	# (if not already done yet)
	my $key;
	foreach my $rc ( @rc ) {
		if ( ref ($rc) and ref ($rc) !~ /ARRAY|HASH|SCALAR/ ) {
			# returns a single object
			$self->log (4, "Method returns object: $rc");
			$key = "$rc";
			$self->get_client_objects->{$key} = 1;
			$self->get_server->register_object($rc, ref $rc);
			$rc = $key;

		} elsif ( ref $rc eq 'ARRAY' ) {
			# possibly returns a list of objects
			# make a copy, otherwise the original object references
			# will be overwritten
			my @val = @{$rc};
			$rc = \@val;
			foreach my $val ( @val ) {
				if ( ref ($val) and ref ($val) !~ /ARRAY|HASH|SCALAR/ ) {
					$self->log (4, "Method returns object lref: $val");
					$key = "$val";
					$self->get_client_objects->{$key} = 1;
					$self->get_server->register_object($val, ref $val);
					$val = $key;
				}
			}
		} elsif ( ref $rc eq 'HASH' ) {
			# possibly returns a hash of objects
			# make a copy, otherwise the original object references
			# will be overwritten
			my %val = %{$rc};
			$rc = \%val;
			foreach my $val ( values %val ) {
				if ( ref ($val) and ref ($val) !~ /ARRAY|HASH|SCALAR/ ) {
					$self->log (4, "Method returns object href: $val");
					$key = "$val";
					$self->get_client_objects->{$key} = 1;
					$self->get_server->register_object($val, ref $val);
					$val = $key;
				}
			}
		}
	}

	# return rc
	return {
		ok => 1,
		rc => \@rc,
	};
}

sub object_destroyed_on_client {
	my $self = shift;
	my ($request) = @_;

	$self->log(5, "Object with oid=$request->{oid} destroyed on client");

	delete $self->get_client_objects->{$request->{oid}};
	$self->get_server->deregister_object($request->{oid});

	return {
		ok => 1
	};
}

sub get_classes_list {
	my $self = shift;
	my ($request) = @_;

	my @classes = keys %{$self->get_classes};
	
	return {
		ok      => 1,
		classes => \@classes,
	}
}

sub get_class_info {
	my $self = shift;
	my ($request) = @_;

	my $class = $request->{class};
	
	if ( not defined $self->get_classes->{$class} ) {
		$self->log ("Unknown class '$class'");
		return {
			ok  => 0,
			msg => "Unknown class '$class'"
		};
	}
	
	$self->log (4, "Class info for '$class' requested");

	return {
		ok           => 1,
		methods      => $self->get_classes->{$class},
	};
}

sub resolve_object_params {
	my $self = shift;
	my ($params) = @_;
	
	my $key;
	foreach my $par ( @{$params} ) {
		if ( defined $self->get_classes->{ref($par)} ) {
			$key = ${$par};
			$key = "$key";
			croak "unknown object with key '$key'"
				if not defined $self->get_objects->{$key};
			$par = $self->get_objects->{$key}->{object};
		}
	}
	
	1;
}


package Event::RPC::Server::LogConnection;

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
		poll => 're',
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

	my $sock = $self->get_sock;
	$self->disconnect if eof($sock);
	<$sock>;
	
	1;
}

1;

__END__

=head1 NAME

Event::RPC::Server - Simple API for event driven RPC servers

=head1 SYNOPSIS

  use Event::RPC::Server;
  use My::TestModule;

  my $server = Event::RPC::Server->new (
      #-- Required arguments
      port               => 8888,
      classes            => {
        "My::TestModule" => {
	  new      => "_constructor",
	  get_data => 1,
	  set_data => 1,
	  clone    => "_object",
	},
      },

      #-- Optional arguments
      name               => "Test server",
      logger             => Event::RPC::Logger->new(),
      start_log_listener => 1,

      ssl                => 1
      ssl_key_file       => "server.key",
      ssl_cert_file      => "server.crt",
      ssl_passwd_cb      => sub { "topsecret" },

      auth_required      => 1,
      auth_passwd_href   => { $user => Event::RPC->crypt($user,$pass) },

      loop               => Event::RPC::Loop::Event->new(),
  );

  $server->start;

  # and later from inside your server implementation
  Event::RPC::Server->instance->stop;

=head1 DESCRIPTION

Use this module to add a simple to use RPC mechanism to your event
driven server application.

Just create an instance of the Event::RPC::Server class with a
bunch of required settings. Then enter the main event loop through
it, or take control over the main loop on your own if you like
(refer to the MAINLOOP chapter for details).

General information about the architecture of Event::RPC driven
applications is collected in the Event::RPC manpage.

The following documentation describes mainly the options passed to the
new() constructor of Event::RPC::Server, divided into several topics.

=head1 CONFIGURATION OPTIONS

=head2 REQUIRED OPTIONS

If you just pass the required options listed beyond you have
a RPC server which listens to a network port and allows everyone
connecting to it to access a well defined list of classes and methods
resp. using the correspondent server objects.

There is no authentication or encryption active in this minimal
configuration, so aware that this may be a big security risk!
Adding security is easy, refer to the chapters about SSL and
authentication.

These are the required options:

=over 4

=item B<port>

TCP port number of the RPC listener.

=item B<classes>

This is a hash ref with the following structure:

  classes => {
    "Class1" => {
      new             => "_constructor",
      simple_method   => 1,
      object_returner => "_object",
    },
    "Class2" => { ... },
    ...
  },

Each class which should be accessable for clients needs to
be listed here at the first level, assigned a hash of methods
allowed to be called. Event::RPC disuinguishes three types
of methods by classifying their return value:

=over 4

=item B<Constructors>

A constructor method creates a new object of the corresponding class
and returns it. You need to assign the string "_constructor" to
the method entry to mark a method as a constructor.

=item B<Simple methods>

What's simple about these methods is their return value: it's
a scalar, array, hash or even any complex reference structure
(Ok, not simple anymore ;), but in particular it returns B<NO> objects,
because this needs to handled specially (see below).

Declare simple methods by assigning 1 in the method declaration.

=item B<Object returners>

Methods which return objects need to be declared by assigning
"_object" to the method name here. They're not bound to return
just one scalar object reference and may return an array or list
reference with a bunch of objects as well.

=back

=back

=head2 SSL OPTIONS

The client/server protocol of Event::RPC is not encrypted by default,
so everyone listening on your network can read or even manipulate
data. To prevent this efficiently you can enable SSL encryption.
Event::RPC uses the IO::Socket::SSL Perl module for this.

First you need to generate a server key and certificate for your server
using the openssl command which is part of the OpenSSL distribution,
e.g. by issueing these commands (please refer to the manpage of openssl
for details - this is a very rough example, which works in general, but
probably you want to tweak some parameters):

  % openssl genrsa -des3 -out server.key 1024
  % openssl req -new -key server.key -out server.csr
  % openssl x509 -req -days 3600 -in server.csr \
            -signkey server.key -out server.crt

After executing these commands you have the following files

  server.crt
  server.key
  server.csr

Event::RPC needs the first two of them to operate with SSL encryption.

To enable SSL encryption you need to pass the following options
to the constructor:

=over 4

=item B<ssl>

The ssl option needs to be set to 1.

=item B<ssl_key_file>

This is the filename of the server.key you generated with
the openssl command.

=item B<ssl_cert_file>

This is the filename of the server.crt file you generated with
the openssl command.

=item B<ssl_passwd_cb>

Your server key is encrypted with a password you entered during the
key creation process described above. This callback must return
it. Depending on how critical your application is you probably must
request the password from the user during server startup or place it
into a more or less secured file. For testing purposes you
can specify a simple anonymous sub here, which just returns the
password, e.g.

  ssl_passwd_cb => sub { return "topsecret" }

But note: having the password in plaintext in your program code is
insecure!

=back

=head2 AUTHENTICATION OPTIONS

SSL encryptiong is fine, now it's really hard for an attacker to
listen or modify your network communication. But without any further
configuration any user on your network is able to connect to your
server. To prevent this users resp. connections to your server
needs to be authenticated somehow.

Event::RPC has a simple user/password based model for this. For now
this controls just the right to connect to your server, so knowing
one valid user/password pair is enough to access all exported methods
of your server. Probably a more differentiated model will be added later
which allows granting access to a subset of exported methods only
for each user who is allowed to connect.

The following options control the authentication:

=over 4

=item B<auth_required>

Set this to 1 to enable authentication and nobody can connect your server
until he passes a valid user/password pair.

=item B<auth_passwd_href>

This is a hash of valid user/password pairs. The password stored here
needs to be encrypted using Perl's crypt() function, using the username
as the salt.

Event::RPC has a convenience function for generating such a crypted
password, although it's currently just a 1:1 wrapper around Perl's
builtin crypt() function, but probably this changes someday, so better
use this method:

  $crypted_pass = Event::RPC->crypt($user, $pass);

This is a simple example of setting up a proper B<auth_passwd_href> with
two users:

  auth_passwd_href => {
    fred => Event::RPC->crypt("fred", $freds_password),
    nick => Event::RPC->crypt("nick", $nicks_password),
  },

=back

B<Note:> you can use the authentication module without SSL but aware that
an attacker listening to the network connection will be able to grab
the encrypted password token and authenticate himself with it to the
server (replay attack). Probably a more sophisticated challenge/response
mechanism will be added to Event::RPC to prevent this. But you definitely
should use SSL encryption in a critical environment anyway, which renders
grabbing the password from the net impossible.

=head2 LOGGING OPTIONS

Event::RPC has some logging abilities, primarily for debugging purposes.
It uses a B<logger> for this, which is an object implementing the
Event::RPC::Logger interface. The documentation of Event::RPC::Logger
describes this interface and Event::RPC's logging facilities in general.

=over 4

=item B<logger>

To enable logging just pass such an Event::RPC::Logger object to the
constructor.

=item B<start_log_listener>

Additionally Event::RPC can start a log listener on the server's port
number incremented by 1. All clients connected to this port (e.g. by
using telnet) get the server's log output.

Note: currently the logging port supports neither SSL nor authentication,
so be careful enabling the log listener in critical environments.

=back

=head2 MAINLOOP OPTIONS

Event::RPC derived it's name from the fact that it follows the event
driven paradigma. There are several toolkits for Perl which allow
event driven software development. Event::RPC has an abstraction layer
for this and thus should be able to work with any toolkit.

=over 4

=item B<loop>

This option takes an object of the loop abstraction layer you
want to user. Currently the following modules are implemented:

  Event::RPC::Loop::Event     Use the Event module
  Event::RPC::Loop::Glib      Use the Glib module

If B<loop> isn't set, Event::RPC::Server tries all supported modules
in a row and aborts the program, if no module was found.

More modules will be added in the future. If you want to implement one
just take a look at the code in the modules above: it's really
easy and I appreciate your patch. The interface is roughly described
in the documentation of Event::RPC::Loop.

=back

If you use the Event::RPC->start() method as described in the SYNOPSIS
Event::RPC will enter the correspondent main loop for you. If you want
to have full control over the main loop, use this method to setup
all necessary Event::RPC listeners:

  $server->setup_listeners();

and manage the main loop stuff on your own.

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
