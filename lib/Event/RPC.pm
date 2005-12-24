package Event::RPC;

$VERSION  = "0.88";
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

=head1 REQUIREMENTS

Event::RPC needs either one of the following modules on the server
(they're not necessary on the client):

  Event
  Glib

They're needed for event handling resp. mainloop implementation.
If you like to use SSL encryption you need to install

  IO::Socket::SSL

As well Event::RPC makes heavy use of the

  Storable

module, which is part of the Perl standard library. It's important
that both client and server use B<exactly the same version of the Storable
module>! Otherwise Event::RPC client/server communication will fail badly.

=head1 INSTALLATION

If your system meets the requirements mentioned above, installation
is just:

  perl Makefile.PL
  make test
  make install

=head1 EXAMPLES

The tarball includes an examples/ directory which contains two
programs:

  server.pl
  client.pl

Just execute them with --help to get the usage. They do some very
simple communication but are good to test your setup, in particular
in a mixed environment.

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
