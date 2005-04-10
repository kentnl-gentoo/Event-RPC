use strict;
use Test::More;

my $depend_modules = 0;
eval { require Event } && ++$depend_modules;
eval { require Glib }  && ++$depend_modules;

if ( not $depend_modules ) {
	plan skip_all => "Neither Event nor Glib installed";
}

plan tests => 14;

my $PORT = 61524;

# start server in background, without logging
my $server = qx[ $^X t/server.pl -d -l 0 -p $PORT ];
my ($pid) = $server =~ /SERVER_PID=(\d+)/;
die "server not started: $server" unless $pid;
END { kill 1, $pid }; # prevent server from hanging around if a test fails

# load client class
use_ok('Event::RPC::Client');

# create client instance
my $client = Event::RPC::Client->new (
  server   => "localhost",
  port     => $PORT,
);

# wait on server to come up
sleep 1;

# connect to server
$client->connect;
ok(1, "connected");

# create instance of test class over RPC
my $data = "Some test data. " x 6;
my $object = Event_RPC_Test->new (
	data => $data
);
ok ((ref $object)=~/Event_RPC_Test/, "object created via RPC");

# test data
ok ($object->get_data eq $data, "data member ok");

# set data
ok ($object->set_data("foo") eq "foo", "set data");

# check set data
ok ($object->get_data eq "foo", "get data");

# object transfer
my $clone;
ok ( $clone = $object->clone, "object transfer");

# check clone
$clone->set_data("bar");
ok ( $clone->get_data eq 'bar' &&
     $object->get_data eq 'foo', "clone");


# transfer a list of objects
my ($lref, $href) = $object->multi(10);
ok ( @$lref == 10 && $lref->[5]->get_data == 5, "multi object list");
ok ( keys(%$href) == 10 && $href->{4}->get_data == 4, "multi object hash");

# complex parameter transfer
my @params = (
  "scalar", { 1 => "hash" }, [ "a", "list" ],
);

my @result = $object->echo(@params);

ok ( @result == 3                &&
     $result[0]      eq 'scalar' &&
     ref $result[1]  eq 'HASH'   &&
     $result[1]->{1} eq 'hash'   &&
     ref $result[2]  eq 'ARRAY'  &&
     $result[2]->[1] eq 'list'
     ,
     "complex parameter transfer"
);

# call quit method, which stops the server after one second
ok ($object->quit =~ /stops/, "quit method called");

# disconnect client
ok ($client->disconnect, "client disconnected");

# wait on server to quit
wait;
ok (1, "server stopped");
sleep 1;
