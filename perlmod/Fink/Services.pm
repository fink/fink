#
# Fink::Services module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2003 The Fink Package Manager Team
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

package Fink::Services;

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
	@EXPORT_OK	 = qw(&read_config &read_properties &read_properties_var
					  &read_properties_multival
					  &execute &execute_script &expand_percent
					  &filename &print_breaking
					  &prompt &prompt_boolean &prompt_selection
					  &version_cmp &latest_version &parse_fullversion
					  &collapse_space &get_term_width
					  &file_MD5_checksum &get_arch &get_sw_vers
					  &get_system_perl_version &get_path);
}
our @EXPORT_OK;

# non-exported package globals go here
our $linelength = 77;
our $arch;
our $system_perl_version;

END { }				# module clean-up code here (global destructor)

=head1 NAME

Fink::Services - functions for text processing and user interaction

=head1 SYNOPSIS

=head1 DESCRIPTION

These functions handle a variety of text (file and string) parsing,
outupt formatting, and user interaction/response tasks.

=head2 Functions

No functions are exported by default. You can get whichever ones you
need with things like:

    use Fink::Services '&read_config';
    use Fink::Services qw(&execute_script &expand_percent);

=over 4

=item read_config

    my $config = read_config $filename;
    my $config = read_config $filename, \%defaults;

Reads a fink.conf file given by $filename into a new Fink::Config
object and initializes Fink::Config globals from it. If %defaults is
given they will be used as defaults for any keys not in the config
file. The new object is returned.

=cut

sub read_config {
	my($filename, $defaults) = @_;

	require Fink::Config;

	my $config_object = Fink::Config->new_with_path($filename, $defaults);

	return $config_object;
}

=item read_properties

    my $property_hash = read_properties $filename;
    my $property_hash = read_properties $filename, $notLC;

Reads a text file $filename and returns a ref to a hash of its
fields. See the description of read_properties_lines for more
information.

If $filename cannot be read, program will die with an error message.

=cut

sub read_properties {
	 my ($file) = shift;
	 # do we make the keys all lowercase
	 my ($notLC) = shift || 0;
	 my (@lines);
	 
	 open(IN,$file) or die "can't open $file: $!";
	 @lines = <IN>;
	 close(IN);
	 return read_properties_lines($file, $notLC, @lines);
}

=item read_properties_var

    my $property_hash = read_properties_var $filename, $string;
    my $property_hash = read_properties_var $filename, $string, $notLC;

Parses the multiline text $string and returns a ref to a hash of
its fields. See the description of read_properties_lines for more
information. The string $filename is used in parsing-error messages
but the file is not accessed.

=cut

sub read_properties_var {
	 my ($file) = shift;
	 my ($var) = shift;
	 # do we make the keys all lowercase
	 my ($notLC) = shift || 0;
	 my (@lines);
	 my ($line);

	 @lines = split /^/m,$var;
	 return read_properties_lines($file, $notLC, @lines);
}

=begin private

=item read_properties_lines

    my $property_hash = read_properties_lines $filename, $notLC, @lines;

Parses the list of text strings @lines and returns a ref to a hash of
its fields. The string $filename is used in parsing-error messages but
the file is not accessed.

If $notLC is true, fields are treated in a case-sensitive manner. If
$notLC is false (including undef), field case is ignored (and
cannonicalized to lower-case). In functions where passing $notLC is
optional, not passing is equivalent to false.

See the Fink Packaging Manual, section 2.2 "File Format" for
information about the format of @lines text.

If errors are encountered while parsing @lines, messages are sent to
STDOUT, but whatever (possibly incorrect) parsing is returned anyway.
The following situations are checked:

  More than one occurance of a key. In this situation, the last
  occurance encountered in @lines is the one returned. Note that the
  same key can occur in the main package and/or different splitoff
  packages, up to one time in each.

  Use of RFC-822-style multilining (whitespace indent of second and
  subsequent lines). This notation has been deprecated in favor of
  heredoc notation.

  Any unknown/invalid syntax.

  Reaching the end of @lines while a heredoc multiline value is still
  open.

Note that no check is made for the validity of the fields being in the
file in which they were encountered. The filetype (fink.conf, *.info,
etc.) is not necessarily known and this routine is used for many
different filetypes.

=end private

=cut

sub read_properties_lines {
	my ($file) = shift;
	# do we make the keys all lowercase
	my ($notLC) = shift || 0;
	my (@lines) = @_;
	my ($hash, $lastkey, $heredoc);

	$hash = {};
	$lastkey = "";
	$heredoc = 0;

	foreach (@lines) {
		chomp;
		if ($heredoc > 0) {
			# We are inside a HereDoc
			if (/^\s*<<\s*$/) {
				# The heredoc ends here; decrese the nesting level
				$heredoc--;
				if ($heredoc > 0) {
					# This was the end of an inner/nested heredoc. Just append
					# it to the data of its parent heredoc.
					$hash->{$lastkey} .= $_."\n";
				} else {
					# The heredoc really ended; remove trailing empty lines.
					$hash->{$lastkey} =~ s/\s+$//;
					$hash->{$lastkey} .= "\n";
				}
			} else {
				# Append line to the heredoc.
				$hash->{$lastkey} .= $_."\n";

				# Did a nested heredoc start here? This commonly occurs when
				# using splitoffs in a package. We need to detect it, else the
				# parser would have no way to distinguish the end of the inner
				# heredoc(s) and the end of the top heredoc, since both are
				# marked by '<<'.
				$heredoc++ if (/<<\s*$/);
			}
		} else {
			next if /^\s*\#/;		# skip comments
			next if /^\s*$/;		# skip empty lines
			if (/^([0-9A-Za-z_.\-]+)\:\s*(\S.*?)\s*$/) {
				$lastkey = $notLC ? $1 : lc $1;
				if (exists $hash->{$lastkey}) {
					print "WARNING: Field \"$lastkey\" occurs more than once in \"$file\".\n";
				}
				if ($2 eq "<<") {
					$hash->{$lastkey} = "";
					$heredoc = 1;
				} else {
					$hash->{$lastkey} = $2;
				}
			} elsif (/^\s+(\S.*?)\s*$/) {
				# Old multi-line property format. Deprecated! Use heredocs instead.
				$hash->{$lastkey} .= "\n".$1;
				#print "WARNING: Deprecated multi-line format used for property \"$lastkey\" in \"$file\".\n";
			} elsif (/^([0-9A-Za-z_.\-]+)\:\s*$/) {
				# For now tolerate empty fields.
			} else {
				print "WARNING: Unable to parse the line \"".$_."\" in \"$file\".\n";
			}
		}
	}

	if ($heredoc > 0) {
		print "WARNING: End of file reached during here-document in \"$file\".\n";
	}

	return $hash;
}

=item read_properties_multival

    my $property_hash = read_properties_multival $filename;
    my $property_hash = read_properties_multival $filename, $notLC;

Reads a text file $filename and returns a ref to a hash of its
fields. See the description of read_properties_lines for more
information, with the following differences:

  Multiline values are can only be given in RFC-822 style notation,
  not with heredoc.

  No sanity-checking is performed. Lines that could not be parsed are
  silently ignored.

  Multiple occurances of a field are allowed. In this case, the value
  returned in the hash is a ref to an array of the values (in the
  order as they were encountered in $filename).

If $filename cannot be read, program will die with an error message.

=cut

sub read_properties_multival {
	my ($file) = shift;
	my ($notLC) = shift || 0;
	my ($hash, $lastkey, $lastindex);

	$hash = {};
	$lastkey = "";
	$lastindex = 0;

	open(IN,$file) or die "can't open $file: $!";
	while (<IN>) {
		next if /^\s*\#/;		# skip comments
		if (/^([0-9A-Za-z_.\-]+)\:\s*(\S.*?)\s*$/) {
			$lastkey = $notLC ? $1 : lc $1;
			if (exists $hash->{$lastkey}) {
				$lastindex = @{$hash->{$lastkey}};
				$hash->{$lastkey}->[$lastindex] = $2;
			} else {
				$lastindex = 0;
				$hash->{$lastkey} = [ $2 ];
			}
		} elsif (/^\s+(\S.*?)\s*$/) {
			$hash->{$lastkey}->[$lastindex] .= "\n".$1;
		}
	}
	close(IN);

	return $hash;
}

=item execute

    my $retval = execute $cmd;
    my $retval = execute $cmd, $quiet;

Executes $cmd as a single string via a perl system() call and returns
the exit code from it. The command is printed on STDOUT before being
executed. If $cmd begins with a # (preceeded optionally by whitespace)
it is treated as a comment and is not executed. If $quiet is false (or
not given) and the command failed, a message including the return code
is sent to STDOUT.

=cut

### execute a single command

sub execute {
	my $cmd = shift;
	my $quiet = shift || 0;
	my ($commandname);

	return if ($cmd =~ /(^\s*$)|(^\s*#)/); # Ignore empty commands and comments
	print "$cmd\n";
	system($cmd);
	$? >>= 8 if defined $? and $? >= 256;
	if ($? and not $quiet) {
		($commandname) = split(/\s+/, $cmd);
		print "### execution of $commandname failed, exit code $?\n";
	}
	return $?;
}

=item execute_script

     my $retval = execute_script $script;
     my $retval = execute_script $script, $quiet;

Executes the multiline script $script.

If $script appears to specify an interpretter (i.e., the first line
begins with #!) the whole thing is stored in a temp file which is made
chmod +x and executed. If the tempfile could not be created, the
program dies with an error message. If executing the script fails, the
tempfile is not deleted and the failure code is returned.

If $script does not specify an interpretter, each line is executed
individually. In this latter case, the first line that fails causes
further lines to not be executed and the failure code is returned.

In either case, execution is performed by Fink::Services::execute
(which see for more information, including the meaning of $quiet).

=cut

sub execute_script {
	my $script = shift;
	my $quiet = shift || 0;
	my ($retval, $cmd, $tempfile);

	$script =~ s/[\r\n]+$//s;			# Remove empty lines
	$script =~ s/^\s*//;					# Remove white spaces from the start of each line

	# If the script starts with a shell specified (e.g. #!/bin/sh), run it 
	# as a script. Otherwise fall back to the old behaviour for compatibility.
	if ($script =~ /^#!/) {
		# Put the script into a temporary file and run it.
		$tempfile = POSIX::tmpnam() or die "unable to get temporary file: $!";
		open (OUT, ">$tempfile") or die "unable to write to $tempfile: $!";
		print OUT "$script\n";
		close (OUT) or die "an unexpected error occurred closing $tempfile: $!";
		chmod(0755, $tempfile);
		$retval = execute($tempfile, $quiet);
		if ($retval == 0) {
			# Delete the temporary file, but only if it run successfully. Simplifies
			# debugging since it allows us to look at failed scripts. 
			unlink($tempfile);
		}
		return $retval;
	} elsif (defined $script and $script ne "") {
		# Execute each line as a separate command.
		foreach $cmd (split(/\n/,$script)) {
			$retval = execute($cmd, $quiet);
			if ($retval) {
				return $retval;
			}
		}
		return 0;
	} else {
		# Script is empty. We pretend successful execution.
		return 0;
	}
}

=item expand_percent

    my $string = expand_percent $template;
    my $string = expand_percent $template, \%map;


Performs percent-expansion on the given multiline $template according
to %map (if one is defined). If a line in $template begins with #
(possibly preceeded with whitespace) it is treated as a comment and no
expansion is performed on that line.

The %map is a hash where the keys are the strings to be replaced (not
including the percent char). The mapping can be recursive (i.e., a
value that itself has a percent char), and multiple substitution
passes are made to deal with this situation. Recursing is currently
limitted to a single additional level (only (up to) two passes are
made). If there are still % chars left after the recursion, that means
$template needs more passes (beyond the recursion limit) or there are
% patterns in $template that are not in %map. If either of these two
cases occurs, the program will die with an error message.

To get an actual percent char in the string, protect it as %% in
$template (similar to printf()). This occurs whether or not there is a
%map.  This behavior is implemented internally in the function, so you
should not have ('%'=>'%') in %map. Pecent-delimited percent chars are
left-associative (again as in printf()). Currently, this %% treatment
is implemented using a temporary sentinel string of "@PERCENT@", so if
$template contains @PERCENT@ that will also be replaced with %.

Expansion keys are not limitted to single letters, however, having one
expansion key that is the beginning of a longer one (d and dir) will
cause unpredictable results (i.e., "a" and "arch" is bad but "c" and
"arch" is okay). Note that no such keys are in use at this point.

=cut

sub expand_percent {
	my $s = shift;
	my $map = shift || {};
	my ($key, $value, $i, @lines, @newlines, %map, $percent_keys);

	return $s if (not defined $s);
	# Bail if there is nothing to expand
	return $s unless ($s =~ /\%/);

	%map = ( %$map, '%' => '@PERCENT@' );  # Don't touch the caller's copy
	$percent_keys = join('|', keys %map);

	# split multi lines to process each line incase of comments
	@lines = split(/\r?\n/, $s);

	foreach $s (@lines) {
		# if line is a comment don't expand
		unless ($s =~ /^\s*#/) {

			# Values for percent signs expansion may be nested
			# once, to allow e.g. the definition of %N in terms of
			# %n (used a lot for splitoffs which do stuff like
			# %N = %n-shlibs). Hence we repeate the expansion if
			# necessary.
			# Abort as soon as no substitution performed.
			for ($i = 0; $i < 2 ; $i++) {
				$s =~ s/\%($percent_keys)/$map{$1}/eg || last;
				# Abort early if no percent symbols are left
				last if not $s =~ /\%/;
			}
	
			# If ther are still unexpanded percents left, error out
			die "Error performing percent expansion: unknown % expansion or nesting too deep: \"$s\"." if $s =~ /\%/;

			# Change @PERCENT@ back to % as it should be
			$s =~ s/\@PERCENT\@/\%/g;
		}
		push(@newlines, $s);
	}

	$s = join("\n", @newlines);

	return $s;
}

=item filename

    my $file = filename $source_field;

Treats $source_field as a URL or "mirror:" construct as might be found
in Source: fields of a .info file and returns just the filename (skips
URL proto/host or mirror-type, and directory hierarchy). Note that the
presence of colons in the filename will break this function.

=cut

### isolate filename from path

sub filename {
	my ($s) = @_;

	if (defined $s and $s =~ /[\/:]([^\/:]+)$/) {
		$s = $1;
	}
	return $s;
}

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

Ask the user a yes/no question and return the logical value of the
answer. The user is prompted via STDOUT/STDIN using $prompt (which is
word-wrapped). If $default_true is true or undef, the default answer
is true, otherwise it is false. If the user returns a null string or
Fink is configured to automatically accept defaults (i.e., bin/fink
was invoked with the -y or --yes option), the default answer is
returned.

=cut

sub prompt_boolean {
	my $prompt = shift;
	my $default_value = shift;
	$default_value = 1 unless defined $default_value;
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
		$answer = <STDIN> || "";
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

=item prompt_selection
    my $answer = prompt_selection $prompt, $default, \%names, @choices;

Ask the user a multiple-choice question and return the answer. The
user is prompted via STDOUT/STDIN using $prompt (which is
word-wrapped) and a list of choices (the values of %names). The
choices are numbered (beginning with 1) and the user selects by
number. The list @choices is the keys of %names listed in the order
they are to be presented to the user, and the value returned is the
item in @choices corresponding to the choice number. If the user
returns a null string or Fink is configured to automatically accept
defaults (i.e., bin/fink was invoked with the -y or --yes option), the
answer-number $default is used.

This seems ripe for replacement by an ordered hash or an array of
array-refs ([key1,val1],[key2,val2],...) or a simple pairwise list
(key1,val1,key2,val2,...) and the actual default value instead of
default value-number (abstracting for an interface other than
numbered-choices).

=cut

sub prompt_selection {
	my $prompt = shift;
	my $default_value = shift;
	$default_value = 1 unless defined $default_value;
	my $names = shift;
	my @choices = @_;
	my ($key, $count, $answer);

	require Fink::Config;
	my $dontask = Fink::Config::get_option("dontask");

	$count = 1;
	foreach $key (@choices) {
		print "\n($count)	 ";
		if (exists $names->{$key}) {
			print $names->{$key};
		} else {
			print $key;
		}
		$count++;
	}
	print "\n\n";

	&print_breaking("$prompt [$default_value] ", 0);
	if ($dontask) {
		print "(assuming default)\n";
	} else {
		$answer = <STDIN> || "";
		chomp($answer);
		if (!$answer) {
			$answer = 0;
		}
		$answer = int($answer);
		if ($answer > 0 && $answer <= $#choices + 1) {
			return $choices[$answer-1];
		}
	}
	return $choices[$default_value-1];
}

=item version_cmp

    my $bool = version_cmp $fullversion1, $op, $fullversion2;

Compares the two debian version strings $fullversion1 and
$fullversion2 according to the binary operator $op. Each version
string is of the form epoch:version-revision (though one or more of
these components may be omitted as usual--see the Debian Policy
Manual, section 5.6.11 "Version" for more information). The operators
are those used in the debian-package world: << and >> for
strictly-less-than and strictly-greater-than, <= and >= for
less-than-or-equal-to and greater-than-or-equal-to, and = for
equal-to.

The results of the basic comparison (similar to the perl <=> and cmp
operators) are cached in a package variable so repeated queries about
the same two version strings does not require repeated parsing and
element-by-element comparison. The result is cached in both the order
the packages are given and the reverse, so these later requests can be
either direction.

=cut

# Caching the results makes fink much faster.
my %Version_Cmp_Cache = ();
sub version_cmp {
	my ($a, $b, $op, $i, $res, @avers, @bvers);
	$a = shift;
	$op = shift;
	$b = shift;
	
	if (exists($Version_Cmp_Cache{$a}{$b})) {
		$res = $Version_Cmp_Cache{$a}{$b};
	} else {
		@avers = parse_fullversion($a);
		@bvers = parse_fullversion($b);
		# compare them in version array order: Epoch, Version, Revision
		for ($i = 0; $i <= $#avers; $i++) {
			$avers[$i] = "" if (not defined $avers[$i]);
			$bvers[$i] = "" if (not defined $bvers[$i]);
			$res = raw_version_cmp($avers[$i], $bvers[$i]);
			last if $res;
		}

		$Version_Cmp_Cache{$a}{$b} = $res;
		$Version_Cmp_Cache{$b}{$a} = - $res;
	}
	
	if ($op eq "<<") {
		$res = $res < 0 ? 1 : 0;	
	} elsif ($op eq "<=") {
		$res = $res <= 0 ? 1 : 0;
	} elsif ($op eq "=") {
		$res = $res == 0 ? 1 : 0;
	} elsif ($op eq ">=") {
		$res = $res >= 0 ? 1 : 0;
	} elsif ($op eq ">>") {
		$res = $res > 0 ? 1 : 0;
	}

	return $res;
}

=begin private

=item raw_version_cmp
    my $cmp = raw_version_cmp $item1, $item2;

Compare $item1 and $item2 as debian epoch or version or revision
strings and return -1, 0, 1 as for the perl <=> or cmp operators.

=end private

=cut

sub raw_version_cmp {
	my ($a1, $b1, $a2, $b2, @ca, @cb, $res);
	$a1 = shift;
	$b1 = shift;

	while ($a1 ne "" and $b1 ne "") {
		# pull a string of non-digit chars from the left
		# compare it left-to-right, sorting non-letters higher than letters
		$a1 =~ /^(\D*)/;
		@ca = unpack("C*", $1);
		$a1 = substr($a1,length($1));
		$b1 =~ /^(\D*)/;
		@cb = unpack("C*", $1);
		$b1 = substr($b1,length($1));

		while (int(@ca) and int(@cb)) {
			$res = chr($a2 = shift @ca);
			$a2 += 256 if $res !~ /[A-Za-z]/;
			$res = chr($b2 = shift @cb);
			$b2 += 256 if $res !~ /[A-Za-z]/;
			$res = $a2 <=> $b2;
			return $res if $res;
		}
		$res = $#ca <=> $#cb;		# terminate when exactly one is exhausted
		return $res if $res;

		last unless ($a1 ne "" and $b1 ne "");

		# pull a string of digits from the left
		# compare it numerically
		$a1 =~ /^(\d*)/;
		$a2 = $1;
		$a1 = substr($a1,length($a2));
		$b1 =~ /^(\d*)/;
		$b2 = $1;
		$b1 = substr($b1,length($b2));
		$res = $a2 <=> $b2;
		return $res if $res;
	}

	# at this point, at least one of the strings is exhausted
	return $a1 cmp $b1;
}

=item latest_version

    my $latest = latest_version @versionstrings;

Given a list of one or more debian version strings, return the one
that is the highest. See the Debian Policy Manual, section 5.6.11
"Version" for more information.

=cut

sub latest_version {
	my ($latest, $v);

	$latest = shift;
	foreach $v (@_) {
		next unless defined $v;
		if (version_cmp($v, '>>', $latest)) {
			$latest = $v;
		}
	}
	return $latest;
}

=item parse_fullversion

    my ($epoch, $version, $revision) = parse_fullversion $versionstring;

Parses the given $versionstring of the form epoch:version-revision and
returns a list of the three components. Epoch and revision are each
optional and default to zero if absent. Epoch must contain only
numbers and revision must not contain any hyphens.

If there is an error parsing $versionstring, () is returned.

=cut

sub parse_fullversion {
	my $fv = shift;
	if ($fv =~ /^(?:(\d+):)?(.+?)(?:-([^-]+))?$/) {
			# not all package have an epoch
			return ($1 ? $1 : '0', $2, $3 ? $3 : '0');
	} else {
			return ();
	}
}

=item collapse_space

    my $pretty_text = collapse_space $original_text;

Collapses whitespace inside a string. All whitespace sequences are
converted to a single space char. Newlines are removed.

=cut

sub collapse_space {
	my $s = shift;
	$s =~ s/\s+/ /gs;
	return $s;
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

=item file_MD5_checksum

    my $md5 = file_MD5_checksum $filename;

Returns the MD5 checksum of the given $filename. Uses /sbin/md5 if it
is available, otherwise uses the first md5sum in PATH. The output of
the chosen command is read via an open() pipe and matched against the
appropriate regexp. If the match fails, a '-' char is returned. If the
command fails, the program dies with an error message.

=cut

sub file_MD5_checksum {
	my $filename = shift;
	my ($pid, $checksum, $name, $md5cmd, $match);

	$checksum = "-";
	if(-e "/sbin/md5") {
		$md5cmd = "/sbin/md5";
		$match = '= ([^\s]+)$';
	} else {
		$md5cmd = "md5sum";
		$match = '([^\s]*)\s*(:?[^\s]*)';
	}
	
	$pid = open(MD5SUM, "$md5cmd $filename |") or die "Couldn't run $md5cmd: $!\n";
	while (<MD5SUM>) {
		if (/$match/) {
			$checksum = $1;
		}
	}
	close(MD5SUM) or die "Error on closing pipe to $md5cmd: $!\n";

	return $checksum;
}

=item get_arch

    my $arch = get_arch;

Returns the architecture string to be used on this platform. For
example, "powerpc" for ppc.

=cut

sub get_arch {
	if(not defined $arch) {
	  $arch = `/usr/bin/uname -p`;
	  chomp $arch;
	}
	return $arch;
}

=item get_sw_vers

    my $os_x_version = get_sw_vers;

Returns OS X version (if that's what this platform appears to be, as
indicated by being able to run /usr/bin/sw_vers). The output of that
command is parsed and cached in a global configuration option in the
Fink::Config package so that multiple calls to this function do not
result in repeated spawning of sw_vers processes.

=cut

sub get_sw_vers {
	if (not defined Fink::Config::get_option('sw_vers') or Fink::Config::get_option('sw_vers') eq "0" and -x '/usr/bin/sw_vers') {
		if (open(SWVERS, "sw_vers |")) {
			while (<SWVERS>) {
				if (/^ProductVersion:\s*([^\s]+)\s*$/) {
					Fink::Config::set_options( { 'sw_vers' => $1 } );
					last;
				}
			}
			close(SWVERS);
		}
	}
	return Fink::Config::get_option('sw_vers');
}

=item get_system_perl_version

    my $perlversion = get_system_perl_version;


Returns the version of perl in that is /usr/bin/perl by running a
program with it to return its $^V variable. The value is cached, so
multiple calls to this function do not result in repeated spawning of
perl processes.

=cut

sub get_system_perl_version {
	if (not defined $system_perl_version) {
		if (open(PERL, "/usr/bin/perl -e 'printf \"\%vd\", \$^V' 2>/dev/null |")) {
			chomp($system_perl_version = <PERL>);
			close(PERL);
		}
	}
	return $system_perl_version;
}

=item get_path

    my $path_to_file = get_path $filename;

Returns the full pathname of the first executable occurance of
$filename in PATH. The correct platform-dependent pathname separator
is used. This is an all-perl routine that emulates 'which' in csh.

=cut

sub get_path {
	use File::Spec;

	my $file = shift;
	my $path = $file;
	my (@path, $base);

	### Get current user path env
	@path = File::Spec->path();

	### Get matches and return first match in order of path
	for $base (map { File::Spec->catfile($_, $file) } @path) {
		if (-x $base and !-d $base) {
			$path = $base;
			last;
		}
	}

	return $path;
}

=back

=cut

### EOF
1;
