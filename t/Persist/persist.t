#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

use Fink::Config;
use Data::Dumper;

=begin private

Hard to test explicitly:
	- DBI not present
	- DBD::SQLite not present
	- Disconnecting

=end private

=cut

use Fink::Persist;
use Fink::Persist::TableHash qw(:ALL);
use Fink::Persist::Base;

my $config = Fink::Config->new_with_path('basepath/etc/fink.conf');

### Test loading ###

my $dbfile = "Persist/testdb.sqlite";
unlink $dbfile;

my $dbh = getdbh($dbfile);
ok($dbh, "getdbh should return true");
cmp_ok($dbh, '==', getdbh($dbfile), "getdbh should cache results");


### Test hash ###

ok(!exists_id($dbh, "test", 2), "Item should not yet exist in DB");

my $h = Fink::Persist::TableHash->new($dbh, "test", 2);
ok($h, "TableHash creation should return true");

my $h2 = Fink::Persist::TableHash->new($dbh, "test");
ok($h2, "Automatic id determination should work");

ok(!exists $h->{int}, "Nothing in hash initially");
$h->{int} = 2;
$h->{str} = "foo";
$h->{arrayref} = [ 1, 2, 3 ];

ok(exists $h->{int}, "Exist should return true");
is($h->{int}, 2, "Integer should be stored");
is($h->{str}, "foo", "String should be stored");
ok(eq_array($h->{arrayref}, [ 1, 2, 3 ]), "Array ref should be stored");

delete $h->{int};
ok(!exists $h->{int}, "Deleted key no longer exists");

ok(eq_array([ sort keys %$h ], [ "arrayref", "str" ]),
	"Keys should reflect changes");


### Test writing ###

ok($dbh->commit, "Commit should work");

# Hack to allow reconnecting
my $newdb = "Persist/testdb2.sqlite";
rename $dbfile, $newdb or die "Couldn't move DB: $!";

my $dbh2 = getdbh($newdb);
ok($dbh2, "Reopen should return true");

ok(exists_id($dbh2, "test", 2), "Old items should still exist in DB");

my $h3 = Fink::Persist::TableHash->new($dbh2, "test", 2);
ok(eq_array($h->{arrayref}, [ 1, 2, 3 ]), "Values should still be in DB");


### Test getting all ###

my @res = all_with_props($dbh2, "iggy", { foo => "bar" });
is(scalar(@res), 0, "Should be no results with invalid table");

@res = all_with_props($dbh2, "test", { str => "bar" });
is(scalar(@res), 0, "Should be no results");

@res = all_with_props($dbh2, "test", { str => "foo" });
is(scalar(@res), 1, "One result should be present");
is((tied %{$res[0]})->id, 2, "Result should be correct");

@res = Fink::Persist::TableHash::all($dbh2, "test");
is(scalar(@res), 2, "All items should be present");


### Test complex references ###

push @{$h3->{arrayref}}, 4;
ok(eq_array($h3->{arrayref}, [ 1, 2, 3, 4 ]),
	"Values should be updated after push");

$h3->{arrayref}[0] = 5;
ok(eq_array($h3->{arrayref}, [ 5, 2, 3, 4 ]),
	"Values should be updated after store");


my %complex = (foo => 1, bar => 2, both => [1, 2], noprop => [3, 4]);
$h3->{complex} = \%complex;

$complex{bar} = 3;
delete $complex{foo};
$complex{both} = [ 3 ];
$complex{noprop}[0] = 1;

ok(eq_hash($h3->{complex}, {bar => 3, both => [3], noprop => [3, 4]}),
	"Some values should be updated after store");

my $h4 = Fink::Persist::TableHash->new($dbh2, "test");
$h4->{thref} = $h3;
is($h4->{thref}{str}, "foo", "TableHashes can be stored inside each other");


### Test objects ###

my $obj1 = Fink::Persist::Base->new();
ok($obj1, "Object creation works");

$obj1->set_param(iggy => "Helen");
is($obj1->param("iggy"), "Helen", "Object methods store correctly");

my $obj2 = Fink::Persist::Base->new();
$obj2->set_param(foo => [1, 2, 3]);
ok(eq_array($obj2->param("foo"), [1, 2, 3]), "Complex storage works");

push @{$obj2->param("foo")}, 4;
ok(eq_array($obj2->param("foo"), [1, 2, 3, 4]), "Complex changes propagate");


$obj2->set_param(obj => $obj1);
$obj2->param("obj")->set_param(test => "ok");
is($obj1->param("test"), "ok", "Objects properly stored within objects");


my $obj3 = Fink::Persist::Base->new_from_properties({
	name => "good",	foo => "Dave",	bar => "John",	iggy => "Helen",
	_ignore => "bad"
});
is($obj3->param("foo"), "Dave", "Construction from properties works");
ok(!$obj3->has_param("_ignore"), "Right params are ignored");


my @sel = Fink::Persist::Base->select_by_params();
ok(scalar(@sel) == 3, "Selection with no params works");

@sel = Fink::Persist::Base->select_by_params(iggy => "Helen");
ok(scalar(@sel) == 2, "Selection by one param works");

@sel = Fink::Persist::Base->select_by_params(iggy => "Helen", foo => "Dave",
	bar => "John");
ok(scalar(@sel) == 1, "Selection by multi params gets right count of results");
is($sel[0]->param("name"), "good", "Selected objects work");


$obj1->set_param(foo => "Chris");
$obj2->set_param(compobj => [ $obj1, $obj3 ]);
ok(eq_array([ map { $_->param("foo") } @{$obj2->param("compobj")} ],
	[ "Chris", "Dave" ]), "Objects within complex works");

