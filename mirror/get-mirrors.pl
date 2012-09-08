#!/usr/bin/perl
#
# This program updates the various mirror lists by scraping various online
# mirror lists for data, then checking each mirror found this way for availability,
# as well as for its geographical location.
#
# To use this tool, you need to install the following Fink packages:
#  * uri-find-pm5100 
#  * www-mechanize-pm5100
#  * html-tree-pm5100
#  * geo-ip-pm5100
#
# TODO: Right now we test all mirrors sequentially, which can take a looong
#       time. We should try to parallelize this. An easy way for that would
#       be to run over two (or more) mirror lists in parallel.
#
# TODO: Apache has switched to using mirmon. There are mirmon sites available
#       for many of the other mirror lists we maintain. And a mirmon instance
#       lists the status of every mirror it knows about...
#       We could just rely on that status instead of doing slow checks ourselves.
#       And independently of this, we could unify several of the parsers by
#       a single mirmon parser.
#
# TODO: PostgreSQL analysis is broken; the website we used to use only lists redirect URLs now.

$|++;

use strict;
use Data::Dumper;

use Cwd;
use File::Slurp;
use File::Temp qw(mktemp);
use Geo::IP;
use HTML::TreeBuilder;
use LWP::UserAgent;
use Net::FTP;
use WWW::Mechanize;
use URI;
use URI::Escape;
use URI::Find;

use vars qw($VERSION %keys %reverse_keys $debug $response);

# map 'site name' to [ proc, URL of mirror list, primary mirror ]
my %mirror_sites = (
	'Apache'  => [ \&parse_apache, 'http://www.apache.org/mirrors/', 'http://www.apache.org/dist' ],
	'CPAN'    => [ \&parse_cpan, 'http://www.cpan.org/SITES.html', 'ftp://ftp.cpan.org/pub/CPAN' ],
	'CTAN'    => [ \&parse_ctan, 'ftp://tug.ctan.org/tex-archive/README.mirrors', 'ftp://tug.ctan.org/tex-archive' ],
	'Debian' => [ \&parse_debian, 'http://www.debian.org/mirror/list', 'ftp://ftp.debian.org/debian' ],
	'FreeBSD' => [ \&parse_freebsd, 'http://www.freebsd.org/doc/en_US.ISO8859-1/books/handbook/mirrors-ftp.html', 'ftp://ftp.FreeBSD.org/pub/FreeBSD/ports/distfiles' ],
	'Gimp' => [ \&parse_gimp, 'http://www.gimp.org/downloads', 'ftp://ftp.gimp.org/pub/gimp' ],
	'GNOME' => [ \&parse_gnome, 'http://ftp.gnome.org/pub/GNOME/MIRRORS', 'ftp://ftp.gnome.org/pub/GNOME' ],
	'GNU' => [ \&parse_gnu, 'http://www.gnu.org/prep/ftp.html', 'ftp://ftp.gnu.org/gnu' ],
	'KDE' => [ \&parse_kde, 'http://download.kde.org/mirrorstatus.html', 'ftp://ftp.kde.org/pub/kde' ],
	
	# FIXME: Format changed, they now only list redirect URls
#	'PostgreSQL' => [ \&parse_postgresql, 'http://wwwmaster.postgresql.org/download/mirrors-ftp?file=%2F', 'ftp://ftp.postgresql.org/pub' ],
	);

$debug = 0;
$VERSION = 1.00;

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

### Iterate over all sites

foreach my $mirror_name (sort keys %mirror_sites) {
	my $site = lc $mirror_name;
	my ($parse_sub, $mirror_list_url, $primary) = @{$mirror_sites{$mirror_name}};

	print "- getting $mirror_name mirror list:\n";
	# Try to load the mirror list
	$response = $mech->get( $mirror_list_url );
	if ($response->is_success) {
		my @links = ($primary);

		# Invoke the actual parsing subroutine.
		&$parse_sub($response, \@links);

		# Transform the output, filling the mirrors hash
		my $mirrors;
		for my $link (@links) {
			my ($code, $uri) = get_code($link);
			push(@{$mirrors->{$code}}, $uri) if (defined $code);
		}

		# Write everything to a file.
		print "- writing $site... ";
		if (open (FILEOUT, ">$site.tmp")) {
			print FILEOUT "# Official mirror list: ", $mirror_list_url, "\n";
			print FILEOUT "Timestamp: ", timestamp(), "\n\n";
			print FILEOUT "Primary: ", $primary, "\n\n";
			for my $key (sort keys %{$mirrors}) {
				for my $link (sort @{$mirrors->{$key}}) {
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

	} else {
		warn "unable to get $mirror_name mirror list\n";
	}

}


### Apache
sub parse_apache {
	my $response = shift;
	my $links = shift;

		my $tree = HTML::TreeBuilder->new();
		$tree->parse($response->decoded_content);
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
					my $url = $link->attr('href');
					$url =~ s#/$##;
					print "\t", $url, ": ";
					if (get_content($url . '/DATE') =~ /^\d+$/gs) {
						print "ok\n";
						push(@$links, $url);
					} else {
						print "failed\n";
					}
				}
			}
		}
}

### CPAN
sub parse_cpan {
	my $response = shift;
	my $links = shift;
	
		my $tree = HTML::TreeBuilder->new();
		$tree->parse($response->decoded_content);
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
			push(@$links, $link->attr('href'));
		}
}

### CTAN
sub parse_ctan {
	my $response = shift;
	my $links = shift;

		for my $line (split(/\r?\n/, $response->decoded_content)) {
			# Typical line:
			#    URL: ftp://carroll.aset.psu.edu/pub/CTAN
			if ($line =~ /^\s+URL: (\S+)$/) {
				my $url = $1;
				print "\t", $url, ": ";
				if (get_content($url . '/CTAN.sites')) {
					print "ok\n";
					push(@$links, $url);
				} else {
					print "failed\n";
				}
			}
		}
}

### Debian
sub parse_debian {
	my $response = shift;
	my $links = shift;

		my $tree = HTML::TreeBuilder->new();
		$tree->parse($response->decoded_content);
		my $table = $tree->look_down(
			'_tag' => 'th',
			sub { $_[0]->as_text eq "Country" },
		)->look_up('_tag' => 'table');
		if ($table) {
			for my $link ($table->look_down('_tag' => 'a')) {
				if ($link) {
					print "\t", $link->attr('href'), ": ok\n";
					push(@$links, $link->attr('href'));
				}
			}
		}
}

### FreeBSD
sub parse_freebsd {
	my $response = shift;
	my $links = shift;

		my $tree = HTML::TreeBuilder->new();
		$tree->parse($response->decoded_content);
		my $tag = $tree->look_down(
			'_tag' => 'div',
			sub { $_[0]->attr('class') eq "VARIABLELIST" },
		);
		if ($tag) {
			FREEBSDLINKS: for my $link ($tag->look_down('_tag' => 'a')) {
				if ($link) {
					my $url = $link->attr('href');
					next if ($url =~ m#^rsync://#);
					$url =~ s,/$,,;
					$url = $url . '/ports/distfiles/';
					for my $num (0..2) {
						my $tempurl = $url . 'exifautotran.txt';
						print "\t", $tempurl, ": ";
						my $content = get_content($tempurl);
						if ($content =~ /Transforms Exif files/gs) {
							print "ok\n";
							push(@$links, $url);
							next FREEBSDLINKS;
						} else {
							print "failed\n";
						}
					}
				}
			}
		}
}

### GIMP
sub parse_gimp {
	my $response = shift;
	my $links = shift;

		my $tree = HTML::TreeBuilder->new();
		$tree->parse($response->decoded_content);
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
						if (get_content($tempurl . 'README') =~ /This is the root directory of the official GIMP/) {
							print "ok\n";
							push(@$links, $tempurl);
							next GIMPLINKS;
						} else {
							print "failed\n";
						}
					}
				}
			}
		}
}

### Gnome
sub parse_gnome {
	my $response = shift;
	my $links = shift;

		my $finder = URI::Find->new(
			sub {
				my ( $url, $orig_uri ) = @_;
				return if ($url =~ /^mailto/);
				$url =~ s#/$##;
				print "\t", $url, ": ";
				if (get_content($url . '/LATEST') =~ /download.gnome.org/gs) {
					print "ok\n";
					push(@$links, $url);
				} else {
					print "failed\n";
				}
			},
		);

		my $content = $mech->content;
		$finder->find( \$content );
}

### GNU
sub parse_gnu {
	my $response = shift;
	my $links = shift;

		my $tree = HTML::TreeBuilder->new();
		$tree->parse($response->decoded_content);
		my $content = $tree->look_down(
			'_tag' => 'div',
			sub { $_[0]->attr('id') eq "content" },
		);
		if ($content) {
			for my $link ($content->look_down('_tag' => 'a')) {
				if ($link) {
					my $url = $link->attr('href');
					next if ($url =~ /^rsync:\/\//);
					$url =~ s#(ftp://)+#ftp://#g;
					$url =~ s#/+$##gs;
					print "\t", $url, ": ";
					if (get_content($url . '/=README') =~ /This directory contains programs/gs) {
						print "ok\n";
						push(@$links, $url);
					} else {
						print "failed\n";
					}
				}
			}
		}
}

### KDE
sub parse_kde {
	my $response = shift;
	my $links = shift;

		my $tree = HTML::TreeBuilder->new();
		$tree->parse($response->decoded_content);
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
					my $url = $link->attr('href');
					$url =~ s#/$##;
					print "\t", $url, ": ";
					if (get_content($url . '/README') =~ /This is the ftp distribution/gs) {
						print "ok\n";
						push(@$links, $url);
					} else {
						print "failed\n";
					}
				}
			}
		}
}

## PostgreSQL
sub parse_postgresql {
	my $response = shift;
	my $links = shift;

		my $tree = HTML::TreeBuilder->new();
		$tree->parse($response->decoded_content);
		for my $link ($tree->look_down('_tag' => 'a')) {
			my $url = $link->attr('href');
			if ($url =~ s/^.*?\&url=//) {
				$url = uri_unescape($url);
				print "\t", $url, ": ";
				if (get_content($url . 'README') =~ /This directory contains the current and past releases of PostgreSQL/gs) {
					print "ok\n";
					push(@$links, $url);
				} else {
					print "failed\n";
				}
			}
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
	my $host;
	eval {
		$host = $uri->host;
	};

	if (not defined $host) {
		warn "unable to determine host for link '$link'";
		return;
	}

	my $code = undef;

	$code = $geo->country_code_by_name($host);
	if (not defined $code or $code =~ /^\s*$/) {
		$debug && warn "unknown code for " . $host . "\n";
		if ($host =~ /\.(\D\D)$/) {
			$code = uc($1);
			warn "found $code in hostname\n";
		} else {
			$code = 'US';
			$debug && warn "still couldn't figure it out, setting to US\n";
		}
	}
	if ($host =~ /ftp\.(\D\D)\.(uu\.net|debian\.org)/) {
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

sub get_content {
	my $url = shift;
	my $return = undef;

	return if ($url =~ /^(\/|mailto\:)/);

	if ($url =~ m#^ftp\://#) {
		my $temp_file = mktemp('mirrorXXXXXX');
		if (system('curl', '-s', '-L', '-o', $temp_file, $url) == 0) {
			$return = read_file($temp_file);
		}
		unlink($temp_file);
	} else {
		my $response = $ua->get($url);
		if ($response->is_success) {
			$return = $response->decoded_content;
		}
	}

	return $return;
}

