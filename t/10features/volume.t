#!/usr/bin/perl -w

use strict;
use Test::More tests => 2;

unlike( $ENV{PREFIX}, qr/\s/, "Whitespace prohibited in fink prefix ($ENV{PREFIX})" );  # 1

SKIP: {
    my $skips = 1;

    my $cmd = "/usr/sbin/diskutil info \"$ENV{PREFIX}\" 2>&1";
    my @cmd_out = `$cmd`;

    skip "Could not run `$cmd`", $skips unless @cmd_out && !$?;

    @cmd_out = map { /(?:Permissions|Owners):\s*(Enabled|Disabled)/ } @cmd_out;
    skip "Could not find Owners or Permissions flag in output of `$cmd`", $skips unless @cmd_out == 1;

    is( $cmd_out[0], 'Enabled', 'Permissions must be enabled on target volume' );  # 2
}
