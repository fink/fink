#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

require_ok('Fink::Services');

# exported functions
use_ok('Fink::Services','execute_script_nonroot_okay');

# for passing 'fink --build-as-nobody' flag to execute*_nonroot_okay
# (don't really care how it's implemented, but these tests are currently
# written for it being implemented with Fink::Config options)
require_ok('Fink::Config');
can_ok('Fink::Config','get_option');
can_ok('Fink::Config','set_options');

# anyone can write to /tmp (local dir could be chmod 700 to a user)
use_ok('File::Temp', 'tempdir');
my $tmpdir = tempdir( 'execute_script_nonroot_okay.t_XXXXX', DIR => '/tmp', CLEANUP => 1);
$tmpdir or die "Bailing--cannot create scratchdir\n";
chmod 0755, $tmpdir;  # only root can write to this dir
chdir "/tmp";         # "nobody" must start shells here in order to test

my $result;

Fink::Config::set_options( {'build_as_nobody' => 0} );
eval { $result = &execute_script_nonroot_okay("touch $tmpdir/f1 >/dev/null 2>&1") };
like("$result: $@", qr/^0: /, 'requires original user; build_as_nobody disabled');

SKIP: {
    skip "You must be non-root for this test", 1 if $> == 0;

    Fink::Config::set_options( {'build_as_nobody' => 1} );
    eval { $result = &execute_script_nonroot_okay("touch $tmpdir/f2 >/dev/null 2>&1") };
    like("$result: $@", qr/EUID/, 'try to set EUID when not root');
}

SKIP: {
    skip "You must be root for this test", 1 if $> != 0;

    Fink::Config::set_options( {'build_as_nobody' => 1} );
    eval { $result = &execute_script_nonroot_okay("touch $tmpdir/f2 >/dev/null 2>&1") };
    unlike("$result: $@", qr/^0: /, 'requires original user but build_as_nobody enabled');
}
