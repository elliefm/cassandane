#!/usr/bin/perl
#
#  Copyright (c) 2011 Opera Software Australia Pty. Ltd.  All rights
#  reserved.
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
#  3. The name "Opera Software Australia" must not be used to
#     endorse or promote products derived from this software without
#     prior written permission. For permission or any legal
#     details, please contact
# 	Opera Software Australia Pty. Ltd.
# 	Level 50, 120 Collins St
# 	Melbourne 3000
# 	Victoria
# 	Australia
#
#  4. Redistributions of any form whatsoever must retain the following
#     acknowledgment:
#     "This product includes software developed by Opera Software
#     Australia Pty. Ltd."
#
#  OPERA SOFTWARE AUSTRALIA DISCLAIMS ALL WARRANTIES WITH REGARD TO
#  THIS SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
#  AND FITNESS, IN NO EVENT SHALL OPERA SOFTWARE AUSTRALIA BE LIABLE
#  FOR ANY SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
#  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
#  AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING
#  OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#

use strict;
use warnings;
package Cassandane::Cyrus::Rename;
use base qw(Cassandane::Cyrus::TestCase);
use Cassandane::Util::Log;
use Cassandane::Instance;

Cassandane::Cyrus::TestCase::magic(Partition2 => sub {
    shift->config_set('partition-p2' => '@basedir@/data-p2');
});
Cassandane::Cyrus::TestCase::magic(AllowMoves => sub {
    shift->config_set('allowusermoves' => 'yes');
});
Cassandane::Cyrus::TestCase::magic(MetaPartition => sub {
    shift->config_set(
	'metapartition-default' => '@basedir@/meta',
	'metapartition_files' => 'header index'
    );
});


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
# Test LSUB behaviour
#
sub test_rename_asuser
{
    my ($self) = @_;

    my $imaptalk = $self->{store}->get_client();

    $imaptalk->create("INBOX.user-src") || die;
    $self->{store}->set_folder("INBOX.user-src");
    $self->{store}->write_begin();
    my $msg1 = $self->{gen}->generate(subject => "subject 1");
    $self->{store}->write_message($msg1, flags => ["\\Seen", "\$NotJunk"]);
    $self->{store}->write_end();
    $imaptalk->select("INBOX.user-src") || die;
    my @predata = $imaptalk->search("SEEN");
    $self->assert_num_equals(1, scalar @predata);

    $imaptalk->rename("INBOX.user-src", "INBOX.user-dst") || die;
    $imaptalk->select("INBOX.user-dst") || die;
    my @postdata = $imaptalk->search("KEYWORD" => "\$NotJunk");
    $self->assert_num_equals(1, scalar @postdata);
}

#
# Test Bug #3586 - rename subfolders
#
sub test_rename_subfolder
{
    my ($self) = @_;

    my $imaptalk = $self->{store}->get_client();

    $imaptalk->create("INBOX.user-src.subdir") || die;
    $self->{store}->set_folder("INBOX.user-src.subdir");
    $self->{store}->write_begin();
    my $msg1 = $self->{gen}->generate(subject => "subject 1");
    $self->{store}->write_message($msg1, flags => ["\\Seen", "\$NotJunk"]);
    $self->{store}->write_end();
    $imaptalk->select("INBOX.user-src.subdir") || die;
    my @predata = $imaptalk->search("SEEN");
    $self->assert_num_equals(1, scalar @predata);

    $imaptalk->rename("INBOX.user-src", "INBOX.user-dst") || die;
    $imaptalk->select("INBOX.user-dst.subdir") || die;
    my @postdata = $imaptalk->search("KEYWORD" => "\$NotJunk");
    $self->assert_num_equals(1, scalar @postdata);
}

#
# Test Bug #3634 - rename inbox -> inbox.sub
#
sub test_rename_inbox
{
    my ($self) = @_;

    my $imaptalk = $self->{store}->get_client();

    $self->{store}->set_folder("INBOX");
    $self->{store}->write_begin();
    my $msg1 = $self->{gen}->generate(subject => "subject 1");
    $self->{store}->write_message($msg1, flags => ["\\Seen", "\$NotJunk"]);
    $self->{store}->write_end();

    $imaptalk->select("INBOX") || die;
    my @predata = $imaptalk->search("SEEN");
    $self->assert_num_equals(1, scalar @predata);

    $imaptalk->rename("INBOX", "INBOX.dst") || die;

    $imaptalk->select("INBOX") || die;
    my @postinboxdata = $imaptalk->search("KEYWORD" => "\$NotJunk");
    $self->assert_num_equals(0, scalar @postinboxdata);

    $imaptalk->select("INBOX.dst") || die;
    my @postdata = $imaptalk->search("KEYWORD" => "\$NotJunk");
    $self->assert_num_equals(1, scalar @postdata);
}

sub test_rename_user
    :Partition2
{
    my ($self) = @_;
    my $admintalk = $self->{adminstore}->get_client();

    xlog "Test Cyrus extension which renames a user to a different partition";

    $admintalk->rename('user.cassandane', 'user.cassandane'); # should have an error;
    $self->assert($admintalk->get_last_error());

    $admintalk->rename('user.cassandane', 'user.cassandane', 'p2') || die; # partition move
}

sub test_rename_deepuser
    :AllowMoves
{
    my ($self) = @_;
    my $admintalk = $self->{adminstore}->get_client();

    xlog "Test user rename";

    $admintalk->create("user.cassandane.foo") || die;
    $admintalk->create("user.cassandane.bar") || die;
    $admintalk->create("user.cassandane.bar.sub") || die;

    my $res = $admintalk->rename('user.cassandane', 'user.newuser');
    $self->assert(not $admintalk->get_last_error());

    my $res = $admintalk->select("user.newuser.bar.sub");
    $self->assert(not $admintalk->get_last_error());
}

sub test_rename_paths
    :MetaPartition
{
    my ($self) = @_;
    my $basedir = $self->{instance}->{basedir};
    my $imaptalk = $self->{store}->get_client();

    $imaptalk->create("INBOX.rename-src.sub") || die;

    $self->{store}->set_folder("INBOX.rename-src.sub");
    $self->{store}->write_begin();
    my $msg1 = $self->{gen}->generate(subject => "subject 1");
    $self->{store}->write_message($msg1, flags => ["\\Seen", "\$NotJunk"]);
    $self->{store}->write_end();

    # check source files exist
    -d "$basedir/data/user/cassandane/rename-src/sub" || die;
    -d "$basedir/meta/user/cassandane/rename-src/sub" || die;
    -f "$basedir/meta/user/cassandane/rename-src/sub/cyrus.header" || die;
    -f "$basedir/meta/user/cassandane/rename-src/sub/cyrus.index" || die;
    -f "$basedir/data/user/cassandane/rename-src/sub/cyrus.cache" || die;
    -f "$basedir/data/user/cassandane/rename-src/sub/1." || die;

    # and target don't
    -d "$basedir/data/user/cassandane/rename-dst" && die;
    -d "$basedir/meta/user/cassandane/rename-dst" && die;

    $imaptalk->rename("INBOX.rename-src.sub", "INBOX.rename-dst.sub");

    # check dest files exist
    -d "$basedir/data/user/cassandane/rename-dst/sub" || die;
    -d "$basedir/meta/user/cassandane/rename-dst/sub" || die;
    -f "$basedir/meta/user/cassandane/rename-dst/sub/cyrus.header" || die;
    -f "$basedir/meta/user/cassandane/rename-dst/sub/cyrus.index" || die;
    -f "$basedir/data/user/cassandane/rename-dst/sub/cyrus.cache" || die;
    -f "$basedir/data/user/cassandane/rename-dst/sub/1." || die;

    # and src don't
    -d "$basedir/data/user/cassandane/rename-src" && die;
    -d "$basedir/meta/user/cassandane/rename-src" && die;
}

1;
