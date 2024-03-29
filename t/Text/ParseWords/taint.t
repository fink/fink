#!./perl -Tw
# [perl #33173] shellwords.pl and tainting

# this file taken from Text-ParseWords-3.29/t/taint.t on CPAN.
# converted to Fink namespace by The Fink Project.

use strict;
use warnings;

BEGIN {
    if ( $ENV{PERL_CORE} ) {
        chdir 't' if -d 't';
        @INC = '../lib';
        require Config;
        no warnings 'once';
        if ($Config::Config{extensions} !~ /\bList\/Util\b/) {
            print "1..0 # Skip: Scalar::Util was not built\n";
            exit 0;
        }
        if (exists($Config::Config{taint_support}) && not $Config::Config{taint_support}) {
            print "1..0 # Skip: your perl was built without taint support\n";
            exit 0;
        }
    }
}

use Fink::Text::ParseWords qw(shellwords old_shellwords);
use Scalar::Util qw(tainted);

print "1..2\n";

print "not " if grep { not tainted($_) } shellwords("$0$^X");
print "ok 1\n";

print "not " if grep { not tainted($_) } old_shellwords("$0$^X");
print "ok 2\n";
