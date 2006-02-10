#!/usr/bin/perl -w

use strict;
use Test::More tests => 2;

my $vsdbutil;
foreach (qw{ /usr/sbin/vsdbutil }) {
    $vsdbutil = $_ if -x $_;
}

unlike( $ENV{PREFIX}, qr/\s/, "Whitespace found in fink prefix \"$ENV{PREFIX}\"" );  # 1

SKIP: {
    my $skips = 1;

    my @cmd_out;

    @cmd_out = `/bin/df "$ENV{PREFIX}" 2>&1`;
    my($volume);
    ($volume) = $cmd_out[1] =~ /^[^%]+%\s+(\/.*)/ if defined $cmd_out[1];

    skip "Could not parse volume name from `/bin/df $ENV{PREFIX}`", $skips unless @cmd_out==2 && defined $volume;
    skip "Could not find vsdbutil", $skips unless defined $vsdbutil;
    
    @cmd_out = `$vsdbutil -c "$volume" 2>&1`;
    # 2
    if (@cmd_out == 0) {
	ok "Permissions enabled on volume \"$volume\"";
    } elsif ($cmd_out[0] =~ /^no entry/) {
	diag "Could not determine permissions info for volume \"$volume\" (try running \"sudo $vsdbutil -i\")";
	pass;
    } elsif ($cmd_out[0] =~ /disabled\.$/) {
	fail "Permissions not enabled on volume \"$volume\" (check the Finder \"Get Info\" dialog)";
    } elsif ($cmd_out[0] =~ /enabled\.$/) {
	pass "Permissions enabled on volume \"$volume\"";
    } else { 
	fail "Could not parse permissions status from `$vsdbutil -c $volume`";
    }
}
