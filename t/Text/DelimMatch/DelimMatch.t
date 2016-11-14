# this file taken from DelimMatch-1.06/test.pl on CPAN.
# converted to Fink namespace by The Fink Project.

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..47\n"; }
END {print "not ok 1\n" unless $loaded;}
use Fink::Text::DelimMatch;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

$mc = new Fink::Text::DelimMatch '"';

# test: simple delimited text, fast
&test (2, 'pre "match" post', 'pre ', '"match"', ' post');
&test (3, '"match" post', '', '"match"', ' post');
&test (4, 'pre "match"', 'pre ', '"match"', '');
&test (5, 'no match" post');
&test (6, 'pre "no match');

# test: simple delimited text, slow
$mc->slow(1);
&test (7, 'pre "match" post', 'pre ', '"match"', ' post');
&test (8, '"match" post', '', '"match"', ' post');
&test (9, 'pre "match"', 'pre ', '"match"', '');
&test (10, 'no match" post');
&test (11, 'pre "no match');

# test: delimited text, fast
$mc->slow(0);
$mc->delim("\\(", "\\)");

&test (12, 'pre (m(a(t)c)h) post', 'pre ', '(m(a(t)c)h)', ' post');
&test (13, '(m(a(t)c)h) post', '', '(m(a(t)c)h)', ' post');
&test (14, 'pre (m(a(t)c)h)', 'pre ', '(m(a(t)c)h)', '');
&test (15, '(no match post');
&test (16, 'no match) post');
&test (17, 'pre (no match');
&test (18, 'pre no match)');

# test: delimited text, slow
$mc->slow(1);
&test (19, 'pre (m(a(t)c)h) post', 'pre ', '(m(a(t)c)h)', ' post');
&test (20, '(m(a(t)c)h) post', '', '(m(a(t)c)h)', ' post');
&test (21, 'pre (m(a(t)c)h)', 'pre ', '(m(a(t)c)h)', '');
&test (22, '(no match post');
&test (23, 'no match) post');
&test (24, 'pre (no match');
&test (25, 'pre no match)');

# test: delimited text, skipping quotes
$mc->slow(0);
$mc->quote('"');

&test (26, 'pre "(no match)" "(no" "match)" (match) post', 
       'pre "(no match)" "(no" "match)" ', '(match)', ' post');
&test (27, '"(no match)" pre (match) post', 
       '"(no match)" pre ', '(match)', ' post');

# test: delimited text, complex quotes
$mc->quote();
$mc->quote('<!--', '-->');
&test (28, 'pre <!-- ( --> (match) post', 
       'pre <!-- ( --> ', '(match)', ' post');

# test: delimited text, escaped characters
$mc->quote();
$mc->escape('\\');
&test (29, 'pre \(no match) (match) post',
       'pre \(no match) ', '(match)', ' post');

&test (30, 'pre (match \) this) post',
       'pre ', '(match \) this)', ' post');

# test: delimited text, doubled quotes
$mc->quote ('"');
$mc->escape();
&test (31, 'pre "(no match)" (no match)" (match) post',
       'pre "(no match)" ', '(no match)', '" (match) post');

$mc->double_escape ('"');
&test (32, 'pre "(no match)"" (no match)" (match) post',
       'pre "(no match)"" (no match)" ', '(match)', ' post');

# test: a little of everything

$mc->escape('[;\\]');
&test (33, ';(no \(match)\) \(no match) \"(m(a\)tc)h)',
       ';(no \(match)\) \(no match) \"', '(m(a\)tc)h)', '');

&test (34, '"(no match) "" (no match) \""\((m"a)t"ch)',
       '"(no match) "" (no match) \""\(', '(m"a)t"ch)', '');

# test: repeated matching

&test (35, 'pre (match) (match2) post',
       'pre ', '(match)', ' (match2) post');

&test (36, undef,
       ' ', '(match2)', ' post');

# test: case sensitivity

$mc->delim('S', 'E');

&test (37, "pre SmastechE post", "pre ", "SmastechE", " post");
&test (38, "pre smaStEche post", "pre ", "smaStEche", " post");

$mc->case_sensitive(1);

&test (39, "snomatche SmastechE post", "snomatche ", "SmastechE", " post");
&test (40, "snomatche smaStEche post", "snomatche sma", "StE", "che post");

# test: backward compatability functions

if (&Fink::Text::DelimMatch::nested_match ("pre (match) ", "\\(", "\\)") eq "(match)") {
    print "ok 41\n";
} else {
    print "not ok 41\n";
}

if (&Fink::Text::DelimMatch::skip_nested_match (" (match)post", "\\(", "\\)") eq "post") {
    print "ok 42\n";
} else {
    print "not ok 42\n";
}

# test: turning off repeated matching

$mc->keep(0);

$mc->delim("\\(", "\\)");

&test (43, 'pre (match) (match2) post',
       'pre ', '(match)', ' (match2) post');

&test (44, undef);

# test: strip delimiters

$mc = new Fink::Text::DelimMatch '\(', '\)';
$mc->returndelim(1);

$match = $mc->match("test ((this is) a test) so there");

if ($match eq '((this is) a test)') {
    print "ok 45\n";
} else {
    print "not ok 45\n";
}

$mc->returndelim(0);

$match = $mc->match("test ((this is) a test) so there");

if ($match eq '(this is) a test') {
    print "ok 46\n";
} else {
    print "not ok 46 ($match)\n";
}

# test: multi-line matching with delimiter stripping

$match = $mc->match("test ((this is)\na test) so there");

if ($match eq "(this is)\na test") {
    print "ok 47\n";
} else {
    print "not ok 47 ($match)\n";
}

exit;

sub test {
    my ($tnum, $string, $okpre, $okmatch, $okpost) = @_;
    my ($pre, $match, $post) = $mc->match($string);

    # check this first, to avoid -w errors
    if (!defined($match) && !defined($okmatch)) {
	print "ok $tnum\n";
	return;
    }

#    print "1: ", defined($pre), " ";
#    print "2: ", defined($okpre), " ";
#    print "3: ", defined($match), "($match) ";
#    print "4: ", defined($okmatch), " ";
#    print "5: ", defined($post), " ";
#    print "6: ", defined($okpost), "\n";

    if (($pre ne $okpre)
	|| ($match ne $okmatch)
	|| ($post ne $okpost)) {
	print "not ok $tnum\n";
	print "\t\"$pre\" =?= \"$okpre\"\n";
	print "\t\"$match\" =?= \"$okmatch\"\n";
	print "\t\"$post\" =?= \"$okpost\"\n";
	$mc->dump();
	exit 1;
    } else {
	print "ok $tnum\n";
    }
}

