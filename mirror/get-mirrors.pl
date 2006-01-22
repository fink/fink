#!/usr/bin/perl

$|++;

use strict;
use Data::Dumper;

use Cwd;
use Geo::IP;
use HTML::TreeBuilder;
use WWW::Mechanize;
use URI;
use vars qw($VERSION %keys %reverse_keys %files $debug $response);

$debug = 0;
$VERSION = ( qw$Revision$ )[-1];

my $mech = WWW::Mechanize->new( agent => "Fink Mirror Query $VERSION" );
my $geo  = Geo::IP->new(GEOIP_STANDARD);

$reverse_keys{'EU'} = 'eur';

open (KEYS, cwd . '/_keys') or die 'unable to open ' . cwd . "/_keys: $!\n";
while (<KEYS>) {
	next if (/^\s*$/);
	next if (/^\s*\#/);
	if (my ($key, $value) = $_ =~ /^\s*(\S+)\s*:\s*(.*?)\s*$/) {
		$keys{$key} = $value;
		if ($key =~ /^\S+\-(\S+)$/) {
			$reverse_keys{$1} = $key;
		}
	}
}
close (KEYS);

### Apache

$response = $mech->get( 'http://www.apache.org/mirrors' );
if ($response->is_success) {
	$files{'apache'}->{'url'} = 'http://www.apache.org/mirrors';
	$files{'apache'}->{'primary'} = 'http://www.apache.org/dist';
	my $mirrors;
	my @links = ($files{'apache'}->{'primary'});

	my $tree = HTML::TreeBuilder->new();
	$tree->parse($response->content);
	my $table = $tree->look_down(
		'_tag' => 'th',
		sub {
			$_[0]->as_text =~ /last stat/
		},
	)->look_up('_tag' => 'table');

	for my $row ($table->look_down('_tag' => 'tr')) {
		my @tds = $row->look_down('_tag' => 'td');
		if (@tds and defined $tds[4]) {
			my $link = $tds[0]->look_down('_tag' => 'a');
			if ($link and $tds[4]->as_text eq "ok") {
				push(@links, $link->attr('href'));
			}
		}
	}

	for my $link (@links) {
		my ($code, $uri) = get_code($link);
		push(@{$mirrors->{$code}}, $uri);
	}

	$files{'apache'}->{'mirrors'} = $mirrors;
} else {
	warn "unable to get apache ftp list\n";
}

### GNU

$response = $mech->get( 'http://www.gnu.org/order/ftp.html' );
if ($response->is_success) {
	$files{'gnu'}->{'url'} = 'http://www.gnu.org/order/ftp.html';
	$files{'gnu'}->{'primary'} = 'ftp://ftp.gnu.org/gnu';
	my $mirrors;
	my @links = ($files{'gnu'}->{'primary'});

	my $tree = HTML::TreeBuilder->new();
	$tree->parse($response->content);
	my $ul = $tree->look_down('_tag' => 'ul');
	if ($ul) {
		for my $link ($ul->look_down('_tag' => 'a')) {
			if ($link) {
				push(@links, $link->attr('href'));
			}
		}
	}

	for my $link (@links) {
		my ($code, $uri) = get_code($link);
		push(@{$mirrors->{$code}}, $uri);
	}

	$files{'gnu'}->{'mirrors'} = $mirrors;
} else {
	warn "unable to get GNU ftp list\n";
}

print Dumper(\%files), "\n";

for my $site (sort keys %files) {
	print "- writing $site... ";
	if (open (FILEOUT, ">$site.tmp")) {
		print FILEOUT "# Official mirror list: ", $files{$site}->{'url'}, "\n";
		print FILEOUT "Timestamp: ", timestamp(), "\n\n";
		print FILEOUT "Primary: ", $files{$site}->{'primary'}, "\n\n";
		for my $key (sort keys %{$files{$site}->{'mirrors'}}) {
			for my $link (@{$files{$site}->{'mirrors'}->{$key}}) {
				print FILEOUT $key, ": ", $link, "\n";
			}
		}
		close (FILEOUT);
		print "done\n";
		unlink("${site}");
		link("${site}.tmp", "${site}");
		unlink("${site}.tmp");
	} else {
		warn "unable to write to ${site}.tmp: $!\n";
	}
}

sub timestamp {
	my (undef, undef, undef, $day, $month, $year) = localtime();
	return sprintf('%04d-%02d-%02d', $year + 1900, $month + 1, $day);
}

sub get_code {
	my $link = shift;
	$link =~ s,ftp://ftp://,ftp://,;

	my $uri = URI->new($link);
	my $code = $geo->country_code_by_name($uri->host);
	if (not defined $code or $code =~ /^\s*$/) {
		$debug && warn "unknown code for " . $uri->host . "\n";
		if ($uri->host =~ /\.(\D\D)$/) {
			$code = uc($1);
			$debug && warn "found $code in hostname\n";
		} else {
			$code = 'US';
			$debug && warn "still couldn't figure it out, setting to US\n";
		}
	}
	if ($uri->host =~ /ftp\.(\D\D)\.uu\.net/) {
		$code = uc($1);
	}
	$code = 'UK' if ($code eq 'GB');
	$debug && warn "code = $code, url = ", $uri->canonical, ", mapping = ", $reverse_keys{"$code"}, "\n";
	if (not exists $reverse_keys{"$code"}) {
		warn "no such entry for $code!\n";
	}
	my $canonical = $uri->canonical->as_string;
	$canonical =~ s,/$,,;
	return ($reverse_keys{"$code"}, $canonical);
}
