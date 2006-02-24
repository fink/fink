#!/usr/bin/perl -w

use strict;
use Test::More tests=>12;

require_ok('Fink::Services');          # 1

# exported functions
use_ok('Fink::Services','execute');    # 2

# needed for passing 'fink --build-as-nobody' flag to execute()
# (don't really care how it's implemented, but these tests are currently
# written for it being implemented with Fink::Config options)
require_ok('Fink::Config');            # 3
can_ok('Fink::Config','get_option');   # 4
can_ok('Fink::Config','set_options');  # 5

# need a a safe place to create files

# OS X 10.2 comes with perl 5.6.0, but File::Temp isn't in core until 5.6.1
#use File::Temp (qw/ tempdir /);
#my $tmpdir = tempdir( 'execute_nonroot_okay.t_XXXXX',
#		      DIR => '/tmp',  # dir itself be accessible to *all* users
##		      CLEANUP => 1    # CLEANUP is unsafe (see 'rmtree' below)
#		    );

# OS X 10.2 mktemp does not have the -p flag implemented
my $mktemp;
foreach (qw| /usr/bin/mktemp /bin/mktemp |) {
    if (-x $_) {
	$mktemp = $_;
	last;
    }
}
if (!defined $mktemp) {
    print "Bail out! Cannot create scratchdir (no mktemp found)\n";
    die "\n";
}

my $tmpdir = `$mktemp -d /tmp/execute_nonroot_okay.t_XXXXX`;
chomp $tmpdir;

if (!defined $tmpdir or !length $tmpdir or !-d $tmpdir) {
    print "Bail out! Cannot create scratchdir\n";
    die "\n";
}
chmod 0755, $tmpdir;  # must have only root be able to write to dir but all read

# Need a world-readable set of Fink perl modules, but local perlmod/
# set might not be accessible (permissions) and fink might not be
# installed or in PERL5LIB.  Don't want to go changing perms on the
# whole hierarchy leading to whereever user is running test, so make a
# copy in a known place with good perms.
{
	my $libdir = "$tmpdir/perlmod";
	if (system qq{ cp -r ../perlmod "$tmpdir" && chmod -R ugo=r,a+X "$libdir" }) {
		diag "Could not create temp Fink directory; using local copy instead.\nDepending on permissions and the presence of an existing Fink, this\nsituation may result in apparently-missing Services.pm or various exported functions.\n";
	} else {
		# need subprocesses to see it, so can't just adjust our @INC
		$ENV{'PERL5LIB'} = defined $ENV{'PERL5LIB'}
			? "$libdir:$ENV{'PERL5LIB'}"
			: $libdir;
    }
}

chdir "/tmp";         # set local dir to where user="nobody" can start shells

# 6
Fink::Config::set_options( {'build_as_nobody' => 0} );
cmp_ok( &execute("touch $tmpdir/f1", nonroot_okay=>1),
	'==', 0,
	'disabling build_as_nobody causes normal execution'
      );

# 7
Fink::Config::set_options( {'build_as_nobody' => 1} );
cmp_ok( &execute("touch $tmpdir/f2"),
	'==', 0,
	'omitting nonroot_okay option causes normal execution'
      );

# 8
Fink::Config::set_options( {'build_as_nobody' => 1} );
cmp_ok( &execute("touch $tmpdir/f3", nonroot_okay=>0),
      '==', 0,
	'false nonroot_okay option causes normal execution'
      );

# 9
 SKIP: {
     Fink::Config::set_options( {'build_as_nobody' => 1} );
     skip "You must be non-root for this test", 1 if $> == 0;
     # this touch should fail noisily, so redirect
     cmp_ok( &execute("touch $tmpdir/f4 > /dev/null 2>&1", nonroot_okay=>1),
	     '!=', 0,
	     'try to switch users when not root'
	   );
 }

# 10
 SKIP: {
     Fink::Config::set_options( {'build_as_nobody' => 1} );
     skip "You must be root for this test", 1 if $> != 0;
     # this touch should fail noisily, so redirect
     cmp_ok( &execute("touch $tmpdir/f5 > /dev/null 2>&1", nonroot_okay=>1, delete_tempfile=>1),
	     '!=', 0,
	     'requires normal user but build_as_nobody enabled'
	   );
 }

# 11
 SKIP: {
     Fink::Config::set_options( {'build_as_nobody' => 1} );
     skip "You must be root for this test", 1 if $> != 0;
     my $file = "$tmpdir/f6";
     open FOO, ">$file";
     close FOO;
     chmod 0666, $file;  # create a file that all users can touch
     cmp_ok( &execute("touch $file", nonroot_okay=>1),
	     '==', 0,
	     'user "nobody" can do this and build_as_nobody enabled'
	   );
 }

# 12
 SKIP: {
     skip "You must be root for this test", 1 if $> != 0;

     # this test should use the exact same perl binary as is running
     # this test (which is the same as the one to be used to run fink)
     Fink::Config::set_options( {'build_as_nobody' => 1} );
     cmp_ok( &execute('/usr/bin/perl -e "1;"', nonroot_okay=>1),
	     '==', 0,
	     'command is not run under setuid'
	   );
 }

# We cannot use tempdir(CLEANUP=>1) because that works by installing
# an END block to do the cleanup, which breaks us because &execute may
# be implemented with forks: the END block runs when each child ends
# not just at the end of the parent (== this test script). Damn it.
use File::Path (qw/ rmtree /);
rmtree($tmpdir, 0, 0);
