#!/usr/bin/perl -w

use strict;

if (eval {require Test::More} ) {
    die "\nThis first test is designed to die, so please ignore the error\n"
    . "message on the next line.\n";
} else {
    print "\nBail out!  Can't find Test::More\n";
    print STDERR <<ERROR;

$@

This is normal if you are bootstrapping fink, or upgrading to
fink 0.18.0 for the first time.  Otherwise, you need to install 
the test-simple-pm package or perl >= v5.8.0.

ERROR
}
