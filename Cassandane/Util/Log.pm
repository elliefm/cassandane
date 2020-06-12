#!/usr/bin/perl
#
#  Copyright (c) 2011-2017 FastMail Pty Ltd. All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in
#     the documentation and/or other materials provided with the
#     distribution.
#
#  3. The name "Fastmail Pty Ltd" must not be used to
#     endorse or promote products derived from this software without
#     prior written permission. For permission or any legal
#     details, please contact
#      FastMail Pty Ltd
#      PO Box 234
#      Collins St West 8007
#      Victoria
#      Australia
#
#  4. Redistributions of any form whatsoever must retain the following
#     acknowledgment:
#     "This product includes software developed by Fastmail Pty. Ltd."
#
#  FASTMAIL PTY LTD DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
#  INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY  AND FITNESS, IN NO
#  EVENT SHALL OPERA SOFTWARE AUSTRALIA BE LIABLE FOR ANY SPECIAL, INDIRECT
#  OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF
#  USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
#  TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
#  OF THIS SOFTWARE.
#

package Cassandane::Util::Log;
use strict;
use warnings;
use Data::Dumper;
use Scalar::Util qw(blessed);
use Sys::Syslog qw(:standard :macros);

use Exporter ();
our @ISA = qw(Exporter);
our @EXPORT = qw(
    &xlog &set_verbose &get_verbose
    );

my $verbose = 0;

openlog('cassandane', '', LOG_LOCAL6)
    or die "Cannot openlog";

sub _looks_like_log_wrapper
{
    print STDERR "wrapper? " . Dumper [@_];

    my ($sub) = @_;

    # let's also skip over eval frames
    return 1 if $sub eq '(eval)';

    # looks like part of a logging package
    return 1 if $sub =~ m/::Log::/;

    # n.b. sub field from caller() is the full disambiguated name
    my ($baresub) = reverse split /::/, $sub;
    return 1 if $baresub =~ m/(?:^log|log$)/;

    return;
}

sub xlog
{
    my $id;
    # if the first argument is an object with an id() method,
    # include the id it returns in the log message
    if (ref $_[0] && blessed $_[0] && $_[0]->can('id')) {
        my $obj = shift @_;
        $id = $obj->id();
    }

    # XXX WIP this is broken still
    # XXX the commit that added sub names was broken too!
    # let's be smart about which caller's details we log: if it
    # looks like a generic logging wrapper, go up another frame
    my ($package, $file, $line, $sub);
    my $n = 0;
    while (my @c = caller ($n)) {
        print STDERR "caller($n): " . Dumper \@c;

        ($package, undef, $line, $sub) = @c;

        my $looks = _looks_like_log_wrapper($sub);
        print STDERR "looks? [$looks]\n";
        last if not _looks_like_log_wrapper($sub);

        $n++;
    }

    $sub =~ s/^Cassandane:://;
    my $msg = "=====> $sub\[$line] ";
    $msg .= "($id) " if $id;
    $msg .= join(' ', @_);
    print STDERR "$msg\n";
    syslog(LOG_ERR, "$msg");
}

sub set_verbose
{
    my ($v) = @_;
    $verbose = 0 + $v;
}

sub get_verbose
{
    return $verbose;
}

1;
