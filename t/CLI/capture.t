#!/usr/bin/perl
use warnings;
use strict;

use Test::More 'no_plan';
use File::Temp qw(tempfile);

BEGIN { use_ok 'Fink::CLI', 'capture'; }

# too many args
{
	my ($out, $err, $extra);
	eval 'capture { print "not ok\n" } \$out, \$err, \$extra';
	ok($@, "too many args - is an error");
	is($out, undef, "too many args - no output");
	is($err, undef, "too many args - no err output");
}

# basic stdout
{
	my $out;
	capture { print "not ok\n" } \$out;
	is($out, "not ok\n", "basic stdout");
}

# bad stdout arg
{
	my $out = "foo";
	eval { capture { print "not ok\n" } $out };
	ok($@, "bad stdout arg - is an error");
	is($out, "foo", "bad stdout arg - value remains the same");
}

# side effects
{
	my ($out, $side);
	capture { $side = "foo"; print "not ok\n" } \$out;
	is($side, "foo", "side effects");
}

# basic stderr
{
	my ($out, $err);
	capture { print "not ok\n"; print STDERR "not ok\n" } \$out, \$err;
	is($out, "not ok\n", "basic stderr - stdout captured");
	is($err, "not ok\n", "basic stderr - stderr captured");
}

# bad stderr arg
{
	my ($out, $err) = ("foo", "bar");
	eval { capture { print "not ok\n" } \$out, $err };
	ok($@, "bad stderr arg - is an error");
	is($out, "foo", "bad stderr arg - out value remains the same");
	is($err, "bar", "bad stderr arg - err value remains the same");
}

# nesting
{
	my ($out, $inner);
	capture {
		capture { print "inner" } \$inner;
		print "outer";
	} \$out;
	is($inner, "inner", "nesting - stdout intercepted");
	is($out, "outer", "nesting - stdout not propagated");
}

# stderr propagation. Wow, this is a hairy test!
{
	my ($out, $err, $inner);
	capture {
		capture { print "inner"; print STDERR "err" } \$inner;
		print "outer";
	} \$out, \$err;
	is($inner, "inner", "stderr propagation - stdout intercepted");
	is($out, "outer", "stderr propagation - stdout not propagated");
	is($err, "err", "stderr propagation - stderr propagated");
}		

# wantarray
{
	my ($out);
	my $scalar = capture { grep /foo/, qw(foo bar foobar) } \$out;
	is($scalar, 2, "wantarray - scalar return");
	my @array = capture { grep /foo/, qw(foo bar foobar) } \$out;
	is_deeply(\@array, [ qw(foo foobar) ], "wantarray - array return");
}

# die
{
	my ($out, $err);
	eval { capture {
		print "before";
		die "test\n";
		print STDERR "after";
	} \$out, \$err };
	is($@, "test\n", "die - exception thrown");
	is($out, "before", "die - retain prints from before");
	is($err, "", "die - no prints from after");
}

# subprocess
{
	my ($out, $err);
	capture {
		system("ls nonexistent");
		system("echo Hello World!");
	} \$out, \$err;
	is($out, "Hello World!\n", "subprocess - stdout");
	like($err, qr/No such file/i, "subprocess - stderr");
}

# perl output
{
	my ($out, $err, $x);
	capture {
		my $foo = "foo";
		$x = $foo + 3;
	} \$out, \$err;
	is($out, "", "perl output - stdout");
	like($err, qr/numeric/i, "perl output - stderr");
}

# merge
{
	my ($out);
	capture {
		print "foo";
		print STDERR "bar";
		print "iggy";
	} \$out, \$out;
	is($out, "foobariggy", "merge");
}

# clean failure
{
	# To test that STDOUT is still connected to real STDOUT after error,
	# must run in a subproc
	my $script = <<'SCRIPT';
use Fink::CLI qw(capture);
$err = "foo";
eval { capture { print "not ok\n" } \$out, $err };
print "sesame";
SCRIPT
	my ($fh, $fname) = tempfile(".capture.XXXX");
	print $fh $script;
	close $fh;
	
	local $ENV{PERL5LIB} = join(':', @INC);
	open my $subproc, '-|', "/usr/bin/perl $fname" or die "Can't open subproc: $!";
	my $out = join('', <$subproc>);
	close $subproc;
	
	is($out, "sesame", "clean failure - stdout remains ok");
	unlink $fname;
}
