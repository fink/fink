#!../perl -w
use Tie::IxHash;

my $TNUM = 0;
print "1..26\n";

sub T { print $_[0] ? "ok " : "not ok ", ++$TNUM, "\n" }
my %bar;
my $ixh = tie (%bar, 'Tie::IxHash', 'a' => 1, 'q' => 2, 'm' => 'X', 'n' => 'Y');
#$ixh = Tie::IxHash->new('a' => 1, 'q' => 2, 'm' => 'X', n => 'Y');
$ixh->Push(e => 5, f => 6);
T 'a|1|q|2|m|X|n|Y|e|5|f|6' eq join('|', %bar);
$ixh->Delete('e', 'a');
T 'q|2|m|X|n|Y|f|6' eq join '|', %bar;
T 'q|m|n|f' eq join '|', $ixh->Keys;
T '2|X|Y|6' eq join '|', $ixh->Values;
T 'm|n|f' eq join '|', $ixh->Keys(1, 2, 3);
T 'X|Y|6' eq join '|', $ixh->Values(1, 2, 3);
$ixh->Replace(1, 9);
T 'q|2|m|9|n|Y|f|6' eq join '|', %bar;
$ixh->Replace(0, 8, 'f');
T 'f|8|m|9|n|Y' eq join '|', %bar;
T '2|1' eq join '|', $ixh->Indices('n', 'm');
$ixh->Push(z => 1);
$ixh->SortByValue;
T 'z|f|m|n' eq join '|', $ixh->Keys;
$ixh->SortByKey;
T 'f|m|n|z' eq join '|', $ixh->Keys;

T 'm' eq $ixh->Keys(1);
T 'Y' eq $ixh->Values(2);
T 3 == $ixh->Indices('z');

%bar = ('a' => 9, 'c' => 6, 'z' => 7, 'f' => 1);
delete $bar{'z'};
$bar{'a'} = 10;
T 'a|10|c|6|f|1' eq join '|', %bar;
T 'a|c|f' eq join '|', keys %bar;
T '10|6|1' eq join '|', values %bar;
$ixh->Reorder(sort { $bar{$a} <=> $bar{$b} } keys %bar);
T 'f|c|a' eq join '|', keys %bar;
$ixh->Reorder('c', 'a', 'z');
T 'c|6|a|10' eq join '|', %bar;

@tmp = $ixh->Splice(0, 3, 'z' => 7, 'm' => 4); 
T 'c|6|a|10' eq join '|', @tmp;
T 'z|7|m|4' eq join '|', %bar;
$ixh->Push('m' => 8);
@tmp = $ixh->Pop;
T 'm|8' eq join '|', @tmp;
$ixh->Push('o' => 2, 'r' => 8);
T 'z|7|o|2|r|8' eq join '|', %bar;
$ixh->Pop;
T 'z|7|o|2' eq join '|', %bar;
$ixh->Splice($ixh->Length,0,$ixh->Pop);
T 'z|7|o|2' eq join '|', %bar;

$ixh->Clear;
T $ixh->Length == 0;

