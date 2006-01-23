#!/usr/bin/perl

$|++;

use strict;
use Data::Dumper;

use Cwd;
use Geo::IP;
use HTML::TreeBuilder;
use LWP::UserAgent;
use WWW::Mechanize;
use URI;
use vars qw($VERSION %keys %reverse_keys %files $debug $response);

use vars qw($APACHE $CPAN $CTAN $DEBIAN $GIMP $GNOME $GNU);

$APACHE = 1;
$CPAN   = 1;
$CTAN   = 1;
$DEBIAN = 1;
$GIMP   = 1;
$GNOME  = 1;
$GNU    = 1;

$debug = 0;
$VERSION = ( qw$Revision$ )[-1];

my $mech = WWW::Mechanize->new( agent => "Fink Mirror Query $VERSION" );
my $geo  = Geo::IP->new(GEOIP_STANDARD);
my $ua   = LWP::UserAgent->new();

$ua->timeout(30);

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

if ($APACHE) {
	print "- getting apache mirror list:\n";
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
					print "\t", $link->attr('href'), ": ok\n";
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
}

### CPAN

if ($CPAN) {
	print "- getting CPAN mirror list:\n";
	$response = $mech->get( 'http://www.cpan.org/SITES.html' );
	if ($response->is_success) {
		$files{'cpan'}->{'url'} = 'http://www.cpan.org/SITES.html';
		$files{'cpan'}->{'primary'} = 'ftp://ftp.cpan.org/pub/CPAN';
		my $mirrors;
		my @links = ($files{'cpan'}->{'primary'});
	
		my $tree = HTML::TreeBuilder->new();
		$tree->parse($response->content);
		my $hostlist = $tree->look_down(
			'_tag' => 'a',
			sub {
				$_[0]->attr('name') =~ /^hostlist$/
			},
		);
	
		for my $link ($tree->look_down('_tag' => 'a')) {
			last if ($link->attr('name') =~ /^rsync$/i);
			next if ($link->attr('href') =~ /^\#/);
			next if ($link->attr('href') eq "");
			print "\t", $link->attr('href'), ": ok\n";
			push(@links, $link->attr('href'));
		}
	
		for my $link (@links) {
			my ($code, $uri) = get_code($link);
			push(@{$mirrors->{$code}}, $uri);
		}
	
		$files{'cpan'}->{'mirrors'} = $mirrors;
	} else {
		warn "unable to get cpan ftp list\n";
	}
	print "done\n";
}

### CTAN

if ($CTAN) {
	print "- getting CTAN mirror list:\n";
	$response = $mech->get( 'ftp://tug.ctan.org/tex-archive/README.mirrors' );
	if ($response->is_success) {
		$files{'ctan'}->{'url'} = 'ftp://tug.ctan.org/tex-archive/README.mirrors';
		$files{'ctan'}->{'primary'} = 'ftp://tug.ctan.org/tex-archive';
		my $mirrors;
		my @links = ($files{'ctan'}->{'primary'});
	
		for my $line (split(/\r?\n/, $response->content)) {
			if ($line =~ /^\s+(\S+)\s+\(.*?\)\s+(\S+)\s*$/) {
				my $url = $1 . $2;
				# the mirror list doesn't specify whether they work with FTP or HTTP
				for my $protocol ('ftp', 'http') {
					my $url = $protocol . '://' . $url;
					print "\t", $url, ": ";
					if ($ua->get($url . '/CTAN.sites')->is_success) {
						print "ok\n";
						push(@links, $url);
					} else {
						print "failed\n";
					}
				}
			}
		}
	
		for my $link (@links) {
			my ($code, $uri) = get_code($link);
			push(@{$mirrors->{$code}}, $uri);
		}
	
		$files{'ctan'}->{'mirrors'} = $mirrors;
	} else {
		warn "unable to get ctan ftp list\n";
	}
}

### Debian

if ($DEBIAN) {
	print "- getting debian mirror list:\n";
	$response = $mech->get( 'http://www.debian.org/mirror/list' );
	if ($response->is_success) {
		$files{'debian'}->{'url'} = 'http://www.debian.org/mirror/list';
		$files{'debian'}->{'primary'} = 'ftp://ftp.debian.org/debian';
		my $mirrors;
		my @links = ($files{'debian'}->{'primary'});
	
		my $tree = HTML::TreeBuilder->new();
		$tree->parse($response->content);
		my $table = $tree->look_down(
			'_tag' => 'th',
			sub { $_[0]->as_text eq "Country" },
		)->look_up('_tag' => 'table');
		if ($table) {
			for my $link ($table->look_down('_tag' => 'a')) {
				if ($link) {
					print "\t", $link->attr('href'), ": ok\n";
					push(@links, $link->attr('href'));
				}
			}
		}
	
		for my $link (@links) {
			my ($code, $uri) = get_code($link);
			push(@{$mirrors->{$code}}, $uri);
		}
	
		$files{'debian'}->{'mirrors'} = $mirrors;
	} else {
		warn "unable to get debian ftp list\n";
	}
	print "done\n";
}

### GIMP

if ($GIMP) {
	print "- getting gimp mirror list:\n";
	$response = $mech->get( 'http://www.gimp.org/downloads' );
	if ($response->is_success) {
		$files{'gimp'}->{'url'} = 'http://www.gimp.org/downloads';
		$files{'gimp'}->{'primary'} = 'ftp://ftp.gimp.org/pub/gimp';
		my $mirrors;
		my @links = ($files{'gimp'}->{'primary'});
	
		my $tree = HTML::TreeBuilder->new();
		$tree->parse($response->content);
		my $dl = $tree->look_down(
			'_tag' => 'dl',
			sub { $_[0]->attr('class') eq "download-mirror" },
		);
		if ($dl) {
			GIMPLINKS: for my $link ($dl->look_down('_tag' => 'a')) {
				if ($link) {
					next if ($link->look_up('_tag' => 'dd')->as_text =~ /WAIX/);
					my $url = $link->attr('href');
					next if ($url =~ m#^rsync://#);
					$url = $url . '/' unless ($url =~ m#/$#);
					for my $num (0..2) {
						my $tempurl = $url . 'gimp/' x $num;
						print "\t", $tempurl, ": ";
						if ($ua->get($tempurl . 'README')->content =~ /This is the root directory of the official GIMP/) {
							print "ok\n";
							push(@links, $tempurl);
							next GIMPLINKS;
						} else {
							print "failed\n";
						}
					}
				}
			}
		}
	
		for my $link (@links) {
			my ($code, $uri) = get_code($link);
			push(@{$mirrors->{$code}}, $uri);
		}
	
		$files{'gimp'}->{'mirrors'} = $mirrors;
	} else {
		warn "unable to get gimp ftp list\n";
	}
}

### Gnome

if ($GNOME) {
	print "- getting gnome mirror list:\n";
	$response = $mech->get( 'http://ftp.gnome.org/pub/GNOME/MIRRORS.html' );
	if ($response->is_success) {
		$files{'gnome'}->{'url'} = 'http://ftp.gnome.org/pub/GNOME/MIRRORS.html';
		$files{'gnome'}->{'primary'} = 'ftp://ftp.gnome.org/pub/GNOME';
		my $mirrors;
		my @links = ($files{'gnome'}->{'primary'});
	
		for my $link ($mech->links) {
			my $url = $link->url;
			next if ($url =~ /^mailto/);
			$url =~ s#/$##;
			print "\t", $url, ": ";
			if ($ua->get($url . '/MIRRORS')->content =~ /GNOME FTP Sites/gs) {
				print "ok\n";
				push(@links, $url);
			} else {
				print "failed\n";
			}
		}
	
		for my $link (@links) {
			my ($code, $uri) = get_code($link);
			push(@{$mirrors->{$code}}, $uri);
		}
	
		$files{'gnome'}->{'mirrors'} = $mirrors;
	} else {
		warn "unable to get gnome ftp list\n";
	}
}

### GNU

if ($GNU) {
	print "- getting GNU mirror list:\n";
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
					my $url = $link->attr('href');
					print "\t", $url, ": ";
					if ($ua->get($url . '/=README')->content =~ /This directory contains programs/gs) {
						print "ok\n";
						push(@links, $url);
					} else {
						print "failed\n";
					}
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
	print "done\n";
}

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
	if ($uri->host =~ /ftp\.(\D\D)\.(uu\.net|debian\.org)/) {
		$code = uc($1);
	}
	$code = 'UK' if ($code eq 'GB');
	$code = 'RQ' if ($code eq 'PR');
	$debug && warn "code = $code, url = ", $uri->canonical, ", mapping = ", $reverse_keys{"$code"}, "\n";
	if (not exists $reverse_keys{"$code"}) {
		warn "no such entry for $code!\n";
	}
	my $canonical = $uri->canonical->as_string;
	$canonical =~ s,/$,,;
	return ($reverse_keys{"$code"}, $canonical);
}
