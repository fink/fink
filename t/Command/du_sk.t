#!/usr/bin/perl -w

use Test::More tests => 6;
use Fink::Command qw(du_sk);

open FILE, '>foo';
print FILE "Some stuff\nAnd things\n";
close FILE;
my $smallsize = du_sk('foo');
# Check reasonable block sizes
ok( $smallsize > 0  && $smallsize <= 8,
	"can get a regular size" );											# 1

symlink 'foo', 'bar';
is( du_sk('bar'), 0, "gets zero for symlink" );							# 2
unlink qw(foo bar);

mkdir 'foo';
chmod 0000, 'foo';
SKIP: {
	skip "can't test permission errors as root", 1 if -r 'foo';
	like( du_sk('foo'), qr/^Error: .* \b cd \b/ix, "errors appropriately");	# 3
}
chmod 0700, 'foo';
rmdir 'foo';

# User better not touch anything for a moment
(my $dirsize = `/usr/bin/du -sk .`) =~ s/\D.*$//s;
is( du_sk('.'), $dirsize, "agrees with du");							# 4

# If block size is less than 1K, then rounding effects can cause size of
# $dir twice to not equal twice size of $dir.
my @ok_sizes = (2 * $dirsize);
push @ok_sizes, 2 * $dirsize - 1 if $smallsize == 1;
my $listsize = du_sk(qw(. .));
ok( (grep { $_ == $listsize } @ok_sizes) , "works on lists");				# 5


is( du_sk(), 0, "works with no arguments");								# 6
