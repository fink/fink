#!/usr/bin/perl
use warnings;
use strict;

use Test::More 'no_plan';
use File::Temp qw(tempfile);

use Fink::CLI qw(capture);
use Fink::Services	qw(lock_wait execute);
use Fink::Command	qw(touch);

sub run_script {
	my $script = shift;
	my ($out, $ret);
	
	$script = "#!/usr/bin/perl\nuse Fink::Finally;\n$script";
	local $ENV{PERL5LIB} = join(':', @INC);
	capture {
		$ret = execute($script, quiet => 1, delete_tempfile => -1);
	} \$out, \$out;
	return wantarray ? ($out, $ret) : $out;
}	

##### TESTS

# use
BEGIN { use_ok 'Fink::Finally'; }

##### SIMPLE

# simple, bad args
{
	eval { Fink::Finally::Simple->new };
	ok($@, 'simple, bad args - no args');
	eval { Fink::Finally::Simple->new('not code') };
	ok($@, 'simple, bad args - not a code ref');
}

# simple, explicit run
{
	my $x = 0;
	my $finally = Fink::Finally::Simple->new(sub { $x++ });
	$finally->cleanup;
	is($x, 1, 'simple, explicit run');
}

# simple, run when we fall out of scope
{
	my $x = 0;
	{
		my $finally = Fink::Finally::Simple->new(sub { $x++ });
	}
	is($x, 1, 'simple, run when we fall out of scope');
}

# simple, run when an exception is thrown
{
	my $x = 0;
	eval {
		my $finally = Fink::Finally::Simple->new(sub { $x++ });
		die "exception!";
	};
	ok($@, 'simple, run when an exception is thrown - exception thrown');
	is($x, 1, 'simple, run when an exception is thrown - executed');
}

# simple, only run once
{
	my $x = 0;
	{
		my $finally = Fink::Finally::Simple->new(sub { $x++ });
		$finally->cleanup;
		$finally->cleanup;
		# out of scope => automatic run
	}
	is($x, 1, 'simple, only run once');
}

# simple, run on exit()
{
	my $out = run_script <<'SCRIPT';
my $finally = Fink::Finally::Simple->new(sub { print "cleanup\n" });
exit 0;
SCRIPT
	is($out, "cleanup\n", "simple, run on exit()");
}

# simple, cancelled finalizers don't run
{
	my $x = 0;
	{
		my $fin = Fink::Finally::Simple->new(sub { $x++ });
		$fin->cancel_cleanup;
		$fin->cleanup;
	} # out of scope
	is($x, 0, "simple, cancelled finalizers don't run");
}


# simple, fork
{
	(undef, my $file) = tempfile("finally.fork.XXXX");
	touch($file);
	
	{
		my $fork; # did we fork or not?
		my $fin = Fink::Finally::Simple->new(sub { unlink $file });
		
		$fork = fork;
		if ($fork) {
			wait;
			ok(-f $file, "simple, fork - don't run in child");
		} else {
			exit 0;
		}
	}
	ok(!-f $file, "simple, fork - run in parent");
}

# simple, exit status unchanged
{
	my ($out, $status) = run_script <<'SCRIPT';
my $finally = Fink::Finally::Simple->new(sub { system("echo finalizer") });
exit 2;
SCRIPT
	is($out, "finalizer\n", 'simple, exit status unchanged - finalizer ran');
	is($status, 2, 'simple, exit status unchanged - correct status');
}

# simple, exception status unchanged
{
	{
		my $fin = Fink::Finally::Simple->new(sub { eval {}; });
		eval { die "test\n" };
	}
	is($@, "test\n", "simple, exception status unchanged");
}

##### OO

package FF::Incr;
use base 'Fink::Finally';
our $x = 0;
sub finalize { $x++ }

package main;
our $ix;
*ix = *FF::Incr::x;

# OO, explicit run
{
	$ix = 0;
	my $finally = FF::Incr->new;
	$finally->cleanup;
	is($ix, 1, 'OO, explicit run');
}

# OO, run when we fall out of scope
{
	$ix = 0;
	{
		my $finally = FF::Incr->new;
	}
	is($ix, 1, 'OO, run when we fall out of scope');
}

# OO, run when an exception is thrown
{
	$ix = 0;
	eval {
		my $finally = FF::Incr->new;
		die "exception!";
	};
	ok($@, 'OO, run when an exception is thrown - exception thrown');
	is($ix, 1, 'OO, run when an exception is thrown - executed');
}

# OO, only run once
{
	$ix = 0;
	{
		my $finally = FF::Incr->new;
		$finally->cleanup;
		$finally->cleanup;
		# out of scope => automatic run
	}
	is($ix, 1, 'OO, only run once');
}

# OO, run on exit()
{
	my $out = run_script <<'SCRIPT';
package FF::Print;
use base 'Fink::Finally';
sub finalize { print "cleanup\n" }

package main;
my $finally = FF::Print->new;
exit 0;
SCRIPT
	is($out, "cleanup\n", "OO, run on exit()");
}

# OO, cancelled finalizers don't run
{
	$ix = 0;
	{
		my $fin = FF::Incr->new;
		$fin->cancel_cleanup;
		$fin->cleanup;
	} # out of scope
	is($x, 0, "OO, cancelled finalizers don't run");
}

# OO, initializer and private storage
package FF::Init;
use base 'Fink::Finally';
sub initialize {
	my ($self, $sc) = @_;
	$self->{sc} = $sc;
	$self->SUPER::initialize;
}
sub finalize { ${$_[0]->{sc}}++ }

package main;
{
	my $x = 0;
	{
		my $finally = FF::Init->new(\$x);
	}
	is($x, 1, 'OO, initializer and private storage');
}

# OO, fork
package FF::Unlink;
use base 'Fink::Finally';
sub initialize	{ $_[0]->{file} = $_[1]; $_[0]->SUPER::initialize; }
sub finalize	{ unlink $_[0]->{file}	}

package main;
{
	(undef, my $file) = tempfile("finally.fork.XXXX");
	touch($file);
	
	{
		my $fork; # did we fork or not?
		my $fin = FF::Unlink->new($file);
		
		$fork = fork;
		if ($fork) {
			wait;
			ok(-f $file, "OO, fork - don't run in child");
		} else {
			exit 0;
		}
	}
	ok(!-f $file, "OO, fork - run in parent");
}

# OO, exit status unchanged
{
	my ($out, $status) = run_script <<'SCRIPT';
package FF::Echo;
use base 'Fink::Finally';
sub finalize { system("echo finalizer") }

package main;
my $finally = FF::Echo->new;
exit 2;
SCRIPT
	is($out, "finalizer\n", 'OO, exit status unchanged - finalizer ran');
	is($status, 2, 'OO, exit status unchanged - correct status');
}

# OO, exception status unchanged
package FF::Eval;
use base 'Fink::Finally';
sub finalize { eval {}; }

package main;
{
	{
		my $fin = FF::Eval->new;
		eval { die "test\n" };
	}
	is($@, "test\n", "OO, exception status unchanged");
}
