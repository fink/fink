#!/usr/bin/perl -w

use strict;
use Test::More tests=>14;

require_ok('Fink::Services');          # 1

# exported functions
use_ok('Fink::Services','execute');    # 2

# needed for passing 'fink --build-as-nobody' flag to execute()
# (don't really care how it's implemented, but these tests are currently
# written for it being implemented with Fink::Config options)
require_ok('Fink::Config');            # 3
can_ok('Fink::Config','get_option');   # 4
can_ok('Fink::Config','set_options');  # 5

### FIXME: File::Temp is not present until perl-5.6.1, so need to
### rewrite this for use on OS X 10.2 (perl-5.6.0). Maybe use
### /usr/bin/mktemp (which has no -p flag on OS X 10.2).
# need a a safe place to create files
use_ok('File::Temp', 'tempdir');       # 6
my $tmpdir = tempdir( 'execute_nonroot_okay.t_XXXXX',
		      DIR => '/tmp',  # dir itself be accessible to *all* users
#		      CLEANUP => 1    # wish this worked:(
		    );
length $tmpdir or die "Bail out! cannot create scratchdir\n";
chmod 0755, $tmpdir;  # only root can write to this dir

# We cannot use tempdir(CLEANUP=>1) because that works by installing
# an END block to do the cleanup, which breaks us because %execute may
# be implemented with forks: the END block runs when each child ends
# not just at the end of the parent (== this test script). Damn it.
use_ok('File::Path', 'rmtree');        # 7

chdir "/tmp";         # user="nobody" must start shells in the local dir

# 8
Fink::Config::set_options( {'build_as_nobody' => 0} );
cmp_ok( &execute("touch $tmpdir/f1", nonroot_okay=>1),
	'==', 0,
	'disabling build_as_nobody causes normal execution'
      );

# 9
Fink::Config::set_options( {'build_as_nobody' => 1} );
cmp_ok( &execute("touch $tmpdir/f2 >/dev/null 2>&1"),
	'==', 0,
	'omitting nonroot_okay option causes normal execution'
      );

# 10
Fink::Config::set_options( {'build_as_nobody' => 1} );
cmp_ok( &execute("touch $tmpdir/f3", nonroot_okay=>0),
      '==', 0,
	'false nonroot_okay option causes normal execution'
      );

# 11
 SKIP: {
     Fink::Config::set_options( {'build_as_nobody' => 1} );
     skip "You must be non-root for this test", 1 if $> == 0;
     # this touch should fail noisily, so redirect
     cmp_ok( &execute("touch $tmpdir/f4 > /dev/null 2>&1", nonroot_okay=>1),
	     '!=', 0,
	     'try to switch users when not root'
	   );
 }

# 12
 SKIP: {
     Fink::Config::set_options( {'build_as_nobody' => 1} );
     skip "You must be root for this test", 1 if $> != 0;
     # this touch should fail noisily, so redirect
     cmp_ok( &execute("touch $tmpdir/f5 > /dev/null 2>&1", nonroot_okay=>1),
	     '!=', 0,
	     'requires normal user but build_as_nobody enabled'
	   );
 }

# 13
 SKIP: {
     Fink::Config::set_options( {'build_as_nobody' => 1} );
     skip "You must be root for this test", 1 if $> != 0;
     cmp_ok( &execute("/usr/bin/touch $tmpdir", nonroot_okay=>1),
	     '==', 0,
	     'user "nobody" can do this and build_as_nobody enabled'
	   );
 }

# 14
 SKIP: {
     skip "You must be root for this test", 1 if $> != 0;

     # this test should use the exact same perl binary as is running
     # this test (which is the same as the one to be used to run fink)
     Fink::Config::set_options( {'build_as_nobody' => 1} );
     cmp_ok( &execute('/usr/bin/perl -e \'print "hello\n"\' > /dev/null', nonroot_okay=>1),
	     '==', 0,
	     'command is not run under setuid'
	   );
 }

# clean up tempdir ourselves to work around File:Temp bug
rmtree($tmpdir, 0, 1);

