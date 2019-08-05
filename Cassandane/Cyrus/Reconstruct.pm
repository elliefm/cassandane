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

package Cassandane::Cyrus::Reconstruct;
use strict;
use warnings;
use Data::Dumper;
use IO::File;
use IO::File::fcntl;

use lib '.';
use base qw(Cassandane::Cyrus::TestCase);
use Cassandane::Util::Log;
use Cassandane::Instance;
use Cyrus::IndexFile;

sub new
{
    my $class = shift;
    return $class->SUPER::new({ adminstore => 1 }, @_);
}

sub set_up
{
    my ($self) = @_;
    $self->SUPER::set_up();
}

sub tear_down
{
    my ($self) = @_;
    $self->SUPER::tear_down();
}

#
# Test zeroed out data across the UID
#
sub test_reconstruct_zerouid
{
    my ($self) = @_;

    my $imaptalk = $self->{store}->get_client();

    for (1..10) {
        my $msg = $self->{gen}->generate(subject => "subject $_");
        $self->{store}->write_message($msg, flags => ["\\Seen", "\$NotJunk"]);
    }
    $self->{store}->write_end();
    $imaptalk->select("INBOX") || die;

    my @records = $imaptalk->search("all");
    $self->assert_num_equals(10, scalar @records);
    $self->assert(grep { $_ == 6 } @records);

    $self->{instance}->run_command({ cyrus => 1 }, 'reconstruct');

    @records = $imaptalk->search("all");
    $self->assert_num_equals(10, scalar @records);
    $self->assert(grep { $_ == 6 } @records);

    # this needs a bit of magic to know where to write... so
    # we do some hard-coded cyrus.index handling
    my $basedir = $self->{instance}->{basedir};
    my $file = "$basedir/data/user/cassandane/cyrus.index";
    my $fh = IO::File->new($file, "+<");
    die "NO SUCH FILE $file" unless $fh;
    my $index = Cyrus::IndexFile->new($fh);

    my $offset = $index->header('StartOffset') + (5 * $index->header('RecordSize'));
    warn "seeking to offset $offset";
    $fh->seek($offset, 0);
    $fh->syswrite("\0\0\0\0\0\0\0\0", 8);
    $fh->close();

    # this time, the reconstruct will fix up the broken record and re-insert later
    $self->{instance}->run_command({ cyrus => 1 }, 'reconstruct', 'user.cassandane');

    @records = $imaptalk->search("all");
    $self->assert_num_equals(10, scalar @records);
    $self->assert(not grep { $_ == 6 } @records);
    $self->assert(grep { $_ == 11 } @records);
}

#
# Test truncated file
#
sub test_reconstruct_truncated
{
    my ($self) = @_;

    my $imaptalk = $self->{store}->get_client();

    for (1..10) {
        my $msg = $self->{gen}->generate(subject => "subject $_");
        $self->{store}->write_message($msg, flags => ["\\Seen", "\$NotJunk"]);
    }
    $self->{store}->write_end();
    $imaptalk->select("INBOX") || die;

    my @records = $imaptalk->search("all");
    $self->assert_num_equals(10, scalar @records);
    $self->assert(grep { $_ == 6 } @records);

    $self->{instance}->run_command({ cyrus => 1 }, 'reconstruct');

    @records = $imaptalk->search("all");
    $self->assert_num_equals(10, scalar @records);
    $self->assert(grep { $_ == 6 } @records);

    # this needs a bit of magic to know where to write... so
    # we do some hard-coded cyrus.index handling
    my $basedir = $self->{instance}->{basedir};
    my $file = "$basedir/data/user/cassandane/cyrus.index";
    my $fh = IO::File->new($file, "+<");
    die "NO SUCH FILE $file" unless $fh;
    my $index = Cyrus::IndexFile->new($fh);

    my $offset = $index->header('StartOffset') + (5 * $index->header('RecordSize'));
    $fh->truncate($offset);
    $fh->close();

    # this time, the reconstruct will create the records again
    $self->{instance}->run_command({ cyrus => 1 }, 'reconstruct', 'user.cassandane');

    # XXX - this actually deletes everything, so we unselect and reselect.  A
    # too-short cyrus.index is a fatal error, so we don't even try to read it.
    $imaptalk->unselect();
    $imaptalk->select("INBOX") || die;

    @records = $imaptalk->search("all");
    $self->assert_num_equals(10, scalar @records);
    $self->assert(grep { $_ == 6 } @records);
    $self->assert(not grep { $_ == 11 } @records);
}

#
# Test removed file
#
sub test_reconstruct_removedfile
{
    my ($self) = @_;

    my $imaptalk = $self->{store}->get_client();

    for (1..10) {
        my $msg = $self->{gen}->generate(subject => "subject $_");
        $self->{store}->write_message($msg, flags => ["\\Seen", "\$NotJunk"]);
    }
    $self->{store}->write_end();
    $imaptalk->select("INBOX") || die;

    my @records = $imaptalk->search("all");
    $self->assert_num_equals(10, scalar @records);
    $self->assert(grep { $_ == 6 } @records);

    $self->{instance}->run_command({ cyrus => 1 }, 'reconstruct');

    @records = $imaptalk->search("all");
    $self->assert_num_equals(10, scalar @records);
    $self->assert(grep { $_ == 6 } @records);

    # this needs a bit of magic to know where to write... so
    # we do some hard-coded cyrus.index handling
    my $basedir = $self->{instance}->{basedir};
    unlink("$basedir/data/user/cassandane/6.");

    # this time, the reconstruct will fix up the broken record and re-insert later
    $self->{instance}->run_command({ cyrus => 1 }, 'reconstruct', 'user.cassandane');

    @records = $imaptalk->search("all");
    $self->assert_num_equals(9, scalar @records);
    $self->assert(not grep { $_ == 6 } @records);
}

#
# Test zero modseqs
# Regression test for https://github.com/cyrusimap/cyrus-imapd/issues/2839
#
sub test_reconstruct_zeromodseq
{
    my ($self) = @_;

    my $imaptalk = $self->{store}->get_client();
    # we need to be in uid mode to ensure these messages keep their
    # original UIDs after we fiddle with them...
    $imaptalk->uid(1);

    for (1..10) {
        my $msg = $self->{gen}->generate(subject => "subject $_");
        $self->{store}->write_message($msg, flags => ["\\Seen", "\$NotJunk"]);
    }
    $self->{store}->write_end();
    $imaptalk->select("INBOX") || die;

    my @records = $imaptalk->search("all");
    $self->assert_num_equals(10, scalar @records);
    $self->assert_deep_equals([1 .. 10], \@records);

    $self->{instance}->run_command({ cyrus => 1 }, 'reconstruct');

    @records = $imaptalk->search("all");
    $self->assert_num_equals(10, scalar @records);
    $self->assert_deep_equals([1 .. 10], \@records);

    # drop the client connection, we need clean state
    undef $imaptalk;
    $self->{store}->disconnect();

    # we're about to zero out the modseq on some records, which is
    # similar to what may exist naturally if a store is upgraded from a
    # pre-modseq cyrus version
    my $basedir = $self->{instance}->{basedir};
    my $indexfname = "$basedir/data/user/cassandane/cyrus.index";
    my $fh = IO::File::fcntl->new($indexfname, "+<", 'lock_ex', 5);
    die "no fh" if not $fh;
    my $index = Cyrus::IndexFile->new($fh);
    die "didn't open index file" if not $index;

    while (my $record = $index->next_record_hash()) {
        # fiddle with even-numbered records
        if ($record->{Uid} % 2 == 0) {
            $record->{Modseq} = 0;
            $index->rewrite_record($record);
        }
    }
    undef $index;
    $fh->lock_un();
    xlog "zeroed out modseq for even-numbered records";

    # the messages with modseq=0 should still be visible to a new imap
    # connection
    $imaptalk = $self->{store}->get_client();
    $imaptalk->uid(1);
    $imaptalk->select("INBOX") || die;
    @records = $imaptalk->search("all");
    $self->assert_num_equals(10, scalar @records);
    $self->assert_deep_equals([1 .. 10], \@records);
    undef $imaptalk;
    $self->{store}->disconnect();

    # reconstruct should not need to do anything special, because it
    # still finds the messages in the index.
    # IN PARTICULAR, it should not "rediscover" these messages on
    # disk and re-add them with new uids.
    # Before patching, the rediscover behaviour was triggered by a
    # cyrus.index version upgrade, so definitely exercise that by
    # downgrading and then upgrading back to current
    $self->{instance}->run_command({ cyrus => 1 }, 'reconstruct', '-V12', 'user.cassandane');
    $self->{instance}->run_command({ cyrus => 1 }, 'reconstruct', '-Vmax', 'user.cassandane');

    # checking with IMAP again, we should still see the original 10
    # messages with their original 10 uids
    $imaptalk = $self->{store}->get_client();
    $imaptalk->uid(1);
    $imaptalk->select("INBOX") || die;
    @records = $imaptalk->search("all");
    $self->assert_num_equals(10, scalar @records);
    $self->assert_deep_equals([1 .. 10], \@records);
}

1;
