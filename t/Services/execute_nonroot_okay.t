#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

require_ok('Fink::Services');

# exported functions
use_ok('Fink::Services','execute');

# needed for passing 'fink --build-as-nobody' flag to execute()
# (don't really care how it's implemented, but these tests are currently
# written for it being implemented with Fink::Config options)
require_ok('Fink::Config');
can_ok('Fink::Config','get_option');
can_ok('Fink::Config','set_options');

# anyone can write to /tmp (local dir could be chmod 700 to a user)
use_ok('File::Temp', 'tempdir');
my $tmpdir = tempdir( 'execute_nonroot_okay.t_XXXXX', DIR => '/tmp', CLEANUP => 1);
$tmpdir or die "Bailing--cannot create scratchdir\n";
chmod 0755, $tmpdir;  # only root can write to this dir
chdir "/tmp";         # "nobody" must start shells here in order to test

my $result;

Fink::Config::set_options( {'build_as_nobody' => 0} );
eval { $result = &execute("touch $tmpdir/f1 >/dev/null 2>&1", nonroot_okay=>1) };
like("$result: $@", qr/^0: /, 'disabling build_as_nobody causes normal execution');

Fink::Config::set_options( {'build_as_nobody' => 1} );
eval { $result = &execute("touch $tmpdir/f2 >/dev/null 2>&1") };
like("$result: $@", '/^0: /', 'omitting nonroot_okay option causes normal execution');

Fink::Config::set_options( {'build_as_nobody' => 1} );
eval { $result = &execute("touch $tmpdir/f3 >/dev/null 2>&1", nonroot_okay=>0) };
like("$result: $@", '/^0: /', 'false nonroot_okay option causes normal execution');

Fink::Config::set_options( {'build_as_nobody' => 1} );
eval { $result = &execute("touch $tmpdir/f4 >/dev/null 2>&1", nonroot_okay=>1) };
 SKIP: {
     skip "You must be non-root for this test", 1 if $> == 0;
     like("$result: $@", '/^\d+: .*EUID/', 'try to set EUID when not root');
 }
 SKIP: {
     skip "You must be root for this test", 1 if $> != 0;
     unlike("$result: $@", '/^0: /', 'requires normal user but build_as_nobody enabled');
 }

 SKIP: {
     skip "You must be root for this test", 1 if $> != 0;
   TODO: {
       local $TODO = "cannot fully drop root yet";

     # this test should use the exact same perl binary as is running
     # this test (which is the same as the one to be used to run fink)
     Fink::Config::set_options( {'build_as_nobody' => 1} );
     eval { $result = &execute('/usr/bin/perl -e \'print "hello\n"\' > /dev/null', nonroot_okay=>1) };
     like("$result: $@", '/^0: /', 'command is not run under setuid');
   }
}
