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

package Cassandane::Cyrus::JMAPSieve;
use strict;
use warnings;
use DateTime;
use JSON;
use JSON::XS;
use Mail::JMAPTalk 0.13;
use Data::Dumper;
use Storable 'dclone';
use File::Basename;
use IO::File;

use lib '.';
use base qw(Cassandane::Cyrus::TestCase);
use Cassandane::Util::Log;

use charnames ':full';

sub new
{
    my ($class, @args) = @_;

    my $config = Cassandane::Config->default()->clone();

    my ($maj, $min) = Cassandane::Instance->get_version();
    if ($maj == 3 && $min == 0) {
        # need to explicitly add 'body' to sieve_extensions for 3.0
        $config->set(sieve_extensions =>
            "fileinto reject vacation vacation-seconds imap4flags notify " .
            "envelope relational regex subaddress copy date index " .
            "imap4flags mailbox mboxmetadata servermetadata variables " .
            "body");
    }
    elsif ($maj < 3) {
        # also for 2.5 (the earliest Cyrus that Cassandane can test)
        $config->set(sieve_extensions =>
            "fileinto reject vacation vacation-seconds imap4flags notify " .
            "envelope relational regex subaddress copy date index " .
            "imap4flags body");
    }

    $config->set(caldav_realm => 'Cassandane',
                 conversations => 'yes',
                 httpmodules => 'carddav caldav jmap',
                 httpallowcompress => 'no',
                 jmap_nonstandard_extensions => 'yes');

    return $class->SUPER::new({
        config => $config,
        jmap => 1,
        adminstore => 1,
        services => [ 'imap', 'sieve', 'http' ]
    }, @args);
}

sub set_up
{
    my ($self) = @_;
    $self->SUPER::set_up();
    $self->{jmap}->DefaultUsing([
        'urn:ietf:params:jmap:core',
        'urn:ietf:params:jmap:mail',
        'https://cyrusimap.org/ns/jmap/sieve',
        'https://cyrusimap.org/ns/jmap/blob',
    ]);
}

sub tear_down
{
    my ($self) = @_;
    $self->SUPER::tear_down();
}

sub test_sieve_get
    :min_version_3_3 :needs_component_sieve :needs_component_jmap :JMAPExtensions
{
    my ($self) = @_;

    my $jmap = $self->{jmap};

    my $target = "INBOX.target";

    xlog $self, "Install a sieve script filing all mail into a folder";
    my $script = <<EOF;
require ["fileinto"];\r
fileinto "$target";\r
EOF
    $self->{instance}->install_sieve_script($script);

    xlog "get all scripts";
    my $res = $jmap->CallMethods([
        ['SieveScript/get', {
            properties => ['name', 'isActive'],
         }, "R1"]]);
    $self->assert_not_null($res);
    $self->assert_str_equals('SieveScript/get', $res->[0][0]);
    $self->assert_str_equals('R1', $res->[0][2]);
    $self->assert_num_equals(1, scalar @{$res->[0][1]{list}});
    $self->assert_str_equals('test1', $res->[0][1]{list}[0]{name});
    $self->assert_equals(JSON::true, $res->[0][1]{list}[0]{isActive});

    my $id = $res->[0][1]{list}[0]{id};

    xlog "get script by id";
    $res = $jmap->CallMethods([
        ['SieveScript/get', {
            ids => [$id],
         }, "R2"]]);
    $self->assert_not_null($res);
    $self->assert_str_equals('SieveScript/get', $res->[0][0]);
    $self->assert_str_equals('R2', $res->[0][2]);
    $self->assert_num_equals(1, scalar @{$res->[0][1]{list}});
    $self->assert_str_equals('test1', $res->[0][1]{list}[0]{name});
    $self->assert_equals(JSON::true, $res->[0][1]{list}[0]{isActive});
    $self->assert_str_equals($script, $res->[0][1]{list}[0]{content});
}

sub test_sieve_set
    :min_version_3_3 :needs_component_sieve :needs_component_jmap :JMAPExtensions
{
    my ($self) = @_;

    my $script1 = <<EOF;
keep;
EOF
    $script1 =~ s/\r?\n/\r\n/gs;

    my $script2 = <<EOF;
# comment
discard;
EOF
    $script2 =~ s/\r?\n/\r\n/gs;

    my $script3 = <<EOF;
require "imap4flags";
keep :flags "\\flagged";
EOF
    $script3 =~ s/\r?\n/\r\n/gs;

    my $jmap = $self->{jmap};

    xlog "create script";
    my $res = $jmap->CallMethods([
        ['SieveScript/set', {
            create => {
                "1" => {
                    name => "foo",
                    content => "$script1"
                },
                "2" => {
                    name => "xxx",
                    content => "$script2"
                }
            }
         }, "R1"],
        ['SieveScript/get', {
            'ids' => [ '#1', '#2' ]
         }, "R2"]
    ]);
    $self->assert_not_null($res);
    $self->assert_equals(JSON::false, $res->[0][1]{created}{1}{isActive});
    $self->assert_equals(JSON::false, $res->[0][1]{created}{2}{isActive});

    $self->assert_num_equals(2, scalar @{$res->[1][1]{list}});
    $self->assert_str_equals('foo', $res->[1][1]{list}[0]{name});
    $self->assert_equals(JSON::false, $res->[1][1]{list}[0]{isActive});
    $self->assert_str_equals('xxx', $res->[1][1]{list}[1]{name});
    $self->assert_equals(JSON::false, $res->[1][1]{list}[1]{isActive});

    my $id1 = $res->[0][1]{created}{"1"}{id};
    my $id2 = $res->[0][1]{created}{"2"}{id};

    xlog "attempt to create script with same name";
    $res = $jmap->CallMethods([
        ['SieveScript/set', {
            create => {
                "1" => {
                    name => "foo",
                    content => "$script1"
                }
            },
            replaceOnCreate => JSON::false
         }, "R1"],
        ['SieveScript/get', {
         }, "R2"]
    ]);
    $self->assert_not_null($res);
    $self->assert_null($res->[0][1]{created});
    $self->assert_str_equals('scriptNameExists', $res->[0][1]{notCreated}{1}{type});
    $self->assert_num_equals(2, scalar @{$res->[1][1]{list}});

    xlog "overwrite existing script and activate it";
    $res = $jmap->CallMethods([
        ['SieveScript/set', {
            create => {
                "1" => {
                    name => "foo",
                    content => "$script3"
                }
            },
            replaceOnCreate => JSON::true,
            onSuccessActivateScript => "#1"
         }, "R1"],
        ['SieveScript/get', {
         }, "R2"]
    ]);
    $self->assert_not_null($res);
    $self->assert_equals(JSON::true, $res->[0][1]{created}{1}{isActive});
    $self->assert_null($res->[0][1]{updated});
    $self->assert_equals($id1, $res->[0][1]{destroyed}[0]);

    $self->assert_num_equals(2, scalar @{$res->[1][1]{list}});
    $self->assert_str_equals('foo', $res->[1][1]{list}[0]{name});
    $self->assert_equals(JSON::true, $res->[1][1]{list}[0]{isActive});
    $self->assert_str_equals($script3, $res->[1][1]{list}[0]{content});

    $id1 = $res->[0][1]{created}{"1"}{id};

    xlog "rename and deactivate script";
    $res = $jmap->CallMethods([
        ['SieveScript/set', {
            update => {
                $id1 => {
                    name => "bar"
                }
            },
            onSuccessActivateScript => JSON::null
         }, "R3"]
    ]);
    $self->assert_not_null($res->[0][1]{updated});
    $self->assert_null($res->[0][1]{notUpdated});
    $self->assert_equals(JSON::false, $res->[0][1]{updated}{$id1}{isActive});

    xlog "rewrite one script and activate another";
    $res = $jmap->CallMethods([
        ['SieveScript/set', {
            update => {
                $id1 => {
                    content => "$script1",
                }
            },
            onSuccessActivateScript => $id2
         }, "R4"],
        ['SieveScript/get', {
         }, "R5"]
    ]);
    $self->assert_not_null($res->[0][1]{updated});
    $self->assert_equals(JSON::true, $res->[0][1]{updated}{$id2}{isActive});
    $self->assert_null($res->[0][1]{notUpdated});

    $self->assert_num_equals(2, scalar @{$res->[1][1]{list}});
    $self->assert_str_equals('bar', $res->[1][1]{list}[0]{name});
    $self->assert_equals(JSON::false, $res->[1][1]{list}[0]{isActive});
    $self->assert_str_equals($script1, $res->[1][1]{list}[0]{content});
    $self->assert_equals(JSON::true, $res->[1][1]{list}[1]{isActive});

    xlog "change active script";
    $res = $jmap->CallMethods([
        ['SieveScript/set', {
            onSuccessActivateScript => $id1
         }, "R4"],
        ['SieveScript/get', {
         }, "R5"]
    ]);
    $self->assert_not_null($res->[0][1]{updated});
    $self->assert_null($res->[0][1]{notUpdated});
    $self->assert_num_equals(2, scalar @{$res->[1][1]{list}});
    $self->assert_str_equals($id1, $res->[1][1]{list}[0]{id});
    $self->assert_equals(JSON::true, $res->[1][1]{list}[0]{isActive});
    $self->assert_str_equals($id2, $res->[1][1]{list}[1]{id});
    $self->assert_equals(JSON::false, $res->[1][1]{list}[1]{isActive});

    xlog "attempt to delete active script";
    $res = $jmap->CallMethods([
        ['SieveScript/set', {
            destroy => [ $id1 ],
         }, "R6"],
        ['SieveScript/get', {
         }, "R7"]
    ]);
    $self->assert_null($res->[0][1]{destroyed});
    $self->assert_not_null($res->[0][1]{notDestroyed});
    $self->assert_num_equals(2, scalar @{$res->[1][1]{list}});

    xlog "delete active script";
    $res = $jmap->CallMethods([
        ['SieveScript/set', {
            destroy => [ $id1 ],
            onSuccessActivateScript => JSON::null
         }, "R8"],
        ['SieveScript/get', {
         }, "R9"]
    ]);
    $self->assert_not_null($res->[0][1]{destroyed});
    $self->assert_null($res->[0][1]{notDestroyed});
    $self->assert_num_equals(1, scalar @{$res->[1][1]{list}});
}

sub test_sieve_set_bad_script
    :min_version_3_3 :needs_component_sieve :needs_component_jmap :JMAPExtensions
{
    my ($self) = @_;

    my $jmap = $self->{jmap};

    xlog "create bad script";
    my $res = $jmap->CallMethods([
        ['SieveScript/set', {
            create => {
                "1" => {
                    name => "foo",
                    content => "keepme;\r\n"
                }
            }
         }, "R1"]
    ]);
    $self->assert_not_null($res);
    $self->assert_null($res->[0][1]{created});
    $self->assert_str_equals('invalidScript', $res->[0][1]{notCreated}{1}{type});

    xlog "update bad script";
    $res = $jmap->CallMethods([
        ['SieveScript/set', {
            create => {
                "1" => {
                    name => "foo",
                    content => "keep;\r\n"
                }
            },
            update => {
                "#1" => {
                    content => "keepme;\r\n"
                }
            },
            destroy => [ "#1" ]
         }, "R2"]
    ]);
    $self->assert_not_null($res);

    my $id = $res->[0][1]{created}{"1"}{id};

    $self->assert_null($res->[0][1]{updated});
    $self->assert_str_equals('invalidScript', $res->[0][1]{notUpdated}{$id}{type});
    $self->assert_not_null($res->[0][1]{destroyed});
    $self->assert_str_equals($id, $res->[0][1]{destroyed}[0]);
    $self->assert_null($res->[0][1]{notDestroyed});
}

sub test_sieve_query
    :min_version_3_3 :needs_component_sieve :needs_component_jmap :JMAPExtensions
{
    my ($self) = @_;

    my $jmap = $self->{jmap};

    xlog "create script";
    my $res = $jmap->CallMethods([
        ['SieveScript/set', {
            create => {
                "1" => {
                    name => "foo",
                    content => "keep;"
                },
                "2" => {
                    name => "bar",
                    content => "discard;"
                },
                "3" => {
                    name => "pooh",
                    content => "redirect \"test\@example.com\";"
                }
            },
            onSuccessActivateScript => "#1"
         }, "R1"],
    ]);
    $self->assert_not_null($res);
    my $id1 = $res->[0][1]{created}{"1"}{id};
    my $id2 = $res->[0][1]{created}{"2"}{id};
    my $id3 = $res->[0][1]{created}{"3"}{id};

    xlog $self, "get unfiltered list";
    $res = $jmap->CallMethods([ ['SieveScript/query', { }, "R1"] ]);
    $self->assert_num_equals(3, $res->[0][1]{total});
    $self->assert_num_equals(3, scalar @{$res->[0][1]{ids}});

    xlog $self, "filter by isActive";
    $res = $jmap->CallMethods([ ['SieveScript/query', {
                    filter => {
                        isActive => JSON::true,
                    }
                }, "R1"] ]);
    $self->assert_num_equals(1, $res->[0][1]{total});
    $self->assert_num_equals(1, scalar @{$res->[0][1]{ids}});
    $self->assert_str_equals($id1, $res->[0][1]{ids}[0]);

    xlog $self, "filter by not isActive";
    $res = $jmap->CallMethods([ ['SieveScript/query', {
                    filter => {
                        isActive => JSON::false,
                    }
                }, "R1"] ]);
    $self->assert_num_equals(2, $res->[0][1]{total});
    $self->assert_num_equals(2, scalar @{$res->[0][1]{ids}});
    $self->assert_str_equals($id2, $res->[0][1]{ids}[0]);
    $self->assert_str_equals($id3, $res->[0][1]{ids}[1]);

    xlog $self, "filter by name containing 'oo', sorted descending";
    $res = $jmap->CallMethods([ ['SieveScript/query', {
                    filter => {
                        name => 'oo',
                    },
                    sort => [{
                        property => 'name',
                        isAscending => JSON::false,
                    }]
                }, "R1"] ]);
    $self->assert_num_equals(2, $res->[0][1]{total});
    $self->assert_num_equals(2, scalar @{$res->[0][1]{ids}});
    $self->assert_str_equals($id3, $res->[0][1]{ids}[0]);
    $self->assert_str_equals($id1, $res->[0][1]{ids}[1]);

    xlog $self, "filter by name not containing 'oo'";
    $res = $jmap->CallMethods([ ['SieveScript/query', {
                    filter => {
                        operator => 'NOT',
                        conditions => [{
                            name => 'oo',
                        }]
                    },
                }, "R1"] ]);
    $self->assert_num_equals(1, $res->[0][1]{total});
    $self->assert_num_equals(1, scalar @{$res->[0][1]{ids}});
    $self->assert_str_equals($id2, $res->[0][1]{ids}[0]);

    xlog $self, "filter by name containing 'oo' and inactive";
    $res = $jmap->CallMethods([ ['SieveScript/query', {
                    filter => {
                        operator => 'AND',
                        conditions => [{
                            name => 'oo',
                            isActive => JSON::false,
                        }]
                    },
                }, "R1"] ]);
    $self->assert_num_equals(1, $res->[0][1]{total});
    $self->assert_num_equals(1, scalar @{$res->[0][1]{ids}});
    $self->assert_str_equals($id3, $res->[0][1]{ids}[0]);

    xlog $self, "filter by name not containing 'oo' or active";
    $res = $jmap->CallMethods([ ['SieveScript/query', {
                    filter => {
                        operator => 'OR',
                        conditions => [
                        {
                            operator => 'NOT',
                            conditions => [{
                                name => 'oo',
                            }]
                        },
                        {
                            isActive => JSON::true,
                        }]
                    },
                    sort => [{
                        property => 'name',
                        isAscending => JSON::true,
                    }]
                }, "R1"] ]);
    $self->assert_num_equals(2, $res->[0][1]{total});
    $self->assert_num_equals(2, scalar @{$res->[0][1]{ids}});
    $self->assert_str_equals($id2, $res->[0][1]{ids}[0]);
    $self->assert_str_equals($id1, $res->[0][1]{ids}[1]);
}

sub test_sieve_validate
    :min_version_3_3 :needs_component_sieve :needs_component_jmap :JMAPExtensions
{
    my ($self) = @_;

    my $jmap = $self->{jmap};

    xlog "validating scripts";
    my $res = $jmap->CallMethods([
        ['SieveScript/validate', {
            content => JSON::null
         }, "R1"],
        ['SieveScript/validate', {
            content => "keepme;\r\n",
            content => JSON::null
         }, "R2"],
        ['SieveScript/validate', {
            content => "keepme;\r\n"
         }, "R3"],
        ['SieveScript/validate', {
            content => "keep;\r\n"
         }, "R4"],
    ]);
    $self->assert_not_null($res);

    $self->assert_str_equals("error", $res->[0][0]);
    $self->assert_str_equals("invalidArguments", $res->[0][1]{type});

    $self->assert_str_equals("error", $res->[1][0]);
    $self->assert_str_equals("invalidArguments", $res->[1][1]{type});

    $self->assert_str_equals("SieveScript/validate", $res->[2][0]);
    $self->assert_equals(JSON::false, $res->[2][1]{isValid});
    $self->assert_not_null($res->[2][1]{errorDescription});

    $self->assert_str_equals("SieveScript/validate", $res->[3][0]);
    $self->assert_equals(JSON::true, $res->[3][1]{isValid});
    $self->assert_null($res->[3][1]{errorDescription});
}

sub test_sieve_test
    :min_version_3_3 :needs_component_jmap :JMAPExtensions
{
    my ($self) = @_;

    my $script = <<EOF;
require ["fileinto", "imap4flags", "copy", "variables", "mailbox", "mailboxid", "special-use"];
if header "subject" "Memo" {
  fileinto :copy :flags ["\\flagged", "\\answered"] :specialuse "\\flagged" :mailboxid "123" :create "INBOX.foo";
  setflag "\\seen\";
}
EOF
    $script =~ s/\r?\n/\r\n/gs;
    $script =~ s/\\/\\\\/gs;

    my $jmap = $self->{jmap};

    xlog "create script";
    my $res = $jmap->CallMethods([
        ['SieveScript/set', {
            create => {
                "1" => {
                    name => "foo",
                    content => "$script"
                }
            }
         }, "R1"]
    ]);
    $self->assert_not_null($res);

    my $scriptid = $res->[0][1]{created}{"1"}{blobId};

    xlog "create email";
    $res = $jmap->CallMethods([['Mailbox/get', { properties => ["id"] }, "R1"]]);
    my $inboxid = $res->[0][1]{list}[0]{id};

    my $email =  {
        mailboxIds => { $inboxid => JSON::true },
        from => [ { name => "Yosemite Sam", email => "sam\@acme.local" } ] ,
        to => [ { name => "Bugs Bunny", email => "bugs\@acme.local" }, ],
        subject => "Memo",
        textBody => [{ partId => '1' }],
        bodyValues => { '1' => { value => "Whoa!" }}
    };

    $res = $jmap->CallMethods([
        ['Email/set', { create => { "1" => $email }}, "R2"],
    ]);

    my $emailid = $res->[0][1]{created}{"1"}{blobId};

    xlog "test script";
    $res = $jmap->CallMethods([
        ['SieveScript/test', {
            scriptBlobId => "$scriptid",
            emailBlobIds => [ "$emailid" ],
            envelope => JSON::null,
            lastVacationResponse => JSON::null
         }, "R3"]
    ]);
    $self->assert_not_null($res);
    $self->assert_not_null($res->[0][1]{completed});
    $self->assert_str_equals('fileinto',
                             $res->[0][1]{completed}{$emailid}[0][0]);
    $self->assert_str_equals('keep',
                             $res->[0][1]{completed}{$emailid}[1][0]);
    $self->assert_null($res->[0][1]{notCompleted});
}

sub test_sieve_test_upload
    :min_version_3_3 :needs_component_jmap :JMAPExtensions
{
    my ($self) = @_;

    my $email1 = <<'EOF';
From: "Some Example Sender" <example@example.com>
To: cassandane@example.com
Subject: test email
Date: Wed, 7 Dec 2016 22:11:11 +1100
MIME-Version: 1.0
Content-Type: text/plain; charset="UTF-8"
Content-Transfer-Encoding: quoted-printable

This is a test email.
EOF
    $email1 =~ s/\r?\n/\r\n/gs;

    my $email2 = <<'EOF';
From: "Some Example Sender" <example@example.com>
To: cassandane@example.com
Subject: Hello!
Date: Wed, 7 Dec 2016 22:11:11 +1100
MIME-Version: 1.0
Content-Type: text/plain; charset="UTF-8"
Content-Transfer-Encoding: quoted-printable

This is a test email.
EOF
    $email2 =~ s/\r?\n/\r\n/gs;

    my $script = <<EOF;
require ["fileinto", "imap4flags", "copy", "variables", "mailbox", "mailboxid", "special-use", "vacation"];
if header :contains "subject" "test" {
  setflag "\\Seen\";
  fileinto :copy :flags ["\\Flagged", "\\Answered"] :specialuse "\\Flagged" :mailboxid "M123" :create "INBOX.foo";
}
else {
  vacation "Gone fishin'";
}
EOF
    $script =~ s/\r?\n/\r\n/gs;
    $script =~ s/\\/\\\\/gs;

    my $jmap = $self->{jmap};

    my $res = $jmap->Upload($email1, "message/rfc822");
    my $emailid1 = $res->{blobId};

    $res = $jmap->Upload($email2, "message/rfc822");
    my $emailid2 = $res->{blobId};

    $res = $jmap->Upload($script, "application/sieve");
    my $scriptid = $res->{blobId};

    xlog "test script";
    $res = $jmap->CallMethods([
        ['SieveScript/test', {
            emailBlobIds => [ $emailid1, 'foobar', $emailid2 ],
            scriptBlobId => $scriptid,
            envelope => {
                mailFrom => {
                    email => 'foo@example.com',
                    parameters => JSON::null
                },
                rcptTo => [ {
                    email => 'cassandane@example.com',
                    parameters => JSON::null
                } ]
            },
            lastVacationResponse => JSON::null
         }, "R1"]
    ]);
    $self->assert_not_null($res);

    $self->assert_not_null($res->[0][1]{completed});
    $self->assert_str_equals('fileinto',
                             $res->[0][1]{completed}{$emailid1}[0][0]);
    $self->assert_str_equals('keep',
                             $res->[0][1]{completed}{$emailid1}[1][0]);
    $self->assert_str_equals('vacation',
                             $res->[0][1]{completed}{$emailid2}[0][0]);
    $self->assert_str_equals('keep',
                             $res->[0][1]{completed}{$emailid2}[1][0]);

    $self->assert_not_null($res->[0][1]{notCompleted});
    $self->assert_str_equals('blobNotFound',
                             $res->[0][1]{notCompleted}{foobar}{type});
}

sub test_sieve_test_singlecommand
    :min_version_3_3 :needs_component_jmap :JMAPExtensions
{
    my ($self) = @_;

    my $email1 = <<'EOF';
From: "Some Example Sender" <example@example.com>
To: cassandane@example.com
Subject: test email
Date: Wed, 7 Dec 2016 22:11:11 +1100
MIME-Version: 1.0
Content-Type: text/plain; charset="UTF-8"
Content-Transfer-Encoding: quoted-printable

This is a test email.
EOF
    $email1 =~ s/\r?\n/\r\n/gs;

    my $email2 = <<'EOF';
From: "Some Example Sender" <example@example.com>
To: cassandane@example.com
Subject: Hello!
Date: Wed, 7 Dec 2016 22:11:11 +1100
MIME-Version: 1.0
Content-Type: text/plain; charset="UTF-8"
Content-Transfer-Encoding: quoted-printable

This is a test email.
EOF
    $email2 =~ s/\r?\n/\r\n/gs;

    my $script = <<EOF;
require ["fileinto", "imap4flags", "copy", "variables", "mailbox", "mailboxid", "special-use", "vacation"];
if header :contains "subject" "test" {
  setflag "\\Seen\";
  fileinto :copy :flags ["\\Flagged", "\\Answered"] :specialuse "\\Flagged" :mailboxid "M123" :create "INBOX.foo";
}
else {
  vacation "Gone fishin'";
}
EOF
    $script =~ s/\r?\n/\r\n/gs;
    $script =~ s/\\/\\\\/gs;

    my $jmap = $self->{jmap};

    xlog "test script";
    my $res = $jmap->CallMethods([
        ['Blob/set', {
            create => {
                "1" => { content => $email1 },
                "3" => { content => $email2 },
                "2" => { content => $script }
            }}, 'R0'],
        ['SieveScript/test', {
            emailBlobIds => [ '#1', 'foobar', '#3' ],
            scriptBlobId => '#2',
            envelope => {
                mailFrom => {
                    email => 'foo@example.com',
                    parameters => JSON::null
                },
                rcptTo => [ {
                    email => 'cassandane@example.com',
                    parameters => JSON::null
                } ]
            },
            lastVacationResponse => JSON::null
         }, "R1"]
    ]);
    $self->assert_not_null($res);

    my $emailid1 = $res->[0][1]{created}{1}{blobId};
    my $emailid2 = $res->[0][1]{created}{3}{blobId};

    $self->assert_not_null($res->[1][1]{completed});
    $self->assert_str_equals('fileinto',
                             $res->[1][1]{completed}{$emailid1}[0][0]);
    $self->assert_str_equals('keep',
                             $res->[1][1]{completed}{$emailid1}[1][0]);
    $self->assert_str_equals('vacation',
                             $res->[1][1]{completed}{$emailid2}[0][0]);
    $self->assert_str_equals('keep',
                             $res->[1][1]{completed}{$emailid2}[1][0]);

    $self->assert_not_null($res->[1][1]{notCompleted});
    $self->assert_str_equals('blobNotFound',
                             $res->[1][1]{notCompleted}{foobar}{type});
}

1;
