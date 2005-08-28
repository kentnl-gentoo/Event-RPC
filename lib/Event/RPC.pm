package Event::RPC;

$VERSION  = "0.85";
$PROTOCOL = "1.00";

sub crypt {
	my $class = shift;
	my ($user, $pass) = @_;
	return crypt($pass, $user);
}

__END__

=head1 NAME

Event::RPC - Event based transparent Client/Server RPC framework

=head1 SYNOPSIS

  #-- Server Code
  use Event::RPC::Server;
  use My::TestModule;
  my $server = Event::RPC::Server->new (
      port    => 5555,
      classes => { "My::TestModule" => { ... } },
  );
  $server->start;

  ----------------------------------------------------------
  
  #-- Client Code
  use Event::RPC::Client;
  my $client = Event::RPC::Client->new (
      server   => "localhost",
      port     => 5555,
  );
  $client->connect;

  #-- Call methods of My::TestModule on the server
  my $obj = My::TestModule->new ( foo => "bar" );
  my $foo = $obj->get_foo;

=head1 ABSTRACT

Event::RPC supports you in developing Event based networking client/server applications with transparent object/method access from the client to the server. Network communication is optionally encrypted using IO::Socket::SSL. Several event loop managers are supported due to an extensible API. Currently Event and Glib are implemented.

=head1 DESCRIPTION

Event::RPC consists of a server and a client library. The server exports a list of classes and methods, which are allowed to be called over the network. More specific it acts as a proxy for objects created on the server side (on demand of the connected clients) which handles client side methods calls with transport of method arguments and return values.

The object proxy handles refcounting and destruction of objects created by clients properly. Objects as method parameters and return values are handled as well (although with some limitations, see below).

For the client the whole thing is totally transparent - once connected to the server it doesn't know whether it calls methods on local or remote objects.

Also the methods on the server newer know whether they are called locally
or from a connected client. Your application logic is not affected by Event::RPC at all, at least if it has a rudimentary clean OO design.

For details on implementing servers and clients please refer to the man pages of Event::RPC::Server and Event::RPC::Client.

=head1 COMPLETE EXAMPLE

  Server:
  ==================================================

  use strict;
  use Event::RPC::Server;

  main: {
      #-- Create a Server instance and declare the
      #-- exported interface
      my $server = Event::RPC::Server->new (
        name    => "test daemon",
        port    => 5555,
        classes => {
          'Event::RPC::Test' => {
            new       => '_constructor', # Class constructor
            set_data  => 1,              # and 'normal' methods...
            get_data  => 1,
            hello     => 1,
          },
        },
      );

      #-- Start the server resp. the Event loop.
      $server->start;
  }

  #-- A simple test class

  package Event::RPC::Test;

  sub get_data  { shift->{data}         }
  sub set_data  { shift->{data} = $_[1] }

  sub new {
      my $class = shift;
      my %par = @_;
      my ($data) = $par{'data'};

      my $self = bless { data => $data };

      return $self;
  }

  sub hello {
      my $self = shift;
      return "I have this data: '".$self->get_data."'";
  }

  Client:
  ==================================================

  use strict;

  use Event::RPC::Client;

  main: {
      #-- This connects to the server, requests the exported
      #-- interfaces and establishes proxy methods
      #-- in the correspondent packages.
      my $client = Event::RPC::Client->new (
        server   => "localhost",
        port     => 5555,
        error_cb => sub { print "An RPC error occured\n"; exit },
      );

      #-- Connect the client to the server
      $client->connect;

      #-- From now on the call to Event::RPC::Test->new is
      #-- handled transparently by Event::RPC::Client
      my $object = Event::RPC::Test->new (
              data => "some test data" x 5
      );

      #-- and method calls as well...
      print "hello=".$object->hello,"\n";
      $object->set_data ("changed data");
      print "data=".$object->get_data."\n";

      #-- disconnection is handled by the destructor of $client 
      #-- or disconnect explictly
      $client->disconnect;
  }

=head1 LIMITATIONS

Although the classes and objects on the server are accessed
transparently by the client there are some limitations should
be aware of. With a clean object oriented design these should
be no problem in real applications:

=head2 Direct object data manipulation is forbidden

All objects reside on the server and they keep there! The client
just has specially wrapped proxy objects, which trigger the
necessary magic to access the object's B<methods> on the server. Complete
objects are never transferred from the server to the client,
so something like this does B<not> work:

  $object->{data} = "changed data";

(assuming $object is a hash ref on the server).

Only method calls are transferred to the server, so even for
"simple" data manipulation a method call is necessary:

  $object->set_data ("changed data");

As well for reading an object attribute. Accessing a hash
key will fail:

  my $data = $object->{data};

Instead call a method which returns the 'data' member:

  my $data = $object->get_data;

=head2 Methods may exchange objects, but not in a too complex structure

Event::RPC handles methods which return objects. The only
requirement is that they are declared as a B<Object returner>
on the server (refer to Event::RPC::Server for details),
but not if the object is hided inside a deep complex data structure.

An array or hash ref of objects is Ok, but not more. This
would require to much expensive runtime data inspection.

Object receiving parameters are more restrictive,
since even hiding them inside one array or hash ref is not allowed.
They must be passed as a direkt argument of the method subroutine.

=head2 Using the same class locally and remotely is impossible

It's not possible to create resp. use local objects from a
class which was exported by a server the client is connected
to (and vice versa).

Event::RPC::Client registers all exported methods in the local
namespace of the correspondent classes, so having the same method
locally and remotely can't be done, because the methods would
override each other.

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
