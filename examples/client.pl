#!/usr/bin/perl -w

use strict;

use lib 'lib';
use lib qw(../lib);
use Event::RPC::Client;
use Getopt::Std;

my $USAGE = <<__EOU;

Usage: client.pl [-s] [-a user:pass]

Description:
  Event::RPC client demonstration program. Execute this from
  the distribution's base or examples/ directory after starting
  the correspondent examples/server.pl program.

Options:
  -s             Use SSL encryption
  -a user:pass   Pass this authorization data to the server

__EOU

sub HELP_MESSAGE {
	my ($fh) = @_;
	$fh ||= \*STDOUT;
	print $fh $USAGE;
	exit;
}

main: {
    my %opts;
    my $opts_ok = getopts('l:a:s',\%opts);
   
    HELP_MESSAGE() unless $opts_ok;

    my $ssl = $opts{s} || 0;

    my %auth_args;
    if ( $opts{a} ) {
      my ($user, $pass) = split(":", $opts{a}); 
      $pass = Event::RPC->crypt($user,$pass);
      %auth_args = (
	auth_user => $user,
	auth_pass => $pass,
      );
    }

    #-- This connects to the server, requests the exported
    #-- interfaces and establishes correspondent proxy methods
    #-- in the correspondent packages.
    my $client;
    $client = Event::RPC::Client->new (
      host     => "localhost",
      port     => 5555,
      ssl      => $ssl,
      %auth_args,
      error_cb => sub {
        my ($client, $error) = @_;
      	print "An RPC error occured: $_[0]";
	print "Disconnect and exit.\n";
	$client->disconnect if $client;
	exit
      },
      classes => [ "Test_class", "Foo" ],
    );

    $client->connect;

    print "Connected to localhost:5555\n";
    print "Server version:  ".$client->get_server_version,"\n";
    print "Server protocol: ".$client->get_server_protocol,"\n\n";

    #-- So the call to Event::RPC::Test->new is handled transparently
    #-- by Event::RPC::Client
    my $object = Test_class->new (
	    data => "Some test data. " x 6
    );

    #-- and methods calls as well...
    print "hello=".$object->hello,"\n";
    $object->set_data ("changed data");
    print "data=".$object->get_data."\n";

    #-- disconnection is handled by the destructor of $client	
}
