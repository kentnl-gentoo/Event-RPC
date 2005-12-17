package Event_RPC_Test_Server;

use strict;

use Event::RPC::Server;
use Event::RPC::Logger;
use lib qw(t);

sub start_server {
    my $class = shift;
    my %opts = @_;

    #-- fork
    my $server_pid = fork();
    die "can't fork" unless defined $server_pid;
    
    #-- client tries to make a log connection to
    #-- verify that the server is up and running
    #-- (20 times with a usleep of 0.25, so the
    #--  overall timeout is 10 seconds)
    if ( $server_pid ) {
        for ( 1..20 ) {
	    eval {
	        Event::RPC::Client->log_connect (
		    server => "localhost",
		    port   => $opts{p}+1,
	        );
	    };
	    #-- return to client code if connect succeeded
	    return if !$@;
	    #-- bail out if the limit is reached
	    if ( $_ == 20 ) {
	        die "Couldn't start server";
	    }
	    #-- wait a quarter second...
	    select(undef, undef, undef, 0.25);
	}
    }

    #-- This code is mainly copied from the server.pl
    #-- example and works with a command line style
    #-- %opts hash
    my %ssl_args;
    if ( $opts{s} ) {
      %ssl_args = (
        ssl => 1,
	ssl_key_file  => 't/ssl/server.key',
	ssl_cert_file => 't/ssl/server.crt',
	ssl_passwd_cb => sub { 'eventrpc' },
      );
      if ( not -f 't/ssl/server.key' ) {
	print "please execute from toplevel directory\n";
      }
    }

    my %auth_args;
    if ( $opts{a} ) {
      my ($user, $pass) = split(":", $opts{a}); 
      $pass = Event::RPC->crypt($user, $pass);
      %auth_args = (
	auth_required    => 1,
	auth_passwd_href => { $user => $pass },
      );
    }

    #-- Create a logger object
    my $logger = Event::RPC::Logger->new (
	    min_level => (defined $opts{l} ? $opts{l} : 4),
	    fh_lref   => [ \*STDOUT ],
    );

    #-- Create a loop object
    my $loop;
    my $loop_module = $opts{L};
    if ( $loop_module ) {
	    eval "use $loop_module";
	    die $@ if $@;
	    $loop = $loop_module->new();
    }
    
    my $port = $opts{p} || 5555;
    
    my $disconnect_cnt = $opts{S};
    
    #-- Create a Server instance and declare the
    #-- exported interface
    my $server;
    $server = Event::RPC::Server->new (
      name               => "test daemon",
      port               => $port,
#      logger             => $logger,
      loop               => $loop,
      start_log_listener => 1,
      %auth_args,
      %ssl_args,
      classes => {
	'Event_RPC_Test' => {
	  new         	 => '_constructor',
	  set_data    	 => 1,
	  get_data    	 => 1,
	  hello       	 => 1,
	  quit	      	 => 1,
	  clone	      	 => '_object',
	  multi		 => '_object',
	  echo		 => 1,
          get_cid        => 1,
          get_object_cnt => 1,
	},
      },
      connection_hook   => sub {
      	  my ($conn, $event) = @_;
	  return if $event eq 'connect';
	  --$disconnect_cnt;
	  $server->stop
	      if $disconnect_cnt <= 0 &&
	         $server->get_clients_connected == 0;
	  1;
      },
    );

    #-- Start the server resp. the Event loop.
    $server->start;
    
    #-- Exit the program
    exit;
}

1;

