#!/usr/bin/perl
use warnings;
use strict;

use Test::More 'no_plan';
use File::Temp qw(tempfile);

use Fink::CLI qw(capture);
use Fink::Services	qw(lock_wait execute);
use Fink::Command	qw(touch);

BEGIN { use_ok 'Fink::Finally'; }

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

# bad args
{
	eval { Fink::Finally->new };
	ok($@, 'bad args - no args');
	eval { Fink::Finally->new('not code') };
	ok($@, 'bad args - not a code ref');
}

# explicit run
{
	my $x = 0;
	my $finally = Fink::Finally->new(sub { $x++ });
	$finally->run;
	is($x, 1, 'explicit run');
}

# run when we fall out of scope
{
	my $x = 0;
	{
		my $finally = Fink::Finally->new(sub { $x++ });
	}
	is($x, 1, 'run when we fall out of scope');
}

# run when an exception is thrown
{
	my $x = 0;
	eval {
		my $finally = Fink::Finally->new(sub { $x++ });
		die "exception!";
	};
	ok($@, 'run when an exception is thrown - exception thrown');
	is($x, 1, 'run when an exception is thrown - executed');
}

# only run once
{
	my $x = 0;
	{
		my $finally = Fink::Finally->new(sub { $x++ });
		$finally->run;
		$finally->run;
		# out of scope => automatic run
	}
	is($x, 1, 'only run once');
}

# run on exit()
{
	my $out = run_script <<'SCRIPT';
my $finally = Fink::Finally->new(sub { print "cleanup\n" });
exit 0;
SCRIPT
	is($out, "cleanup\n", "run on exit()");
}

# cancelled finalizers don't run
{
	my $x = 0;
	{
		my $fin = Fink::Finally->new(sub { $x++ });
		$fin->cancel;
		$fin->run;
	} # out of scope
	is($x, 0, "cancelled finalizers don't run");
}


# fork doesn't run Finally objects in the subproc
{
	my $dummy;
	($dummy, my $file) = tempfile("capture.fork.XXXX");
	touch($file);
	
	{
		my $fork; # did we fork or not?
		my $fin = Fink::Finally->new(sub { unlink $file });
		
		$fork = fork;
		if ($fork) {
			wait;
			ok(-f $file, "fork doesn't run Finally objects in the subproc");
		} else {
			exit 0;
		}
	}
}

# exit status unchanged
{
	my ($out, $status) = run_script <<'SCRIPT';
my $finally = Fink::Finally->new(sub { system("echo finalizer") });
exit 2;
SCRIPT
	is($out, "finalizer\n", 'exit status unchanged - finalizer ran');
	is($status, 2, 'exit status unchanged - correct status');
}

	
