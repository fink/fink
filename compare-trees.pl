#!/usr/bin/perl -w
# -*- mode: Perl; tab-width: 4; -*-

use File::Basename;
use Getopt::Std;
use strict;

our ($opt_h, $opt_l, $opt_m, $opt_w, $opt_p, $opt_t, $opt_d, $opt_r);
getopts('hlm:wptdr');

if ($opt_h) {
	print <<END;
usage: $0 [-h] [-l] [-m <text>] [directory ...]

	-h         this help
	-l         include trees other than stable/unstable
	-m <text>  list only packages maintained by someone
	           matching text <text>
	-w         conserve white space
	-p         list package names only (also turns off md5sum check)
	-t         list and sort by maintainer
	-d         ignore md5sum check
	-r         ignore revisions (also turns off md5sum check)

END
	exit 0;
}

$ENV{PATH} = '/sw/bin:'.$ENV{PATH};

my %PACKAGES;
my @TREES;
my $prefix;

if (defined $opt_r or defined $opt_p) {
	$opt_d=1;
}

if (@ARGV) {
	@TREES = @ARGV;
} else {
	if (opendir(DIR, dirname($0))) {
		$prefix = dirname($0);
		for my $dir (grep(!/^\.\.?$/, readdir(DIR))) {
			push(@TREES, $prefix . '/' . $dir);
		}
	} else {
		die "couldn't read from " . dirname($0) . ": $!\n";
	}
}

for my $tree (@TREES) {
	my $treename = $tree;
	$treename =~ s#/*$##;
	$treename =~ s#^.*/##;

	if (open(FIND, "/usr/bin/find $tree -name '*.info' | /usr/bin/xargs md5sum |")) {
		while (my $file = <FIND>) {
			chomp $file;
			my $md5sum;
			($md5sum, $file) = split(/\s+/, $file);
			if (open(INFO, $file)) {
				my $firstpack = "";
				my $maint     = "";
				my $packname  = "";
				my $version   = 0;
				my $revision  = 0;
				my $epoch     = 0;
				my $stable    = "stable";
				$stable = $1 if ($file =~ m#/([^/]+)/[^/]+/finkinfo#);
				next if ((($stable ne "stable" and $stable ne "unstable") or $file =~ /\/local\//) and not $opt_l);
				chomp(my @info = <INFO>);
				close(INFO);
				if (not defined $opt_m or grep(/^maintainer:.*$opt_m.*$/i, @info)) {
					for (@info) {
						if (/^\s*version:\s*(\S+)\s*$/i) {
							$version = $1;
						} elsif (/^\s*revision:\s*(\S+)\s*$/i) {
							$revision = $1;
						} elsif (/^\s*epoch:\s*(\S+)\s*$/i) {
							$epoch = $1;
						} elsif (/^\s*maintainer:\s*(.+?)\s*$/i) {
							$maint = $1;
						} elsif (/^\s*package:\s*(\S+)\s*$/i) {
							my $package = $1;
							if ($firstpack eq "") {
								$firstpack = $package;
							}
							$package =~ s/\%N/$firstpack/i;
							my @maints = grep (/^\s*maintainer:\s*(.+?)\s*$/i, @info);
							$maint = $maints[0];
							$maint =~ s/^\s*maintainer:\s*//i;
							if ($packname ne "") {
								if (not defined $opt_t) {
									push(@{$PACKAGES{$packname}->{version}->{get_verstring($epoch, $version, $revision)}}, get_treestring($treename, $stable, $file));
									push(@{$PACKAGES{$packname}->{md5s}->{get_verstring($epoch, $version, $revision)}->{$md5sum}}, get_treestring($treename, $stable, $file));
								} else {
									push(@{$PACKAGES{$maint}->{$packname}->{version}->{get_verstring($epoch, $version, $revision)}}, get_treestring($treename, $stable, $file));
									push(@{$PACKAGES{$maint}->{$packname}->{md5s}->{get_verstring($epoch, $version, $revision)}->{$md5sum}}, get_treestring($treename, $stable, $file));
								}
							}
							$packname = $package;
						}
					}
					$packname =~ s/\%N/$firstpack/g;
					if (not defined $opt_t) {
						push(@{$PACKAGES{$packname}->{version}->{get_verstring($epoch, $version, $revision)}}, get_treestring($treename, $stable, $file));
						push(@{$PACKAGES{$packname}->{md5s}->{get_verstring($epoch, $version, $revision)}->{$md5sum}}, get_treestring($treename, $stable, $file));
					} else {
						push(@{$PACKAGES{$maint}->{$packname}->{version}->{get_verstring($epoch, $version, $revision)}}, get_treestring($treename, $stable, $file));
						push(@{$PACKAGES{$maint}->{$packname}->{md5s}->{get_verstring($epoch, $version, $revision)}->{$md5sum}}, get_treestring($treename, $stable, $file));
					}
				}
			} else {
				warn "unable to open $file: $!\n";
			}
		}
		close(FIND);
	} else {
		warn "find failed in tree $treename, skipping: $!\n";
	}
}
if (not defined $opt_t) {
	for my $package (sort keys %PACKAGES) {
		my $output;
		if (not defined $opt_p) {
			$output = $package . ":\n";
		} else {
			$output = $package . "\n";
		}
		if (not defined $opt_p) {
			for my $version (sort keys %{$PACKAGES{$package}->{version}}) {
				$output .= sprintf('  %-20s ', $version);
				$output .= join(", ", @{$PACKAGES{$package}->{version}->{$version}});
				if (keys %{$PACKAGES{$package}->{md5s}->{$version}} > 1 and not defined $opt_d) {
					$output .= " (md5's don't match)\n";
					for my $md5sum (sort keys %{$PACKAGES{$package}->{md5s}->{$version}}) {
						$output .= " " x 27 . $md5sum . ": ";
						$output .= join(', ', @{$PACKAGES{$package}->{md5s}->{$version}->{$md5sum}});
						$output .= "\n";
					}
				} else {
					$output .= "\n";
				}
			}
		}
		$output =~ s/\n*$//;
		if (not defined $opt_w) {
			print $output, "\n\n";
		} else {
			print $output, "\n";
		}
	}
} else {
	for my $maint (sort keys %PACKAGES) {
		print $maint . ":\n";
		for my $package (sort keys %{$PACKAGES{$maint}}) {
			my $output;
			if (not defined $opt_p) {
				$output = $package . ":\n";
			} else {
				$output = $package . "\n";
			}
			if (not defined $opt_p) {
				for my $version (sort keys %{$PACKAGES{$maint}->{$package}->{version}}) {
					$output .= sprintf('    %-20s ', $version);
					$output .= join(", ", @{$PACKAGES{$maint}->{$package}->{version}->{$version}});
					if (keys %{$PACKAGES{$maint}->{$package}->{md5s}->{$version}} > 1 and not defined $opt_d) {
						$output .= " (md5's don't match)\n";
						for my $md5sum (sort keys %{$PACKAGES{$maint}->{$package}->{md5s}->{$version}}) {
							$output .= " " x 27 . $md5sum . ": ";
							$output .= join(', ', @{$PACKAGES{$maint}->{$package}->{md5s}->{$version}->{$md5sum}});
							$output .= "\n";
						}
					} else {
						$output .= "\n";
					}
				}
			}
			if (not defined $opt_w) {
				$output .= "\n";
			}
			$output =~ s/\n*$//;
			if (not defined $opt_w) {
				print $output, "\n\n";
			} else {
				print $output, "\n";
			}
		}
		print "\n";
	}
}

sub get_verstring {
	my $epoch    = shift;
	my $version  = shift;
	my $revision = shift;

	if (not defined $opt_r) {
		if ($epoch) {
			return $epoch . ':' . $version . '-' . $revision;
		} else {
			return $version . '-' . $revision;
		}
	} else {
		return $version;
	}
}

sub get_treestring {
	my $treename = shift;
	my $stable   = shift;
	my $file     = shift;

	if ($file =~ m#/crypto/#) {
		$file = "/crypto";
	} elsif ($file =~ m#.*(/[^/]+)/[^/]+$#) {
		$file = $1;
	} else {
		$file = "";
	}

	return $treename . '/' . $stable . $file;
}

# vim: ts=4 sw=4 noet
