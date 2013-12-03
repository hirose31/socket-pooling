#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
BEGIN {
    sub p($) {
        local $Data::Dumper::Indent    = 1;
        local $Data::Dumper::Deepcopy  = 1;
        local $Data::Dumper::Sortkeys  = 1;
        local $Data::Dumper::Terse     = 1;
        local $Data::Dumper::Useqq     = 1;
        local $Data::Dumper::Quotekeys = 0;
        my $d =  Dumper($_[0]);
        $d    =~ s/\\x{([0-9a-z]+)}/chr(hex($1))/ge;
        print STDERR $d;
    }
}

use Log::Minimal;
use Carp;

use AnyEvent;
use AnyEvent::FDpasser;
use IO::Socket::UNIX;

my $s2c_path  = "/tmp/pool.s2c";
my $c2s_path  = "/tmp/pool.c2s";

my $cv = AE::cv;
infof("[$$] Client start");
my $passer = AnyEvent::FDpasser->new( fh => AnyEvent::FDpasser::fdpasser_connect($s2c_path) );

$passer->push_recv_fh(
    sub {
        my $fh = shift;
        # use fh
        infof("[$$] syswrite");
        syswrite $fh, "[$$] Client\n";

        # return fh
        my $passer_c2s = AnyEvent::FDpasser->new( fh => AnyEvent::FDpasser::fdpasser_connect($c2s_path) );

        $passer_c2s->push_send_fh(
            $fh,
            sub {
                infof("[$$] return fh");
                $cv->send;
            });
    });


$cv->recv;

__END__

# for Emacsen
# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# cperl-close-paren-offset: -4
# cperl-indent-parens-as-block: t
# indent-tabs-mode: nil
# coding: utf-8
# End:

# vi: set ts=4 sw=4 sts=0 et ft=perl fenc=utf-8 :
