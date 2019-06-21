#!/usr/bin/perl
#
#  Copyright (c) 2011-2019 FastMail Pty Ltd. All rights reserved.
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
package saslauthd;

use strict;
use warnings;

use Data::Dumper;
use IO::Socket::UNIX;

use lib '.';
use Cassandane::Util::Log;

set_verbose($ENV{CASSANDANE_VERBOSE}) if $ENV{CASSANDANE_VERBOSE};

sub saslauthd
{
    my ($sockpath) = @_;

    xlog "opening socket $sockpath ...";
    unlink("$sockpath");
    my $sock = IO::Socket::UNIX->new(
        Local => "$sockpath",
        Type => SOCK_STREAM,
        Listen => SOMAXCONN,
    );
    die "FAILED to create socket $sockpath: $!" unless $sock;
    chmod(0777, $sockpath) or die "chmod $sockpath: $!";

    xlog "listening on $sockpath";

    eval {
        while (my $client = $sock->accept()) {
            my $LoginName = get_counted_string($client);
            my $Password = get_counted_string($client);
            my $Service = lc get_counted_string($client);
            my $Realm = get_counted_string($client);
            if (get_verbose()) {
                xlog "authdaemon connection: $LoginName $Password" .
                     " $Service $Realm";
            }

            # custom logic!
            if ($Password eq 'bad') {
                $client->print(pack("nA3", 2, "NO\000"));
            }
            else {
                $client->print(pack("nA3", 2, "OK\000"));
            }
            $client->close();
        }
    };
}

sub get_counted_string
{
    my $sock = shift;
    my $data;
    $sock->read($data, 2);
    my $size = unpack('n', $data);
    $sock->read($data, $size);
    return unpack("A$size", $data);
}

my ($sockpath) = @ARGV;
die "Usage: $0 sockpath\n" if not $sockpath;

saslauthd($sockpath);
