# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::CLI module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2011 The Fink Package Manager Team
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
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA.
#

package Fink::CLI;

use Carp;
use File::Temp qw(tempfile);
use Fcntl qw(:seek :DEFAULT);
use IO::Handle;

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
	@EXPORT_OK	 = qw(&print_breaking &print_breaking_stderr &die_breaking
					  &rejoin_text
					  &prompt &prompt_boolean &prompt_selection
					  &print_optionlist
					  &get_term_width &should_skip_prompt
					  &word_wrap &capture);
}
our @EXPORT_OK;

# non-exported package globals go here
our $linelength = 77;

END { }				# module clean-up code here (global destructor)

=head1 NAME

Fink::CLI - functions for user interaction

=head1 DESCRIPTION

These functions handle a variety of output formatting and user
interaction/response tasks.

=head2 Functions

No functions are exported by default. You can get whichever ones you
need with things like:

    use Fink::CLI '&prompt_boolean';
    use Fink::CLI qw(&print_breaking &prompt);

=over 4

=item word_wrap

    my @lines = word_wrap $string, $length;
    my @lines = word_wrap $string, $length, $prefix1;
    my @lines = word_wrap $string, $length, $prefix1, $prefix2;

Word wraps a single-line string $string to maximum length $length, and returns
the resulting lines. Breaking is performed only at space characters.

Optionally, prefixes can be defined to prepend to each line printed:
$prefix1 is prepended to the first line, $prefix2 is prepended to all
other lines. If only $prefix1 is defined, that will be prepended to
all lines.

=cut

sub word_wrap {
	my ($s, $length, $prefix1, $prefix2) = @_;
	$prefix1 = "" unless defined $prefix1;
	$prefix2 = "" unless defined $prefix2;
	
	my @lines;
	
	my $first = 1;
	my $prefix = $prefix1;
	my $reallength = $length - length($prefix);
	while (length($s) > $reallength) {
		my $t;
		my $pos = rindex($s," ",$reallength);
		if ($pos < 0) {
			$t = substr($s,0,$reallength);
			$s = substr($s,$reallength);
		} else {
			$t = substr($s,0,$pos);
			$s = substr($s,$pos+1);
		}
		push @lines, "$prefix$t";
		if ($first) {
			$first = 0;
			$prefix = $prefix2;
			$reallength = $length - length($prefix);
		}
	}
	push @lines, "$prefix$s";
	
	return @lines;
}

=item print_breaking

    print_breaking $string;
    print_breaking $string, $linebreak;
    print_breaking $string, $linebreak, $prefix1;
    print_breaking $string, $linebreak, $prefix1, $prefix2;

Wraps $string, breaking at word-breaks, and prints it on STDOUT. The
screen width is determined by get_term_width, or if that fails, the
package global variable $linelength. Breaking is performed only at
space chars. A linefeed will be appended to the last line printed
unless $linebreak is defined and false.

Optionally, prefixes can be defined to prepend to each line printed:
$prefix1 is prepended to the first line, $prefix2 is prepended to all
other lines. If only $prefix1 is defined, that will be prepended to
all lines.

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

	my $width = &get_term_width - 1;    # some termcaps need a char for \n
	$width = $linelength if $width < 1;

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
	my @lines = word_wrap $s, $width, $prefix1, $prefix2;
	for (my $i = 0; $i < $#lines; ++$i) {
		print "$lines[$i]\n";
	}
	print $lines[$#lines];
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

=item die_breaking

  die_breaking $message;

Raises an exception like 'die', but formats the error message with
print_breaking.

Note that this does not have all the special features of 'die', such as adding
the line number on which the error occurs or propagating previous errors if
no argument is passed.

=cut

sub die_breaking {
	my $msg = shift;
	print_breaking_stderr $msg;
	die "\n";
}

=item rejoin_text

	print_breaking rejoin_text <<EOMSG
    Here is paragraph
    one.

    And
    two.
    EOMSG

This function takes text in which multiple newlines are used to
delimit paragraphs and removes newlines from within paragraphs.
Multiple newlines (and any intervening whitespace) become a double
newline. Each "internal" newline becomes a single space.

=cut

sub rejoin_text {
	my $s = shift;
	my @pars = split /\n\s*\n/, $s;
	map { s/\n/ /g } @pars;
	return join "\n\n", @pars;
}

=item prompt

    my $answer = prompt $prompt;
    my $answer = prompt $prompt, %options;

Ask the user a question and return the answer. The user is prompted
via STDOUT/STDIN using $prompt (which is word-wrapped). The trailing
newline from the user's entry is removed.

The %options are given as option => value pairs. The following
options are known:

=over 4

=item default (optional)

If the option 'default' is given, then its value will be
returned if no input is detected.

This can occur if the user enters a null string, or if Fink
is configured to automatically accept defaults (i.e., bin/fink
was invoked with the -y or --yes option).

Default value: null string

=item timeout (optional)

The 'timeout' option establishes a wait period (in seconds) for
the prompt, after which the default answer will be used.
If a timeout is given, any existing alarm() is destroyed.

Default value: no timeout

=item category (optional)

A string to categorize this prompt.

=back

=cut

sub prompt {
	my $prompt = shift;
	my %opts = (default => "", timeout => 0, category => '', @_);

	my $answer = &get_input("$prompt [$opts{default}]",
		map { $_ => $opts{$_} } qw(timeout category));
	chomp $answer;
	$answer = $opts{default} if $answer eq "";
	return $answer;
}

=item prompt_boolean

    my $answer = prompt_boolean $prompt;
    my $answer = prompt_boolean $prompt, %options;

Ask the user a yes/no question and return the B<truth>-value of the
answer. The user is prompted via STDOUT/STDIN using $prompt (which is
word-wrapped).

The %options are given as option => value pairs. The following
options are known:

=over 4

=item default (optional)

If the option 'default' is given, then its B<truth>-value will be
returned if no input is detected.

This can occur if the user enters a null string, or if Fink
is configured to automatically accept defaults (i.e., bin/fink
was invoked with the -y or --yes option).

Default value: true

=item timeout (optional)

The 'timeout' option establishes a wait period (in seconds) for
the prompt, after which the default answer will be used.
If a timeout is given, any existing alarm() is destroyed.

Default value: no timeout

=item category (optional)

A string to categorize this prompt.

=back

=cut

sub prompt_boolean {
	my $prompt = shift;
	my %opts = (default => 1, timeout => 0, category => '', @_);

	my $choice_prompt = $opts{default} ? "Y/n" : "y/N";

	my $meaning;
	my $answer = &get_input(
		"$prompt [$choice_prompt]",
		map { $_ => $opts{$_} } qw(timeout category),
	);
	while (1) {
		chomp $answer;
		if ($answer eq "") {
			$meaning = $opts{default};
			last;
		} elsif ($answer =~ /^y(es?)?$/i) {
			$meaning = 1;
			last;
		} elsif ($answer =~ /^no?$/i) {
			$meaning = 0;
			last;
		}
		$answer = &get_input(
			"Invalid choice. Please try again [$choice_prompt]",
			map { $_ => $opts{$_} } qw(timeout category),
		);
	}

	return $meaning;
}

=item prompt_selection

    my $answer = prompt_selection $prompt, %options;

Ask the user a multiple-choice question and return the value for the
choice. The user is prompted via STDOUT/STDIN using $prompt (which is
word-wrapped) and a list of choices. The choices are numbered
(beginning with 1) and the user selects by number.

The %options are given as option => value pairs. The following
options are known:

=over 4

=item choices (required)

The option 'choices' must be a reference to an ordered pairwise
array [ label1 => value1, label2 => value2, ... ]. The labels will
be displayed to the user; the values are the return values if that
option is chosen.

=item default (optional)

If the option 'default' is given, then it determines which choice
will be returned if no input is detected.

This can occur if the user enters a null string, or if Fink
is configured to automatically accept defaults (i.e., bin/fink
was invoked with the -y or --yes option).

The following formats are recognized for the 'default' option:

  @default = [];                   # choice 1
  @default = ["number", $number];  # choice $number
  @default = ["label", $label];    # first choice with label $label
  @default = ["value", $label];    # first choice with value $value

Default value: choice 1

=item timeout (optional)

The 'timeout' option establishes a wait period (in seconds) for
the prompt, after which the default answer will be used.
If a timeout is given, any existing alarm() is destroyed.

Default value: no timeout

=item intro (optional)

A text block that will be displayed before the list of options. This
contrasts with the $prompt, which is goes afterwards.

=item category (optional)

A string to categorize this prompt.

=back

=cut

sub prompt_selection {
	my $prompt = shift;
	my %opts = (default => [], timeout => 0, category => '', @_);
	my @choices = @{$opts{choices}};
	my $default = $opts{default};

	my ($count, $default_value);

	if (@choices/2 != int(@choices/2)) {
		confess 'Odd number of elements in @choices';
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

	print "\n";

	if (defined $opts{intro}) {
		&print_breaking($opts{intro});
		print "\n";
	}

	$count = 0;
	for (my $index = 0; $index <= $#choices; $index+=2) {
		$count++;
		print "($count)\t$choices[$index]\n";
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
	print "\n";

	my $answer = &get_input(
		"$prompt [$default_value]",
		map { $_ => $opts{$_} } qw(timeout category),
	);
	while (1) {
		chomp $answer;
		if ($answer eq "") {
			$answer = $default_value;
			last;
		} elsif ($answer =~ /^[1-9]\d*$/ and $answer >= 1 && $answer <= $count) {
			last;
		}
		$answer = &get_input(
			"Invalid choice. Please try again [$default_value]",
			map { $_ => $opts{$_} } qw(timeout category),
		);
	}

	return $choices[2*$answer-1];
}

=item should_skip_prompt

  my $bool = should_skip_prompt $category;

Returns whether or not Fink should skip prompts of the given category.
A false $category represents an uncategorized prompt.

=cut

{
	my $skip_cats = undef;
	
	sub should_skip_prompt {
		my $cat = lc shift;
		return 0 unless $cat;
		
		if (!defined $skip_cats) {
			my $str = $Fink::Config::config->param_default(
				'SkipPrompts', '');
			$skip_cats = {
				map { s/^\s+(.*?)\s+$/$1/; lc $_ => 1 } # Trim
				split /,/, $str    # stupid perl.el needs this slash: /
			};
		}
		return exists $skip_cats->{$cat};
	}
}

=item get_input

    my $answer = get_input $prompt;
    my $answer = get_input $prompt, %options;

Prints the string $prompt, then gets a single line of input from
STDIN.

Returns the entered string
(including the trailing newline), or a null string if the timeout
expires or immediately (without waiting for input) if fink is suppressing
the prompt (run with the -y option or with an appropriate SuppressPrompts).
If not suppressing a prompt, this function destroys any pre-existing alarm().
STDIN is flushed before accepting input, so stray keystrokes prior to
the prompt are ignored.

The options hash can contain the following keys:

=over 4

=item timeout => $timeout (optional)

If $timeout is zero or not given, will block forever waiting
for input. If $timeout is given and is positive, will only wait that
many seconds for input before giving up.

=item category => $category (optional)

Categorizes this prompt. If $category is listed in the comma-delimited
SuppressPrompts in fink.conf, will use the default value and not prompt the
user.

=back

=cut

sub get_input {
	my $prompt = shift;
	my %opts = (timeout => 0, category => '', @_);

	use POSIX qw(tcflush TCIFLUSH);

	# Don't really skip SkipPrompts, just make them short
	my $skip_timeout = 7;
	if ( should_skip_prompt($opts{category})
			&& ($opts{timeout} == 0 || $opts{timeout} > $skip_timeout) ) {
		$opts{timeout} = $skip_timeout;
	}
	
	# handle suppressed prompts
	my $dontask = 0;
	require Fink::Config;
	if (Fink::Config::get_option("dontask")) {
		$dontask = 1;
	}
	
	# print the prompt string (leaving cursor on the same line)
	&print_breaking("Default answer will be chosen in $opts{timeout} "
		. "seconds...\n") if $opts{timeout} && !$dontask;
	$prompt = "" if !defined $prompt;
	&print_breaking("$prompt ", 0);
	
	if ($dontask) {
		print "(assuming default)\n";
		return "";
	}

	# get input, with optional timeout functionality
	my $answer = eval {
		local $SIG{ALRM} = sub { die "SIG$_[0]\n"; };  # alarm() expired
		alarm $opts{timeout};  # alarm(0) means cancel the timer
		tcflush(fileno(STDIN),TCIFLUSH);
		my $answer = <STDIN>;
		alarm 0;
		return $answer;
	} || "";

	# deal with error conditions raised by eval{}
	if (length $@) {
		print "\n";   # move off input-prompt line
		if ($@ eq "SIGALRM\n") {
			print "TIMEOUT: using default answer.\n";
		} else {
			die $@;   # something else happened, so just propagate it
		}
	}

	return $answer;
}

=item get_term_width

  my $width = get_term_width;

This function returns the width of the terminal window, or zero if STDOUT 
is not a terminal. Uses Term::ReadKey if it is available, greps the TERMCAP
env var if ReadKey is not installed, tries tput if neither are available,
and if nothing works just returns 80. This function always returns a
number, not undef.

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

=item capture

  my $return = capture { BLOCK }, \$out, \$err;

Executes BLOCK, but intercepts STDOUT and STDERR, putting them into the
arguments $out and $err. The return value is simply the BLOCK's return value.

If $out and $err point to the same scalar, STDOUT and STDERR will have their
outputs merged.

=cut

{ # Simple logging, for when normal out/err aren't available
	my $capterr_dir = undef; # set to undef for production, path for debug
	my $capterr;
	if (defined $capterr_dir) {
		($capterr) = tempfile("capture.XXXXX", DIR => $capterr_dir,
			UNLINK => 0);
		$capterr->autoflush(1);
	}
	sub _fh_log { print $capterr @_, "\n\n" if defined $capterr }
}
	
# Die, printing to a log FH (in addition to stderr)
sub _fh_die {
	my $msg = shift;
	_fh_log(Carp::longmess($msg));
	die $msg;
}

# Save a filehandle
# my $saved = _fh_save \*FH;
sub _fh_save {
	my ($fh, $scalar) = @_;
	_fh_die "Argument must be a scalar ref"
		unless ref($scalar) && ref($scalar) eq 'SCALAR';
	open my $save, '>&', $fh or _fh_die "Can't save filehandle: $!";
	close $fh or _fh_die "Can't temporarily close filehandle: $!";
	return $save;
}

# Reading a filehandle, then restore to the saved FH 
# _fh_restore \*FH, $save, \$read_into;  Last arg optional
sub _fh_restore {
	my ($fh, $save, $into) = @_;
	if (defined $into) {
		$fh->flush or _fh_die "Can't flush: $!";
		seek $fh, 0, SEEK_SET or _fh_die "Can't seek: $!";
		$$into = join('', <$fh>);
		_fh_die "Can't read filehandle: $!" if $fh->error;
	}
	close $fh or _fh_die "Can't close filehandle: $!";
	
	# Try not to use an excessive open mode
	my $mode = (fcntl($save, F_GETFL, 0) & O_RDWR) ? '+>&' : '>&';
	open $fh, $mode, $save or _fh_die "Can't reopen filehandle: $!";
	close $save or _fh_die "Can't close saved filehandle: $!";
}	

sub capture (&$;$) {
	my ($code, $out, $err, @toomany) = @_;
	_fh_die "Too many arguments!" if @toomany;
	my ($die, $ret, $setupok);
	my $array = wantarray;
	
	# Setup the filehandles
	my ($savout, $saverr);
	if (defined $out) {
		$savout = _fh_save(*STDOUT{IO}, $out); # ok to die
		open STDOUT, '+>', undef or _fh_die "Can't reopen STDOUT: $!";
	}
	eval { # cleanup stdout if error within this block
		if (defined $err) {
			$saverr = _fh_save(*STDERR{IO}, $err);
			if ($out eq $err) {
				open STDERR, '>&', STDOUT or _fh_die "Can't merge STDERR: $!";
			} else {
				open STDERR, '+>', undef or _fh_die "Can't reopen STDERR: $!";
			}
		}
		$setupok = 1; # Now ok to save output
		
		# Run!
		eval { $ret = $array ? [ &$code() ] : scalar(&$code()) };
		$die ||= $@;
		
		# Tear down
		_fh_restore(*STDERR{IO}, $saverr, $setupok && $out eq $err ? () : $err)
			if defined $saverr;
	};
	$die ||= $@;
	_fh_restore(*STDOUT{IO}, $savout, $setupok ? $out : ()) if defined $savout;
	
	# Finish up
	_fh_die $die if $die;
	return $array ? @$ret : $ret;
}

=back

=cut

### EOF
1;
# vim: ts=4 sw=4 noet
