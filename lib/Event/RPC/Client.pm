# $Id: Client.pm,v 1.12 2006/04/23 08:37:41 joern Exp $

#-----------------------------------------------------------------------
# Copyright (C) 2002-2006 Jörn Reder <joern AT zyn.de>.
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
use IO::Socket::INET;

sub get_client_version          { $Event::RPC::VERSION                  }
sub get_client_protocol         { $Event::RPC::PROTOCOL                 }

sub get_host                    { shift->{host}                         }
sub get_port                    { shift->{port}                         }
sub get_sock                    { shift->{sock}                         }
sub get_classes                 { shift->{classes}                      }
sub get_class_map               { shift->{class_map}                    }
sub get_loaded_classes          { shift->{loaded_classes}               }
sub get_error_cb                { shift->{error_cb}                     }
sub get_ssl                     { shift->{ssl}                          }
sub get_auth_user               { shift->{auth_user}                    }
sub get_auth_pass               { shift->{auth_pass}                    }
sub get_connected               { shift->{connected}                    }
sub get_server                  { shift->{server}                       }
sub get_server_version          { shift->{server_version}               }
sub get_server_protocol         { shift->{server_protocol}              }

sub set_host                    { shift->{host}                 = $_[1] }
sub set_port                    { shift->{port}                 = $_[1] }
sub set_sock                    { shift->{sock}                 = $_[1] }
sub set_classes                 { shift->{classes}              = $_[1] }
sub set_class_map               { shift->{class_map}            = $_[1] }
sub set_loaded_classes          { shift->{loaded_classes}       = $_[1] }
sub set_error_cb                { shift->{error_cb}             = $_[1] }
sub set_ssl                     { shift->{ssl}                  = $_[1] }
sub set_auth_user               { shift->{auth_user}            = $_[1] }
sub set_auth_pass               { shift->{auth_pass}            = $_[1] }
sub set_connected               { shift->{connected}            = $_[1] }
sub set_server                  { shift->{server}               = $_[1] }
sub set_server_version          { shift->{server_version}       = $_[1] }
sub set_server_protocol         { shift->{server_protocol}      = $_[1] }

sub new {
    my $class = shift;
    my %par   = @_;
    my  ($server, $host, $port, $classes, $class_map, $error_cb) =
    @par{'server','host','port','classes','class_map','error_cb'};
    my  ($ssl, $auth_user, $auth_pass) =
    @par{'ssl','auth_user','auth_pass'};

    $server ||= '';
    $host   ||= '';

    if ( $server ne '' and $host eq '' ) {
        warn "Option 'server' is deprecated. Use 'host' instead.";
        $host = $server;
    }

    my $self = bless {
        host           => $server,
        server         => $host,
        port           => $port,
        classes        => $classes,
        class_map      => $class_map,
        ssl            => $ssl,
        auth_user      => $auth_user,
        auth_pass      => $auth_pass,
        error_cb       => $error_cb,
        loaded_classes => {},
        connected      => 0,
    }, $class;

    return $self;
}

sub connect {
    my $self = shift;

    croak "Client is already connected" if $self->get_connected;

    my $ssl    = $self->get_ssl;
    my $server = $self->get_server;
    my $port   = $self->get_port;

    if ($ssl) {
        eval { require IO::Socket::SSL };
        croak "SSL requested, but IO::Socket::SSL not installed" if $@;
    }

    my $sock;
    if ($ssl) {
        $sock = IO::Socket::SSL->new(
            Proto    => 'tcp',
            PeerPort => $port,
            PeerAddr => $server,
            Type     => SOCK_STREAM
            )
            or croak
            "Can't open SSL connection to $server:$port: $IO::Socket::SSL::ERROR";
    }
    else {
        $sock = IO::Socket::INET->new(
            Proto    => 'tcp',
            PeerPort => $port,
            PeerAddr => $server,
            Type     => SOCK_STREAM
            )
            or croak "Can't open connection to $server:$port - $!";
    }

    $sock->autoflush(1);

    $self->set_sock($sock);

    $self->check_version;

    my $auth_user = $self->get_auth_user;
    my $auth_pass = $self->get_auth_pass;

    if ($auth_user) {
        my $rc = $self->send_request(
            {   cmd  => 'auth',
                user => $auth_user,
                pass => $auth_pass,
            }
        );
        if ( not $rc->{ok} ) {
            $self->disconnect;
            croak $rc->{msg};
        }
    }

    if ( not $self->get_classes ) {
        $self->load_all_classes;
    }
    else {
        $self->load_classes;
    }

    $self->set_connected(1);

    1;
}

sub log_connect {
    my $class = shift;
    my %par   = @_;
    my ( $server, $port ) = @par{ 'server', 'port' };

    my $sock = IO::Socket::INET->new(
        Proto    => 'tcp',
        PeerPort => $port,
        PeerAddr => $server,
        Type     => SOCK_STREAM
        )
        or croak "Can't open connection to $server:$port - $!";

    return $sock;
}

sub disconnect {
    my $self = shift;

    close( $self->get_sock ) if $self->get_sock;
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

    if ($error_cb) {
        &$error_cb( $self, $message );
    }
    else {
        die "Unhandled error in client/server communication: $message";
    }

    1;
}

sub check_version {
    my $self = shift;

    my $rc = $self->send_request( { cmd => 'version', } );

    $self->set_server_version( $rc->{version} );
    $self->set_server_protocol( $rc->{protocol} );

    if ( $rc->{version} ne $self->get_client_version ) {
        warn "Event::RPC warning: server version $rc->{version} != "
            . "client version "
            . $self->get_client_version;
    }

    if ( $rc->{protocol} < $self->get_client_protocol ) {
        die "FATAL: Server protocol version $rc->{protocol} < "
            . "client protocol version "
            . $self->get_client_protocol;
    }

    1;
}

sub load_all_classes {
    my $self = shift;

    my $rc = $self->send_request( { cmd => 'class_info_all', } );

    my $class_info_all = $rc->{class_info_all};

    foreach my $class ( keys %{$class_info_all} ) {
        $self->load_class( $class, $class_info_all->{$class} );
    }

    1;
}

sub load_classes {
    my $self = shift;

    my $classes = $self->get_classes;
    my %classes;
    @classes{ @{$classes} } = (1) x @{$classes};

    my $rc = $self->send_request( { cmd => 'classes_list', } );

    foreach my $class ( @{ $rc->{classes} } ) {
        next if not $classes{$class};
        $classes{$class} = 0;

        my $rc = $self->send_request(
            {   cmd   => 'class_info',
                class => $class,
            }
        );

        $self->load_class( $class, $rc->{methods} );
    }

    foreach my $class ( @{$classes} ) {
        warn "WARNING: Class '$class' not exported by server"
            if $classes{$class};
    }

    1;
}

sub load_class {
    my $self = shift;
    my ( $class, $methods ) = @_;

    my $loaded_classes = $self->get_loaded_classes;
    return 1 if $loaded_classes->{$class};
    $loaded_classes->{$class} = 1;

    my $local_method;
    my $class_map   = $self->get_class_map;
    my $local_class = $class_map->{$class} || $class;

    # create local destructor for this class
    {
        no strict 'refs';
        my $local_method = $local_class . '::' . "DESTROY";
        *$local_method = sub {
            return if not $self->get_connected;
            my $oid_ref = shift;
            $self->send_request({
                cmd => "client_destroy",
                oid => ${$oid_ref},
            });
        };
    }

    # create local methods for this class
    foreach my $method ( keys %{$methods} ) {
        $local_method = $local_class . '::' . $method;

        my $method_type = $methods->{$method};

        if ( $method_type eq '_constructor' ) {
            # this is a constructor for this class
            my $request_method = $class . '::' . $method;
            no strict 'refs';
            *$local_method = sub {
                shift;
                my $rc = $self->send_request({
                    cmd    => 'new',
                    method => $request_method,
                    params => \@_,
                });
                my $oid = $rc->{oid};
                return bless \$oid, $local_class;
            };
        }
        elsif ( $method_type eq '1' ) {
            # this is a simple method
            my $request_method = $method;
            no strict 'refs';
            *$local_method = sub {
                my $oid_ref = shift;
                my $rc = $self->send_request({
                    cmd    => 'exec',
                    oid    => ${$oid_ref},
                    method => $request_method,
                    params => \@_,
                });
                return unless $rc;
                $rc = $rc->{rc};
                return @{$rc} if wantarray;
                return $rc->[0];
            };
        }
        else {
            # this is a object returner
            my $request_method = $method;
            no strict 'refs';
            *$local_method = sub {
                my $oid_ref = shift;
                my $rc      = $self->send_request({
                    cmd    => 'exec',
                    oid    => ${$oid_ref},
                    method => $request_method,
                    params => \@_,
                });
                return unless $rc;
                $rc = $rc->{rc};

                foreach my $val ( @{$rc} ) {
                    if ( ref $val eq 'ARRAY' ) {
                        foreach my $list_elem ( @{$val} ) {
                            my ($class) = split( "=", "$list_elem", 2 );
                            $self->load_class($class)
                                unless $loaded_classes->{$class};
                            my $list_elem_copy = $list_elem;
                            $list_elem = \$list_elem_copy;
                            bless $list_elem,
                                ( $class_map->{$class} || $class );
                        }
                    }
                    elsif ( ref $val eq 'HASH' ) {
                        foreach my $hash_elem ( values %{$val} ) {
                            my ($class) = split( "=", "$hash_elem", 2 );
                            $self->load_class($class)
                                unless $loaded_classes->{$class};
                            my $hash_elem_copy = $hash_elem;
                            $hash_elem = \$hash_elem_copy;
                            bless $hash_elem,
                                ( $class_map->{$class} || $class );
                        }
                    }
                    elsif ( defined $val ) {
                        my ($class) = split( "=", "$val", 2 );
                        $self->load_class($class)
                            unless $loaded_classes->{$class};
                        my $val_copy = $val;
                        $val = \$val_copy;
                        bless $val, ( $class_map->{$class} || $class );
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

    my $message = Event::RPC::Message->new( $self->get_sock );

    $message->write_blocked($request);

    my $rc = eval { $message->read_blocked };

    if ($@) {
        $self->error($@);
        return;
    }

    if ( not $rc->{ok} ) {
        $rc->{msg} .= "\n" if not $rc->{msg} =~ /\n$/;
        croak ("$rc->{msg} -- called via Event::RPC::Client");
    }

    return $rc;
}

1;

__END__

=head1 NAME

Event::RPC::Client - Client API to connect to Event::RPC Servers

=head1 SYNOPSIS

  use Event::RPC::Client;

  my $rpc_client = Event::RPC::Client->new (
    #-- Required arguments
    host => "localhost",
    port => 5555,
    
    #-- Optional arguments
    classes   => [ "Event::RPC::Test" ],
    class_map => { "Event::RPC::Test" => "My::Event::RPC::Test" },

    ssl       => 1,

    auth_user => "fred",
    auth_pass => Event::RPC->crypt("fred",$password),

    error_cb => sub {
      my ($client, $error) = @_;
      print "An RPC error occured: $error\n";
      $client->disconnect;
      exit;
    },
  );

  $rpc_client->connect;
  
  #-- And now use classes and methods the server
  #-- allows to access via RPC, here My::TestModule
  #-- from the Event::RPC::Server manpage SYNPOSIS.
  my $obj = My::TestModule->new( data => "foobar" );
  print "obj says hello: ".$obj->hello."\n";
  $obj->set_data("new foobar");
  print "updated data: ".$obj->get_data."\n";

  $rpc_client->disconnect;

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

All options described here may be passed to the new() constructor of
Event::RPC::Client. As well you may set or modify them using set_OPTION style
mutators, but not after connect() was called!
All options may be read using get_OPTION style accessors.

=head2 REQUIRED OPTIONS

These are necessary to connect the server:

=over 4

=item B<server>

This is the hostname of the server running Event::RPC::Server.
Use a IP address or DNS name here.

=item B<port>

This is the TCP port the server is listening to.

=back

=head2 CLASS IMPORT OPTION

=over 4

=item B<classes>

This is reference to a list of classes which should be imported
into the client. You get a warning if you request a class which
is not exported by the server.

By default all server classes are imported. Use this feature if
your server exports a huge list of classes, but your client
doesn't need all of them. This saves memory in the client and
connect performance increases.

=item B<class_map>

Optionally you can map the class names from the server to a
different name on the local client using the B<class_map> hash.

This is necessary if you like to use the same classes locally
and remotely. Imported classes from the server are by default
registered under the same name on the client, so this conflicts
with local classes named identically.

On the client you access the remote classes under the name
assigned in the class map. For example with this map

  class_map => { "Event::ExecFlow::Job" => "_srv::Event::ExecFlow::Job" }

you need to write this on the client, if you like to create
an object remotely on the server:

  my $server_job = _srv::Event::ExecFlow::Job->new ( ... );

and this to create an object on the client:

  my $client_job = Event::ExecFlow::Job->new ( ... );

The server knows nothing of the renaming on client side, so you
still write this on the server to create objects there:

  my $job = Event::ExecFlow::Job->new ( ... );

=back

=head2 SSL OPTION

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
password, although it's currently just a wrapper around Perl's
builtin crypt() function, but probably this changes someday, so better
use this method:

  $crypted_pass = Event::RPC->crypt($user, $pass);

=back

If the passed credentials are invalid the Event::RPC::Client->connect()
method throws a correspondent exception.

=head2 ERROR HANDLING

Any exceptions thrown on the server during execution of a remote
method will result in a corresponding exception on the client. So
you can use normal exception handling with eval {} when executing
remote methods.

But besides this the network connection between your client and
the server may break at any time. This raises an exception as well,
but you can override this behaviour with the following attribute:

=over 4

=item B<error_cb>

This subroutine is called if any error occurs in the network
communication between the client and the server. The actual
Event::RPC::Client object and an error string are passed
as arguments.

This is B<no> generic exception handler for exceptions thrown from the
executed methods on the server! If you like to catch such
exceptions you need to put an eval {} around your method calls,
as you would do for local method calls.

If you don't specify an B<error_cb> an exception is thrown instead.

=back

=head1 METHODS

=over 4

=item $rpc_client->B<connect>

This establishes the configured connection to the server. An exception
is thrown if something goes wrong, e.g. server not available, credentials
are invalid or something like this.

=item $rpc_client->B<disconnect>

Closes the connection to the server. You may omit explicit disconnecting
since it's done automatically once the Event::RPC::Client object gets
destroyed.

=back

=head1 READY ONLY ATTRIBUTES

=over 4

=item $rpc_client->B<get_server_version>

Returns the Event::RPC version number of the server after connecting.

=item $rpc_client->B<get_server_protocol>

Returns the Event::RPC protocol number of the server after connecting.

=item $rpc_client->B<get_client_version>

Returns the Event::RPC version number of the client.

=item $rpc_client->B<get_client_protocol>

Returns the Event::RPC protocol number of the client.

=back

=head1 AUTHORS

  Jörn Reder <joern at zyn dot de>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2002-2006 by Joern Reder, All Rights Reserved.

This library is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=cut
