#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';
use Fink::Command qw(cat touch mkdir_p);
use File::Basename;

BEGIN { use_ok 'Fink::FinkVersion', ':ALL'; }

{
    my $fink_version = cat '../VERSION';
    chomp $fink_version;
    is( fink_version, , $fink_version, 'fink_version matches VERSION' );
}
