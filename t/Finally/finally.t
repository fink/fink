#!/usr/bin/perl
use warnings;
use strict;

use Test::More 'no_plan';
use File::Temp qw(tempfile);

use Fink::Services	qw(lock_wait);
use Fink::Command	qw(touch);

BEGIN { use_ok 'Fink::Finally'; }

# bad args
{
	eval { Fink::Finally->new };
	ok($@, 'bad args - no args');
	eval { Fink::Finally->new('not code') };
	ok($@, 'bad args - not a code ref');
}

# explicit cleanup
{
	my $x = 0;
	my $finally = Fink::Finally->new(sub { $x++ });
	$finally->run;
	is($x, 1, 'explicit cleanup');
}

# automatic cleanup
{
	my $x = 0;
	{
		my $finally = Fink::Finally->new(sub { $x++ });
	}
	is($x, 1, 'automatic cleanup');
}

# exceptional cleanup
{
	my $x = 0;
	eval {
		my $finally = Fink::Finally->new(sub { $x++ });
		die "exception!";
	};
	ok($@, 'exceptional cleanup - exception thrown');
	is($x, 1, 'exceptional cleanup - executed');
}

# run once
{
	my $x = 0;
	{
		my $finally = Fink::Finally->new(sub { $x++ });
		$finally->run;
		$finally->run;
		# out of scope => automatic run
	}
	is($x, 1, 'run once');
}

# cleanup on exit
{
	my $script = <<'SCRIPT';
use Fink::Finally;
my $finally = Fink::Finally->new(sub { print "cleanup\n" });
exit 0;
SCRIPT
	my ($fh, $fname) = tempfile("capture.XXXX");
	print $fh $script;
	close $fh;
	
	local $ENV{PERL5LIB} = join(':', @INC);
	open my $subproc, '-|', "perl $fname" or die "Can't open subproc: $!";
	my $out = join('', <$subproc>);
	close $subproc;
	
	is($out, "cleanup\n", "cleanup on exit");
	unlink $fname;
}

# cancellation
{
	my $x = 0;
	{
		my $fin = Fink::Finally->new(sub { $x++ });
		$fin->cancel;
		$fin->run;
	} # out of scope
	is($x, 0, 'cancellation');
}

# fork doesn't run in subproc
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
			ok(-f $file, "fork doesn't run in subproc");
		}
	}
}

	
