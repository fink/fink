
use strict;
use Test::More tests=>2;
use Tie::IxHash;

my $o = tie my %h, 'Tie::IxHash';

$h{a} = 1; $h{b} = 2; $h{c} = 3; $h{d} = 4; $h{e} = 5;

while (my ($k) = each %h) { 
  if ($k =~ /b|d|e/) { delete $h{$k}; } 
}

is(scalar(keys(%h)), 2) or diag explain(\%h);
is(join(',',keys(%h)), 'a,c') or diag explain(\%h);
