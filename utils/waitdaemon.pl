#!/usr/bin/perl
#
#  Copyright (c) 2011-2020 FastMail Pty Ltd. All rights reserved.
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

use warnings;
use strict;

use Getopt::Long;
use IO::Handle;
use Sys::Syslog qw(:standard :macros);

openlog('waitdaemon.pl', '', LOG_LOCAL6);

# if this pipe is not undef, then we need to write "ok\r\n" to it once
# we've successfully finished initialising and about to start work
my $childready_pipe = IO::Handle->new_from_fd(3, "w");
if (defined $childready_pipe) {
    syslog(LOG_DEBUG, "opened childready pipe, fd=%i",
                      fileno($childready_pipe));
}
else {
    syslog(LOG_DEBUG, "no childready pipe found");
}

my $opt_altconfig;
my $opt_id;
my $opt_ready;
my $opt_exitearly;
my $opt_requirepipe = 0;
my $opt_shutdownfile;
my $shutdown = 0;

# make sure normal signal exits don't bypass shutdown file
$SIG{HUP} = $SIG{INT} = $SIG{TERM} = sub { $shutdown++; };

GetOptions(
    'C=s',              \$opt_altconfig,
    'id=i',             \$opt_id,
    'ready=s',          \$opt_ready,
    'exitearly=s',      \$opt_exitearly,
    'requirepipe',      \$opt_requirepipe,
    'shutdownfile=s',   \$opt_shutdownfile,
);

# XXX make sure ready is one of ok, short, bad, none
# XXX make sure exitearly is one of before-ok, after-ok

if (defined $opt_exitearly and $opt_exitearly eq 'before-ok') {
    syslog(LOG_INFO, 'exiting early due to --exitearly=before-ok');
    exit 0;
}

if (defined $childready_pipe) {
    if ($opt_ready eq 'ok') {
        print $childready_pipe "ok\r\n";
        $childready_pipe->close();
    }
    elsif ($opt_ready eq 'short') {
        print $childready_pipe "ok";
        $childready_pipe->close();
    }
    elsif ($opt_ready eq 'bad') {
        print $childready_pipe "bad!";
        $childready_pipe->close();
    }
    # any other value, treat as 'none', and do not print anything
}
elsif ($opt_requirepipe) {
    syslog(LOG_INFO, 'no childready pipe, exiting due to --requirepipe');
    exit 1;  # XXX distinct exit values?
}

if (defined $opt_exitearly && $opt_exitearly eq 'after-ok') {
    syslog(LOG_INFO, 'exiting early due to --exitearly=after-ok');
    exit 0;
}

while (!$shutdown) {
    sleep;
}

if ($opt_shutdownfile) {
    open my $fh, '>', $opt_shutdownfile or die "open $opt_shutdownfile: $!";
    close $fh;
    sleep 2;
}

exit 0;
