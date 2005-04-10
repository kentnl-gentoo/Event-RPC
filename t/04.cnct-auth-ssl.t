use strict;

use Test::More;

my $depend_modules = 0;
eval { require Event } && ++$depend_modules;
eval { require Glib }  && ++$depend_modules;

if ( not $depend_modules ) {
	plan skip_all => "Neither Event nor Glib installed";
}

eval { require IO::Socket::SSL };
if ( $@ ) {
	plan skip_all => "IO::Socket::SSL required";
}

plan tests => 7;

my $PORT = 61524;
my $AUTH_USER = "foo";
my $AUTH_PASS = "bar";

# start server in background, without logging
my $server = qx[ $^X t/server.pl -d -s -a $AUTH_USER:$AUTH_PASS -l 0 -p $PORT ];
my ($pid) = $server =~ /SERVER_PID=(\d+)/;
die "server not started: $server" unless $pid;
END { kill 1, $pid }; # prevent server from hanging around if a test fails

# load client class
use_ok('Event::RPC::Client');

# wait on server to come up
sleep 1;

# create client instance
my $client = Event::RPC::Client->new (
  server    => "localhost",
  port      => $PORT,
  auth_user => $AUTH_USER,
  auth_pass => "wrong pass",
  ssl       => 1,
);

# try to connect with wrong password
eval { $client->connect };
ok($@ ne '', "connection failed with wrong pw");

# now set correct password
$client->set_auth_pass(Event::RPC->crypt($AUTH_USER,$AUTH_PASS)),

# connect to server with correct password
$client->connect;
ok(1, "connected");

# create instance of test class over RPC
my $object = Event_RPC_Test->new (
	data => "Some test data. " x 6
);
ok ((ref $object)=~/Event_RPC_Test/, "object created via RPC");

# call quit method, which stops the server after one second
ok ($object->quit =~ /stops/, "quit method called");

# disconnect client
ok ($client->disconnect, "client disconnected");

# wait on server to quit
wait;
ok (1, "server stopped");
sleep 1;
