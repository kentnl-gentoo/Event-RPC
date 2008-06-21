package Event_RPC_Test2;

use strict;

sub get_data			{ shift->{data}				}
sub set_data			{ shift->{data}			= $_[1]	}

sub new {
    my $class = shift;
    my ($data) = @_;
    
    return bless {
        data    => $data,
    }, $class;
}

1;

