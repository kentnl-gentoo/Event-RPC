# $Id: Message.pm,v 1.7 2009-04-22 10:53:51 joern Exp $

#-----------------------------------------------------------------------
# Copyright (C) 2002-2006 Jörn Reder <joern AT zyn.de>.
# All Rights Reserved. See file COPYRIGHT for details.
# 
# This module is part of Event::RPC, which is free software; you can
# redistribute it and/or modify it under the same terms as Perl itself.
#-----------------------------------------------------------------------

package Event::RPC::Message;

use Carp;
use strict;
use Storable;

my $DEBUG = 0;

sub get_sock                    { shift->{sock}                         }

sub get_buffer                  { shift->{buffer}                       }
sub get_length                  { shift->{length}                       }
sub get_written                 { shift->{written}                      }

sub set_buffer                  { shift->{buffer}               = $_[1] }
sub set_length                  { shift->{length}               = $_[1] }
sub set_written                 { shift->{written}              = $_[1] }

sub new {
    my $class = shift;
    my ($sock) = @_;

    my $self = bless {
        sock    => $sock,
        buffer  => undef,
        length  => 0,
        written => 0,
    }, $class;

    return $self;
}

sub read {
    my $self = shift;
    my ($blocking) = @_;

    $self->get_sock->blocking($blocking?1:0);
    
    if ( not defined $self->{buffer} ) {
        my $length_packed;
        $DEBUG && print "DEBUG: going to read header...\n";
        my $rc = sysread ($self->get_sock, $length_packed, 4);
        $DEBUG && print "DEBUG: header read rc=$rc\n";
        die "DISCONNECTED" if !(defined $rc) || $rc == 0;
        $self->{length} = unpack("N", $length_packed);
        $DEBUG && print "DEBUG: packet size=$self->{length}\n";
        die "Incoming message too big"
                if $self->{length} > 4194304;
    }

    my $buffer_length = length($self->{buffer}||'');

    $DEBUG && print "DEBUG: going to read packet... (buffer_length=$buffer_length)\n";

    my $rc = sysread (
        $self->get_sock,
        $self->{buffer},
        $self->{length} - $buffer_length,
        $buffer_length
    );

    $DEBUG && print "DEBUG: packet read rc=$rc\n";

    return if not defined $rc;
    die "DISCONNECTED" if $rc == 0;

    $buffer_length = length($self->{buffer});

    $DEBUG && print "DEBUG: more to read... ($self->{length} != $buffer_length)\n"
        if $self->{length} != $buffer_length;

    return if $self->{length} != $buffer_length;

    $DEBUG && print "DEBUG: read finished, length=$buffer_length\n";

    my $data = Storable::thaw($self->{buffer});

    $self->{buffer} = undef;
    $self->{length} = 0;

    return $data;
}

sub read_blocked {
    my $self = shift;

    my $rc;
    $rc = $self->read(1) while not defined $rc;

    return $rc;
}

sub set_data {
    my $self = shift;
    my ($data) = @_;

    $DEBUG && print "DEBUG: Message->set_data($data)\n";

    my $packed = Storable::nfreeze ($data);
    $self->{buffer} = pack("N", length($packed)).$packed;
    $self->{length} = length($self->{buffer});
    $self->{written} = 0;

    1;
}

sub write {
    my $self = shift;
    my ($blocking) = @_;

    $self->get_sock->blocking($blocking?1:0);

    my $rc = syswrite (
        $self->get_sock,
        $self->{buffer},
        $self->{length}-$self->{written},
        $self->{written},
    );

    $DEBUG && print "DEBUG: written rc=$rc\n";

    return if not defined $rc;

    $self->{written} += $rc;

    if ( $self->{written} == $self->{length} ) {
        $DEBUG && print "DEBUG: write finished\n";
        $self->{buffer} = undef;
        $self->{length} = 0;
        return 1;
    }

    $DEBUG && print "DEBUG: more to be written...\n";

    return;
}

sub write_blocked {
    my $self = shift;
    my ($data) = @_;

    $self->set_data($data);

    my $finished = 0;
    $finished = $self->write(1) while not $finished;

    1;
}

1;

__END__

=head1 NAME

Event::RPC::Message - Implementation of Event::RPC network protocol

=head1 SYNOPSIS

  # Internal module. No documented public interface.

=head1 DESCRIPTION

This module implements the network protocol of Event::RPC.
Objects of this class are created internally by Event::RPC::Server
and Event::RPC::Client and performs message passing over the
network.

=head1 AUTHORS

  Jörn Reder <joern at zyn dot de>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2002-2006 by Joern Reder, All Rights Reserved.

This library is free software; you can redistribute it
and/or modify it under the same terms as Perl itself.

=cut
