#!/usr/bin/perl -w

use strict;

use strict;
use lib qw(t);
use Event::RPC::Server;
use Event::RPC::Logger;
use Getopt::Std;

my $USAGE = <<__EOU;

Usage: server.pl [-l log-level] [-s] [-a user:pass] [-L loop-module] [-S cnt]

Description:
  Event::RPC server demonstration program. Execute this from
  the distribution's base or examples/ directory. Then execute
  examples/client.pl on another console.

Options:
  -p                 RPC port number. Default: 5555
  -l log-level       Logging level. Default: 4
  -s                 Use SSL encryption
  -a user:pass       Require authorization
  -L loop-module     Event loop module to use.
                     Default: Event::RPC::Loop::Event
  -S cnt             Shutdown server after this number of
                     client disconnects

__EOU

sub HELP_MESSAGE {
	my ($fh) = @_;
	$fh ||= \*STDOUT;
	print $fh $USAGE;
	exit;
}

main: {
    my %opts;
    my $opts_ok = getopts('dS:L:l:a:sp:',\%opts);
   
    HELP_MESSAGE() unless $opts_ok;

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
    
    #-- Create a Server instance and declare the
    #-- exported interface
    my $disconnect_cnt = $opts{S};
    my $server;
    $server = Event::RPC::Server->new (
      name               => "test daemon",
      port               => $port,
      logger             => $logger,
      loop               => $loop,
      start_log_listener => 1,
      %auth_args,
      %ssl_args,
      classes => {
	'Event_RPC_Test' => {
	  new         	=> '_constructor',
	  set_data    	=> 1,
	  get_data    	=> 1,
	  hello       	=> 1,
	  quit	      	=> 1,
	  clone	      	=> '_object',
	  multi		=> '_object',
	  echo		=> 1,
	},
      },
      connection_hook   => $disconnect_cnt == 0 ? undef : sub {
      	  my ($conn, $event) = @_;
	  return if $event eq 'connect';
	  --$disconnect_cnt;
	  $server->stop
	      if $disconnect_cnt <= 0 &&
	         $server->get_clients_connected == 0;
	  1;
      },
    );

    daemonize() if $opts{d};

    #-- Start the server resp. the Event loop.
    $server->start;
}

sub daemonize {
    require POSIX;
    defined(my $pid = fork)   or die "Can't fork: $!";
    if ( $pid ) {
	print "SERVER_PID=$pid\n";
	exit if $pid;
    }
    umask 0;
    open STDIN, '/dev/null'   or die "Can't read /dev/null: $!";
    open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
    open STDERR, '>/dev/null' or die "Can't write to /dev/null: $!";
    POSIX::setsid()           or die "Can't start a new session: $!";
    1;
}

1;

