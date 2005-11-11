#!/usr/bin/perl
use warnings;
use strict;

use Test::More 'no_plan';
use Data::Dumper;

BEGIN {
	use_ok( 'Fink::Services', qw(spec2struct spec2string) );
}

# Pairs of valid input and result, which apply to both methods
my @dual = (
	# Plain 'ol package specs
	'foo'		=> { package => 'foo'		},
	'gtk+'		=> { package => 'gtk+'		},
	'quitelongnamedontyouthink'	=> { package => 'quitelongnamedontyouthink'	},
	'9-'		=> { package => '9-'		},
	
	# With version specs
	'foo (>= 1.2.3.14-1)'	=>
		{ package => 'foo', relation => '>=', version => '1.2.3.14-1'		},
	'gtk+ (= 45:2.7+test:2-1)'	=>
		{ package => 'gtk+', relation => '=', version => '45:2.7+test:2-1'	},
	'90 (<< 6)'	=>
		{ package => '90', relation => '<<', version => '6'					},
	'BLaH (<= 6-5-4-3-2-1)'	=>
		{ package => 'BLaH', relation => '<=', version => '6-5-4-3-2-1'		},
);

# Only valid for spec2struct
my @single = (
	# Whitespace weirdness
	' foo'				=> { package => 'foo'		},
	"\tgtk+\n \n"		=> { package => 'gtk+'		},
	'foo(>=1.0-1)'	=>
		{ package => 'foo', relation => '>=', version => '1.0-1'			},
	"     gtk+\n(=\t45:2.7+test:2-1 \t ) \n"	=>
		{ package => 'gtk+', relation => '=', version => '45:2.7+test:2-1'	},
);

# Bad input
my @bad2struct = (
	'a', 										# Too short
	'.foo', '+bar',								# Start with non alnum
	'foo#', 'inner space', '&blah', 'b%a*r',	# Bad chars
	'(foo)',									# Just confusing
	
	'oooh aaah (>> 1)',		# Bad package with spec
	'foo (1.0)',			# No relation
	'bar (<<)',				# No version
	'blah (> 2.0-1)',		# Invalid relation
	'(>= 2) iggy', 'baz (2 >>)',	# Out of order
	'foo (= 1 2)', 'bar (<= *1*)',	# Bad chars
	
	# TODO: Version problems not yet checked:
#	'foo (= 1-2:1)',	# Bad epoch
#	'bar (= 1:2-2:0)',	# Bad revision
#	'iggy (>> :.+-A5)',	# Totally messed up
);
my @bad2string = (
	{ },				# Nothing
	{ name => 'foo' },	# Not name, package
	{ package => 'foo', relation => '<<' },		# Relation w/o version
	{ package => 'foo', version => '1' },		# Version w/o relation
	
	# TODO: Validate content of fields?
);


sub prettify {
	return Data::Dumper->new([shift])->Terse(1)->Useqq(1)->Indent(0)
		->Sortkeys(1)->Dump();
}

sub test {
	my ($sub, $subname, $in, $out, $fail) = @_;
	my $pretty = prettify($in);
	my $result;
	eval { $result = &$sub($in) };
	if ($@) {
		if (!$fail) {
			fail("$subname incorrectly threw exception '$@' on $pretty");
		} elsif ($@ !~ /^Fink::Services:/) {
			fail("$subname threw unrecognized exception '$@' on $pretty");
		} else {
			pass("$subname correctly threw exception on $pretty");
		}
	} else {
		if ($fail) {
			my $pout = prettify($out);
			fail("$subname should have thrown exception on $pretty, instead "
				. "got $pout");
		} else {
			is_deeply($result, $out, "$subname works on $pretty");
		}
	}
}

sub test_spec2struct {
	test(\&spec2struct, 'spec2struct', @_);
}

sub test_spec2string {
	test(\&spec2string, 'spec2string', @_);
}

my ($string, $struct);
while (@dual) {
	($string, $struct, @dual) = @dual;
	test_spec2struct($string, $struct, 0);
	test_spec2string($struct, $string, 0);
}
while (@single) {
	($string, $struct, @single) = @single;
	test_spec2struct($string, $struct, 0);
}
foreach $string (@bad2struct) {
	test_spec2struct($string, '', 1);
}
foreach $struct (@bad2string) {
	test_spec2string($struct, '', 1);
}
