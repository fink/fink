#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

require_ok('Fink::Services');
can_ok('Fink::Services','prepare_script');  # not exported

my( @script, $script, $result );
my $scriptref = \$script;

$script = 'test1';
eval { $result = &Fink::Services::prepare_script($script) };
isnt($@, '', 'fails for non-ref');

$script = undef;
$result = &Fink::Services::prepare_script($scriptref);
isnt(defined $script, 'undef returns undef');

$script = '';
$result = &Fink::Services::prepare_script($scriptref);
isnt(defined $script, 'blank returns undef');

$script = 'test1';
$result = &Fink::Services::prepare_script($scriptref);
cmp_ok($result, '==', 0, 'simple command returns 0');
is($script, 'test1', 'simple command is unchanged');

$script = "test1\n";
$result = &Fink::Services::prepare_script($scriptref);
is($$scriptref, 'test1', 'removes trailing newline');
cmp_ok($scriptref, 'eq', \$script, 'chomps; changes original scalar');

$script = "#!/bin/sh\ntest1";
$result = &Fink::Services::prepare_script($scriptref);
cmp_ok($result, '==', 1, 'magic-char script returns 1');
like($script, '/\/tmp/', 'magic-char script returns scriptname');
like($script, '/^\//', 'scriptname is absolute path');
ok(-f $script, 'scriptname file exists');
open SCRIPT, "<$script";
@script = <SCRIPT>;
close SCRIPT;
unlink $script;
is($script[-1], "test1\n", 'trailing newline added');

$script = "   #!/bin/sh\ntest\\\n test1\n\n# a\nfoo\n";
$result = &Fink::Services::prepare_script($scriptref);
cmp_ok($result, '==', 1, 'whitespace before magic-char is okay');
open SCRIPT, "<$script";
@script = <SCRIPT>;
close SCRIPT;
unlink $script;
cmp_ok(scalar @script, '==', 6, 'read all lines');
is($script[0], "#!/bin/sh\n", 'whitespace befor magic-char is removed');
is($script[1], "test\\\n", 'trailing slash does not cause rejoining');
is($script[2], " test1\n", 'leading whitespace in other lines remains');
is($script[3], "\n", 'blank lines remain');
is($script[4], "# a\n", 'comments remain');
is($script[5], "foo\n", 'no chomp');

$script = " testing\n1, 2, 3\n   over\nand out  \ncharlie\n";
$result = &Fink::Services::prepare_script($scriptref);
is($script, "testing\n1, 2, 3\nover\nand out  \ncharlie", 'leading whitespace is removed');

$script = "\nhi\n  \n\nwocka\nwocka2\n\n  wiff\n\n\n    \n\n\n";
$result = &Fink::Services::prepare_script($scriptref);
is($script, "hi\nwocka\nwocka2\nwiff", 'blanks are removed');

$script = "Hello\nI am # Sam\n#Sam I am\n  # leave now\nwoof";
$result = &Fink::Services::prepare_script($scriptref);
is($script, "Hello\nI am # Sam\nwoof", 'comments are removed');

$script = "I hate\\\nwriting tests";
$result = &Fink::Services::prepare_script($scriptref);
is($script, 'I hate writing tests', 'simple continuation works');

$script = "Tests    \\   \n       are important";
$result = &Fink::Services::prepare_script($scriptref);
is($script, 'Tests are important', 'continuation handles excess whitespace');

$script = "Windows C:\\DOESNT.TST enough\nbummer";
$result = &Fink::Services::prepare_script($scriptref);
is($script, "Windows C:\\DOESNT.TST enough\nbummer", 'internal backslashes ignored');

$script = "That's\nbad news\\\nfor\\\nversion x.0 \\\nusers";
$result = &Fink::Services::prepare_script($scriptref);
is($script, "That's\nbad news for version x.0 users", 'multiple-rejoin works');

$script = "Maybe\\\n# woof!";
$result = &Fink::Services::prepare_script($scriptref);
is($script, 'Maybe # woof!', 'rejoin happens before comment removal (simple)');

$script = "Maybe\\\n# woof!\\\nnot?";
$result = &Fink::Services::prepare_script($scriptref);
is($script, 'Maybe # woof! not?', 'rejoin happens before comment removal (multiple)');

$script = "Maybe\n# woof!\\\nso.";
$result = &Fink::Services::prepare_script($scriptref);
is($script, 'Maybe', 'rejoined comment is fully removed');

$script = 'test1\\';
eval { $result = &Fink::Services::prepare_script($script) };
isnt($@, '', 'fails for trailing backslash');
