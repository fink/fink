# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::CLI module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2004 The Fink Package Manager Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA	 02111-1307, USA.
#

package Fink::CLI;

use Carp;

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	%EXPORT_TAGS = ( );			# eg: TAG => [ qw!name1 name2! ],

	# your exported package globals go here,
	# as well as any optionally exported functions
	@EXPORT_OK	 = qw(&print_breaking &print_breaking_stderr
					  &prompt &prompt_boolean &prompt_selection_new
					  &parse_cmd_options
			      &get_term_width);
}
our @EXPORT_OK;

# non-exported package globals go here
our $linelength = 77;

END { }				# module clean-up code here (global destructor)

=head1 NAME

Fink::CLI - functions for user interaction

=head1 SYNOPSIS

=head1 DESCRIPTION

These functions handle a variety of output formatting and user
interaction/response tasks.

=head2 Functions

No functions are exported by default. You can get whichever ones you
need with things like:

    use Fink::Services '&prompt_boolean';
    use Fink::Services qw(&print_breaking &prompt);

=over 4

=item print_breaking

    print_breaking $string;
    print_breaking $string, $linebreak;
    print_breaking $string, $linebreak, $prefix1;
    print_breaking $string, $linebreak, $prefix1, $prefix2;

Wraps $string, breaking at word-breaks, and prints it on STDOUT. The
screen width used is the package global variable $linelength. Breaking
is performed only at space chars. If $linebreak is true, a linefeed
will be appended to the last line printed, otherwise one will not be
appended. Optionally, prefixes can be defined to prepend to each line
printed: $prefix1 is prepended to the first line, $prefix2 is
prepended to all other lines. If only $prefix1 is defined, that will
be prepended to all lines.

If $string is a multiline string (i.e., it contains embedded newlines
other than an optional one at the end of the whole string), the prefix
rules are applied to each contained line separately. That means
$prefix1 affects the first line printed for each line in $string and
$prefix2 affects all other lines printed for each line in $string.

=cut

sub print_breaking {
	my $s = shift;
	my $linebreak = shift;
	$linebreak = 1 unless defined $linebreak;
	my $prefix1 = shift;
	$prefix1 = "" unless defined $prefix1;
	my $prefix2 = shift;
	$prefix2 = $prefix1 unless defined $prefix2;
	my ($pos, $t, $reallength, $prefix, $first);

	chomp($s);

	# if string has embedded newlines, handle each line separately
	while ($s =~ s/^(.*?)\n//) {
	    # Feed each line except for last back to ourselves (always
	    # want linebreak since $linebreak only controls last line)
	    # prefix behavior: prefix1 for first line of each line of
	    # multiline (cf. first line of the whole multiline only)
	    my $s_line = $1;
	    &print_breaking($s_line, 1, $prefix1, $prefix2);
	}

	# at this point we have either a single line or only the last
	# line of a multiline, so wrap and print

	$first = 1;
	$prefix = $prefix1;
	$reallength = $linelength - length($prefix);
	while (length($s) > $reallength) {
		$pos = rindex($s," ",$reallength);
		if ($pos < 0) {
			$t = substr($s,0,$reallength);
			$s = substr($s,$reallength);
		} else {
			$t = substr($s,0,$pos);
			$s = substr($s,$pos+1);
		}
		print "$prefix$t\n";
		if ($first) {
			$first = 0;
			$prefix = $prefix2;
			$reallength = $linelength - length($prefix);
		}
	}
	print "$prefix$s";
	print "\n" if $linebreak;
}

=item print_breaking_stderr

This is a wrapper around print_breaking that causes output to go to
STDERR. See print_breaking for a complete description of parameters
and usage.

=cut

sub print_breaking_stderr {
	my $old_fh = select STDERR;
	&print_breaking(@_);
	select $old_fh;
}

=item prompt

    my $answer = prompt $prompt;
    my $answer = prompt $prompt, $default;

Ask the user a question and return the answer. The user is prompted
via STDOUT/STDIN using $prompt (which is word-wrapped). If the user
returns a null string or Fink is configured to automatically accept
defaults (i.e., bin/fink was invoked with the -y or --yes option), the
default answer $default is returned (or a null string if no $default
is not defined).

=cut

sub prompt {
	my $prompt = shift;
	my $default_value = shift;
	$default_value = "" unless defined $default_value;
	my ($answer);

	require Fink::Config;
	my $dontask = Fink::Config::get_option("dontask");

	&print_breaking("$prompt [$default_value] ", 0);
	if ($dontask) {
		print "(assuming default)\n";
		$answer = $default_value;
	} else {
		$answer = <STDIN> || "";
		chomp($answer);
		$answer = $default_value if $answer eq "";
	}
	return $answer;
}

=item prompt_boolean

    my $answer = prompt_boolean $prompt;
    my $answer = prompt_boolean $prompt, $default_true;
    my $answer = prompt_boolean $prompt, $default_true, $timeout;

Ask the user a yes/no question and return the logical value of the
answer. The user is prompted via STDOUT/STDIN using $prompt (which is
word-wrapped). If $default_true is true or undef, the default answer
is true, otherwise it is false. If the user returns a null string or
Fink is configured to automatically accept defaults (i.e., bin/fink
was invoked with the -y or --yes option), the default answer is
returned.  The optional $timeout argument establishes a wait period
(in seconds) for the prompt, after which the default answer will be
used.

=cut

sub prompt_boolean {
	my $prompt = shift;
	my $default_value = shift;
	$default_value = 1 unless defined $default_value;
	my $timeout = shift;
	my ($answer, $meaning);

	require Fink::Config;
	my $dontask = Fink::Config::get_option("dontask");

	while (1) {
		&print_breaking("$prompt [".($default_value ? "Y/n" : "y/N")."] ", 0);
		if ($dontask) {
			print "(assuming default)\n";
			$meaning = $default_value;
			last;
		}
		if (defined $timeout) {
			$answer = eval {
				local $SIG{ALRM} = sub {
					print "\n\nTIMEOUT: using default answer.\n";
					die;
				};
				alarm $timeout;
				my $answer = <STDIN>;
				alarm(0);
				return $answer;
			} || "";
		} else {
		    $answer = <STDIN> || "";
		}
		chomp($answer);
		if ($answer eq "") {
			$meaning = $default_value;
			last;
		} elsif ($answer =~ /^y(es?)?/i) {
			$meaning = 1;
			last;
		} elsif ($answer =~ /^no?/i) {
			$meaning = 0;
			last;
		}
	}

	return $meaning;
}

=item prompt_selection_new

    my $answer = prompt_selection_new $prompt, \@default, @choices;

Ask the user a multiple-choice question and return the answer. The
user is prompted via STDOUT/STDIN using $prompt (which is
word-wrapped) and a list of choices. The choices are numbered
(beginning with 1) and the user selects by number. The list @choices
is an ordered pairwise list (label1,value1,label2,value2,...). If the
user returns a null string or Fink is configured to automatically
accept defaults (i.e., bin/fink was invoked with the -y or --yes
option), the default answer is used according to the following:

  @default = undef;                # choice 1
  @default = [];                   # choice 1
  @default = ["number", $number];  # choice $number
  @default = ["label", $label];    # first choice with label $label
  @default = ["value", $label];    # first choice with value $value

=cut

sub prompt_selection_new {
	my $prompt = shift;
	my $default = shift;
	my @choices = @_;
	my ($count, $index, $answer, $default_value);

	if (@choices/2 != int(@choices/2)) {
		confess "Odd number of elements in \@choices";
	}

	if (!defined $default->[0]) {
		$default_value = 1;
	} elsif ($default->[0] eq "number") {
		$default_value = $default->[1];
		$default_value = 1 if $default_value < 1 || $default_value > @choices/2;
	} elsif ($default->[0] =~ /^(label|value)$/) {
		# will be handled later
	} else {
		confess "Unknown default type ",$default->[0];
	}

	require Fink::Config;
	my $dontask = Fink::Config::get_option("dontask");

	$count = 0;
	for ($index = 0; $index <= $#choices; $index+=2) {
		$count++;
		print "\n($count)	 $choices[$index]";
		if (!defined $default_value && (
						(
						 ($default->[0] eq "label" && $choices[$index]   eq $default->[1])
						 ||
						 ($default->[0] eq "value" && $choices[$index+1] eq $default->[1])
						 )
						)) {
			$default_value = $count;
		}

	}
	$default_value = 1 if !defined $default_value;
	print "\n\n";

	&print_breaking("$prompt [$default_value] ", 0);
	if ($dontask) {
		print "(assuming default)\n";
		$answer = $default_value;
	} else {
		$answer = <STDIN> || "";
		chomp($answer);
		if (!$answer) {
			$answer = 0;
		}
		$answer = int($answer);
		if ($answer < 1 || $answer > $count) {
			$answer = $default_value;
		}
	}
	return $choices[2*$answer-1];
}

=item get_term_width

  my $width = get_term_width;

This function returns the width of the terminal window, or zero if STDOUT 
is not a terminal. Uses Term::ReadKey if it is available, greps the TERMCAP
env var if ReadKey is not installed, tries tput if neither are available,
and if nothing works just returns 80.

=cut

sub get_term_width {
	my ($width, $dummy);
	use POSIX qw(isatty);
	if (isatty(fileno STDOUT))
	{
		if (eval { require Term::ReadKey; 1; }) {
			import Term::ReadKey qw(&GetTerminalSize);
			($width, $dummy, $dummy, $dummy) = &GetTerminalSize();						 
		}
		else {
			$width =~ s/.*co#([0-9]+).*/$1/ if defined ($width = $ENV{TERMCAP});
			unless (defined $width and $width =~ /^\d+$/) {
				chomp($width = `tput cols`)		 # Only use tput if it won't spout an error.
								if -t 1 and defined ($width = $ENV{TERM}) and $width ne "unknown";
				unless ($? == 0 and defined $width and $width =~ /^\d+$/) {
					$width = $ENV{COLUMNS};
					unless (defined $width and $width =~ /^\d+$/) {
						$width = 80;
					}
				}
			}
		}
	}
	else {
		# Not a TTY
		$width = 0;
	}
	if ($width !~ /^[0-9]+$/) {
		# Shouldn't get here, but just in case...
		$width = 80;
	}
	return $width;
}

=item parse_cmd_options

  my @remainder = &parse_cmd_options($cmd, \@arg_info, @args);

This function does Getopt::Long processing of the command-line args
passed in @args according to the @arg_info. Each element of that array
is a ref to a 3-element list ($flag, $action, $help) where $flag and
$action are the key and value passed to Getopt::Long:GetOptions.  The
--help flag is handled automatically (and does not return): $help is
the message for each flag in $flag. The subcommand is passed in $cmd
for use in help and error messages. The remaining (unprocessed)
arguments from @args are returned.

=cut

sub parse_cmd_options {
	my $cmd = shift;
	my $arg_info = shift;

	# GetOptions processes @ARGV so save the original
	my @temp_ARGV = @ARGV;
	@ARGV=@_;

	my $wanthelp;

	use Getopt::Long;
	Getopt::Long::Configure(qw(bundling ignore_case require_order no_getopt_compat prefix_pattern=(--|-)));
	GetOptions(
		'help|h' => \$wanthelp,
		map { $_->[0] => $_->[1] } @$arg_info
	) or die "fink $cmd: unknown option\nType 'fink $cmd --help' for more information.\n";
	if ($wanthelp) {
		require Fink::FinkVersion;
		my $version = Fink::FinkVersion::fink_version();

		print "Fink $version\n\n";
		print "Usage: fink [options] $cmd [options] [package(s)]\n\n";
		print "Options:\n";

		my $maxlen = 0;                          # width of flags column
		my $maxmaxlen = int $linelength/2 - 6;   # maximum allowed $maxlen

		my @flags = map { $_->[0] } @$arg_info;  # the Getopt-formatted flags
		# convert to pretty-printing format
		foreach (@flags) {
			s/!\+//g;                        # clear toggle & incremental specs
			s/[=:].//g;                      # clear value type specs
			$_ = join ", ", map {
				# put - before each single-char flag, -- before each multi-char
				length $_ == 1 ? "-$_" : "--$_" 
				} split /\|/;
			# track longest string (but not if too long)
			$maxlen = length $_ if $maxlen < length $_ && length $_ <= $maxmaxlen;
		};

		my $indent = ' ' x ($maxlen+4);  # spaces to get to "-" marker

		my @descs = map { $_->[2] } @$arg_info;  # descriptions
		while(defined( my $helpstring = shift @flags)) {
			# scroll through the parallel @flags and @descs list
			if (length $helpstring > $maxlen) {
				# long flag strings need wrapping so put on their own line
				&print_breaking($helpstring, 1, '  ');
				&print_breaking("- $descs[0]", 1, $indent, "$indent  ");
			} else {
				# short flag strings go on same line as (start of) help msg
				&print_breaking($helpstring.' ' x ($maxlen+2-length($helpstring))."- $descs[0]", 1, '  ', "$indent  ");
			}
			shift @descs;
		}
		print '  ', '1234567890' x 6, "\n";
		exit 0;
	}

	@_ = @ARGV;          # whatever didn't get parsed off
	@ARGV = @temp_ARGV;  # restore original @ARGV

	return @_;
}

=back

=cut

### EOF
1;
