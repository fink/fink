#!/usr/local/bin/bin/perl -w
 
use Fink::Tie::Watch;
use vars qw/$watch/;

print "1..30\n";

my $aa = 1;
$watch = new Fink::Tie::Watch(-variable => \$aa);
$aa = 3;			# test scalar STORE
print $aa == 3 ? "ok 1\n" : "not ok \n"; # test scalar FETCH
$watch->Unwatch;
print $aa == 3 ? "ok 2\n" : "not ok 2\n"; # test -shadow

my %aa = (1,11,2,22);
$watch = new Fink::Tie::Watch(-variable => \%aa);
$aa{3} = 33;			# test hash STORE
print $aa{3} == 33 ? "ok 3\n" : "not ok 3\n"; # test hash FETCH
$watch->Unwatch;
print $aa{3} == 33 ? "ok 4\n" : "not ok 4\n"; # test -shadow
$watch = new Fink::Tie::Watch(-variable => \%aa);
print exists $aa{3} ? "ok 5\n" : "not ok 5\n"; # test hash EXISTS
$d = delete $aa{3};
print exists $aa{3} ? "not ok 6\n" : "ok 6\n"; # test hash DELETE
print $d == 33 ? "ok 7\n" : "not ok 7\n";
$aa{3} = 333; $aa{4} = 444; $aa{5} = 555;
while ( ($key, $val) = each %aa) {
    last if $key == 3;
}
print $val == 333 ? "ok 8\n" : "not ok 8\n"; # test HASH FIRSTKEY
for $k ( sort keys %aa ) {
    $last_val = $aa{$k};
}
print $last_val == 555 ? "ok 9\n" : "not ok 9\n"; # test hash NEXTKEY
($key, $val) = each %aa;
# dumb test
print $val == $val ? "ok 10\n" : "not ok 10\n";
print scalar(keys %aa) == 5 ? "ok 11\n" : "not ok 11\n";
@aa=();
print $#aa == -1 ? "ok 12\n" : "not ok 12\n"; # test hash CLEAR

my @aa = (1,2);
$watch = new Fink::Tie::Watch(-variable => \@aa);
$aa[2] = 3;			# test array STORE
print scalar(@aa) == 3 ? "ok 13\n" : "not ok 13\n"; # test array FETCHSIZE
print $#aa == 2 ? "ok 14\n" : "not ok 14\n"; # test array FETCHSIZE
print $aa[2] == 3 ? "ok 15\n" : "not ok 15\n"; # test array FETCH
$watch->Unwatch;
print $aa[2] == 3 ? "ok 16\n" : "not ok 16\n"; # test -shadow
$watch = new Fink::Tie::Watch(-variable => \@aa);
push @aa, ('frog', 'cow');	# test array PUSH
$#aa = 5;			# extend, fill with 1 undef
my $pop = pop @aa;		# get undef
print defined($pop) ? "not ok 17\n" : "ok 17\n";
$pop = pop @aa;			# should be 'cow'
print $pop eq 'cow' ? "ok 18\n" : "not ok 18\n"; # test array POP
unshift @aa, (-2, -1, 0);
print scalar(@aa) == 7 ? "ok 19\n" : "not ok 19\n"; # test array UNSHIFT
my $shift = shift @aa;
print $shift == -2 ? "ok 20\n" : "not ok 20\n";	# test array SHIFT
@splice = splice @aa, 1, 1, (-0.5, 0, +0.5);
print $splice[0] == 0 ? "ok 21\n" : "not ok 21\n"; # test array SPLICE
@should_be = (-1, -0.5, 0, 0.5, 1, 2, 3, 'frog');
$ok = 1;
for($i = 0; $i <= $#aa; $i++) {
    next if $aa[$i] eq $should_be[$i];
    $ok = 0;
}
print $ok ? "ok 22\n" : "not ok 22\n";
@splice = splice @aa, 2,2;
$ok = ($splice[0] == 0 and $splice[1] == 0.5);
print $ok ? "ok 23\n" : "not ok 23\n";
@splice = splice @aa, 4,1,(qw/a b c/);
$ok = ($aa[3] == 2 and join('',@aa[4..$#aa]) eq 'abcfrog');
print $ok ? "ok 24\n" : "not ok 24\n";
print $splice[0] == 3 ? "ok 25\n" : "not ok 25\n";
@splice = splice @aa, 5;
print join('',@splice) eq 'bcfrog' ? "ok 26\n" : "not ok 26\n";
%aa = ();
print scalar(keys %aa) == 0 ? "ok 27\n" : "not ok 27\n"; # test array CLEAR
$watch->Unwatch;
print defined($watch) ? "not ok 28\n" : "ok 28\n";

$aa = \[1];
$watch = new Fink::Tie::Watch(-variable => \$aa);
$$aa->[0] = 3;			# test scalar STORE
print $$aa->[0] == 3 ? "ok 29\n" : "not ok 29\n"; # test scalar FETCH
$watch->Unwatch;
print $$aa->[0] == 3 ? "ok 30\n" : "not ok 30\n"; # test -shadow
