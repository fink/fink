# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Services module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2005 The Fink Package Manager Team
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

use POSIX qw(uname tmpnam);

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
					  &read_properties_multival &read_properties_multival_var
					  &execute
					  &expand_percent
					  &filename
					  &version_cmp &latest_version &sort_versions
					  &parse_fullversion
					  &collapse_space
					  &pkglist2lol &lol2pkglist
					  &file_MD5_checksum &get_arch &get_sw_vers &enforce_gcc
					  &get_system_perl_version &get_path
					  &eval_conditional &count_files
					  &growl);
}
our @EXPORT_OK;

# non-exported package globals go here
our $arch;
our $system_perl_version;

END { }				# module clean-up code here (global destructor)

=head1 NAME

Fink::Services - functions for text processing and system interaction

=head1 SYNOPSIS

=head1 DESCRIPTION

These functions handle a variety of text (file and string) parsing and
system interaction tasks.

=head2 Functions

No functions are exported by default. You can get whichever ones you
need with things like:

    use Fink::Services '&read_config';
    use Fink::Services qw(&execute &expand_percent);

=over 4

=item read_config

    my $config = read_config $filename;
    my $config = read_config $filename, \%defaults;

Reads a fink.conf file given by $filename into a new Fink::Config
object and initializes Fink::Config globals from it. If %defaults is
given they will be used as defaults for any keys not in the config
file. The new object is returned.

=cut

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

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
	 return read_properties_lines("\"$file\"", $notLC, @lines);
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

=item read_properties_lines

    my $property_hash = read_properties_lines $filename, $notLC, @lines;

This is function is not exported. You should use read_properties_var,
read_properties, or read_properties_multival instead.

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

Multiline values (including all the lines of fields in a splitoff) are
returned as a single multiline string (i.e., with embedded \n), not as
a ref to another hash or array.

=cut

sub read_properties_lines {
	my ($file) = shift;
	# do we make the keys all lowercase
	my ($notLC) = shift || 0;
	my (@lines) = @_;
	my ($hash, $lastkey, $heredoc, $linenum);

	$hash = {};
	$lastkey = "";
	$heredoc = 0;
	$linenum = 0;

	foreach (@lines) {
		$linenum++;
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
				$heredoc++ if (/<<\s*$/ and not /^\s*#/);
			}
		} else {
			next if /^\s*\#/;		# skip comments
			next if /^\s*$/;		# skip empty lines
			if (/^([0-9A-Za-z_.\-]+)\:\s*(\S.*?)\s*$/) {
				$lastkey = $notLC ? $1 : lc $1;
				if (exists $hash->{$lastkey}) {
					print "WARNING: Repeated occurrence of field \"$lastkey\" at line $linenum of $file.\n";
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
				print "WARNING: Deprecated multi-line format used for property \"$lastkey\" at line $linenum of $file.\n";
			} elsif (/^([0-9A-Za-z_.\-]+)\:\s*$/) {
				# For now tolerate empty fields.
			} else {
				print "WARNING: Unable to parse the line \"".$_."\" at line $linenum of $file.\n";
			}
		}
	}

	if ($heredoc > 0) {
		print "WARNING: End of file reached during here-document in $file.\n";
	}

	return $hash;
}

=item read_properties_multival

    my $property_hash = read_properties_multival $filename;
    my $property_hash = read_properties_multival $filename, $notLC;

Reads a text file $filename and returns a ref to a hash of its fields,
with each value being a ref to a list of values for that field. See
the description of read_properties_multival_lines for more
information.

If $filename cannot be read, program will die with an error message.

=cut

sub read_properties_multival {
	 my ($file) = shift;
	 # do we make the keys all lowercase
	 my ($notLC) = shift || 0;
	 my (@lines);
	 
	 open(IN,$file) or die "can't open $file: $!";
	 @lines = <IN>;
	 close(IN);
	 return read_properties_multival_lines($file, $notLC, @lines);
}

=item read_properties_multival_var

    my $property_hash = read_properties_multival_var $filename, $string;
    my $property_hash = read_properties_multival_var $filename, $string, $notLC;

Parses the multiline text $string and returns a ref to a hash of its
fields, with each value being a ref to a list of values for that
field. See the description of read_properties_multival_lines for more
information. The string $filename is used in parsing-error messages
but the file is not accessed.

=cut

sub read_properties_multival_var {

	 my ($file) = shift;
	 my ($var) = shift;
	 # do we make the keys all lowercase
	 my ($notLC) = shift || 0;
	 my (@lines);
	 my ($line);

	 @lines = split /^/m,$var;
	 return read_properties_multival_lines($file, $notLC, @lines);
}

=item read_properties_multival_lines

    my $property_hash = read_properties_multival_lines $filename, $notLC, @lines;

This is function is not exported. You should use read_properties_var,
read_properties, read_properties_multival, or read_properties_multival_var 
instead.

Parses the list of text strings @lines and returns a ref to a hash of
its fields, with each value being a ref to a list of values for that
field. The string $filename is used in parsing-error messages but the
file is not accessed.

The function is similar to read_properties_lines, with the following 
differences:

  Multiline values are can only be given in RFC-822 style notation,
  not with heredoc.

  No sanity-checking is performed. Lines that could not be parsed are
  silently ignored.

  Multiple occurances of a field are allowed.

  Each hash value is a ref to a list of key values instead of a simple
  value string. The list is in the order the values appear in @lines.

=cut

sub read_properties_multival_lines {
	my ($file) = shift;
	my ($notLC) = shift || 0;
	my (@lines) = @_;
	my ($hash, $lastkey, $lastindex);

	$hash = {};
	$lastkey = "";
	$lastindex = 0;

	foreach (@lines) {
		chomp;
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

	return $hash;
}

=item execute

     my $retval = execute $script;
     my $retval = execute $script, %options;

Executes the (possibly multiline) script $script.

If $script appears to specify an interpretter (i.e., the first line
begins with #!) the whole thing is stored in a temp file which is made
chmod +x and executed. If the tempfile could not be created, the
program dies with an error message. If executing the script fails, the
tempfile is not deleted and the failure code is returned.

If $script does not specify an interpretter, each line is executed
individually. In this latter case, the first line that fails causes
further lines to not be executed and the failure code is returned.
Blank lines and lines beginning with # are ignored, and any line
ending with \ is joined to the following line.

In either case, each command to be executed (either the shell script
tempfile or individual lines of the simple script) is printed on
STDOUT before being executed by a system() call.

The optional %options are given as option=>value pairs. The following
options are known:

    quiet

        If the option 'quiet' is not given or its value is false and
        the command failed, a message including the return code is
        sent to STDOUT.

    nonroot_okay

        If the value of the option 'nonroot_okay' is true, fink was
        run with the --build-as-nobody flag, drop to user=nobody when
        running the actual commands.

    delete_tempfile

        Whether to delete temp-files that are created. The following
        values are known:

            -1    Always delete

            0 (or not passed)
                  Delete if script was successful, do not delete if it failed

            1     Never delete

=cut

sub execute {
	my $script = shift;
	my %options = ( defined $_[0] ? @_ : () );
	my ($retval, $cmd);

	# drop root if requested
	my $drop_root = $options{'nonroot_okay'} && Fink::Config::get_option("build_as_nobody") == 1;
	if ($drop_root && $< != 0) {
		print "Fink cannot switch users when not running as root.\n";
		return 1;
	}

	# to drop root, we wrap the given $script in a formal (with #!
	# line) perl script that passes the original back to ourselves
	# but omitting the nonroot_okay flag
	if ($drop_root) {
		my $wrap = <<EOSCRIPT;
#!/usr/bin/perl
		use Fink::Services qw(execute);
		{
			local \$/;
			\$script = <DATA>;
		}
EOSCRIPT
		$script = $wrap .
			'exit &execute(' .
			join ( ', ',
				   '$script',
				   map { "$_ => $options{$_}" } grep { !/nonroot_okay/ } keys %options
				 ) .
			 ");\n" .
			 "__DATA__\n" .
			 $script;
	}

	# preprocess the script, making executable tempfile if necessary
	my $is_tempfile = &prepare_script(\$script);
	return 0 if not defined $script;

	# Execute each line as a separate command.
	foreach my $cmd (split(/\n/,$script)) {
		print "sudo -u nobody sh -c $cmd\n" unless $options{'quiet'};
		$drop_root
			? system(qw/ sudo -u nobody sh -c /, $cmd)
			: system($cmd);
		$? >>= 8 if defined $? and $? >= 256;
		if ($?) {
			my $rc = $?;
			if (not $options{'quiet'}) {
				my ($commandname) = split(/\s+/, $cmd);
				print "### execution of $commandname failed, exit code $rc\n";
			}	
			if (defined $options{'delete_tempfile'} and $options{'delete_tempfile'} == 1) {
				# probably keep tempfile around (to aide debugging)
				unlink($script) if $is_tempfile;
			}
			return $rc;  # something went boom; give up now
		}
	}

	# everything was successful so probably delete tempfile
	if (!defined $options{'delete_tempfile'} or $options{'delete_tempfile'} != -1) {
		unlink($script) if $is_tempfile;
	}
	return 0;
}

=item prepare_script

	my $is_tempfile = prepare_script \$script;

Given a ref to a scalar containing a (possibly multiline) script,
parse it according to the *Script field rules and leave it in
ready-to-run form. There will be no trailing newline. Note that the
scalar $script is changed! Save a copy if you want to see the
original.

If the first line begins with #! (with optional leading whitespace),
dump the whole script (with leading whitespace on the #! line
removed) into a tempfile. Die if there was a problem creating the
tempfile. Return true and leave $script set to the fullpathname of the
tempfile.

Otherwise, remove leading whitespace from each line, join consecutive
lines that end with \ as a continuation character, remove blank lines
and lines beginning with #. Return false and leave $script set to the
parsed script. If there was nothing left after parsing, $script is set
to undef.

=cut

# keep this function is separate (not pulled into execute*()) so we
# can write tests for it

sub prepare_script {
	my $script = shift;

	die "prepare_script was not passed a ref!\n" if not ref $script;
	return 0 if not defined $$script;

	# If the script starts with a shell specified, dump to a tempfile
	if ($$script =~ /^\s*\#!/) {
		$$script =~ s/^\s*//s;  # Strip leading whitespace before "#!" magic
		$$script .= "\n" if $$script !~ /\n$/;  # require have trailing newline

		# Put the script into a temporary file
		my $tempfile = tmpnam() or die "unable to get temporary file: $!";
		open (OUT, ">$tempfile") or die "unable to write to $tempfile: $!";
		print OUT $$script;
		close (OUT) or die "an unexpected error occurred closing $tempfile: $!";
		chmod(0755, $tempfile);

		# tempfile filename is handle to whole script
		$$script = $tempfile;
		return 1;
	}

	### No interpretter is specified so process for line-by-line system()
	$$script =~ s/^\s*//mg;          # Strip leading white space on each line
	$$script =~ s/\s*\\\s*\n/ /g;    # Rejoin continuation/multiline commands
	$$script =~ s/^\#.*?($)\n?//mg;  # remove comment lines
	$$script =~ s/^\s*($)\n?//mg;    # remove blank lines
	chomp $$script;                  # always remove trailing newline 

	# sanity check
	if ($$script =~ /\\$/s) {
		die "illegal continuation at end of script: \n", $$script, "\n";
	}

	$$script = undef if !length $$script;
	return 0;  # $$script is still the real thing, not a tempfile handle
}

=item expand_percent

    my $string = expand_percent $template;
    my $string = expand_percent $template, \%map;
    my $string = expand_percent $template, \%map, $err_info;

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
cases occurs, the program will die with an error message. If given,
$err_info will be appended to this error message.

To get an actual percent char in the string, protect it as %% in
$template (similar to printf()). This occurs whether or not there is a
%map.  This behavior is implemented internally in the function, so you
should not have ('%'=>'%') in %map. Pecent-delimited percent chars are
left-associative (again as in printf()).

Expansion keys are not limitted to single letters, however, having one
expansion key that is the beginning of a longer one (d and dir) will
cause unpredictable results (i.e., "a" and "arch" is bad but "c" and
"arch" is okay).

Curly-braces can be used to explicitly delimit a key. If both %f and
%foo exist, one should use %{foo} and %{f} to avoid ambiguity.

=cut

sub expand_percent {
	my $s = shift;
	my $map = shift || {};
	my $err_info = shift;
	my ($key, $value, $i, @lines, @newlines, %map, $percent_keys);

	return $s if (not defined $s);
	# Bail if there is nothing to expand
	return $s unless ($s =~ /\%/);

	# allow %{var} to prevent ambiguity
	# work with a copy of $map so not touch caller's data
	%map = map { ( $_     => $map->{$_} ,
				   "{$_}" => $map->{$_}
				 ) } keys %$map;

	$percent_keys = join('|', map "\Q$_\E", keys %map);

	# split multi lines to process each line incase of comments
	@lines = split(/\r?\n/, $s);

	foreach $s (@lines) {
		# if line is a comment don't expand
		unless ($s =~ /^\s*#/) {

			if (keys %map) {
				# only expand using $map if one was passed

				# Values for percent signs expansion
				# may be nested once, to allow e.g.
				# the definition of %N in terms of %n
				# (used a lot for splitoffs which do
				# stuff like %N = %n-shlibs). Hence we
				# repeat the expansion if necessary.
				# Do not handle %% => % at this point.
				# The regex for this hairy; to explain
				# REGEX look at thereturn value of
				# YAPE::Regex::Explain->new(REGEX)->explain
				# Abort as soon as no subst performed.
				for ($i = 0; $i < 2 ; $i++) {
					$s =~ s/(?<!\%)\%((?:\%\%)*)($percent_keys)/$1$map{$2}/g || last;
					# Abort early if no percent symbols are left
					last if not $s =~ /\%/;
				}
			}

			# The presence of a sequence of an odd number
			# of percent chars means we have unexpanded
			# percents besides (%% => %) left. Error out.
			if ($s =~ /(?<!\%)(\%\%)*\%(?!\%)/) {
				my $errmsg = "Error performing percent expansion: unknown % expansion or nesting too deep: \"$s\"";
				$errmsg .= " ($err_info)" if defined $err_info;
				$errmsg .= "\n";
				die $errmsg;
			}
			# Now handle %% => %
			$s =~ s/\%\%/\%/g;
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

	return undef if (not defined $a or not defined $op or not defined $b);

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
	} elsif ($op eq "<=>") {
	} else {
		warn "Unknown version comparison operator \"$op\"\n";
	}

	return $res;
}

=item raw_version_cmp

    my $cmp = raw_version_cmp $item1, $item2;

This is function is not exported. You should use version_cmp instead.

Compare $item1 and $item2 as debian epoch or version or revision
strings and return -1, 0, 1 as for the perl <=> or cmp operators.

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

### Do not change API! This is used by FinkCommander (fpkg_list.pl)

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

=item sort_versions {

	my @sorted = sort_versions @versionstrings;

Given a list of one or more debian version strings, return the list
sorted lowest-to-highest. See the Debian Policy Manual, section 5.6.11
"Version" for more information.

=cut

sub sort_versions {
	sort { version_cmp($a,"<=>",$b) } @_;
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

=item pkglist2lol

	my $struct = pkglist2lol $pkglist;

Takes a string representing a pkglist field and returns a ref to a
list of lists of strings representing each pkg. The elements of the
list referenced by $struct are joined by logical AND (commas in
$pkglist). The pkgs in each list referenced by an element of @$srtuct
are joined by logical OR (delimited by vertical-bar within a comma-
delimited cluster). Leading and trailing whitespace are removed from
each pkg, and null pkgs are removed. A ref to an array is always
returned, though it may contain no elements. Each element of @$struct
is always an array ref, even if that list only has one element; none
of these will have no elements. A new $struct is returned on each
call, so changing one returned value does not afect the data returned
by another call or the underlying data.

=cut

sub pkglist2lol {
	my $pkglist = shift;
	my @lol = ();

	return [] unless defined $pkglist && length $pkglist;
	foreach (split /\s*,\s*/, $pkglist) {  # take each OR cluster
		# store ref to list of non-null pkgs
		my @or_cluster = grep {length} split /\s*\|\s*/, $_;
		push @lol, \@or_cluster if @or_cluster;
	}

	return \@lol;
}

=item lol2pkglist

	my $pkglist = lol2pkglist $struct;

Given a ref to a list of lists of pkgs, reconstitute the Debian
pkglist string. Blank/whitespace-only/undef elements are removed. The
return is always defined (though it may be null). $struct is not
modified.

=cut

sub lol2pkglist {
	my $struct = shift;
	my $pkglist = "";

	return "" unless defined $struct && @$struct;

	my $or_cluster;

	foreach (@$struct) {                          # take each OR cluster
		next unless defined $_ && @$_;            # skip empty clusters
		$or_cluster = join " | ", grep {defined and length} @$_;
		if (defined $or_cluster && length $or_cluster) {
			$pkglist .= ", " if length $pkglist;
			$pkglist .= $or_cluster;              # join clusters by AND
		}
	}

	return $pkglist;
}

=item file_MD5_checksum

    my $md5 = file_MD5_checksum $filename;

Returns the MD5 checksum of the given $filename. Uses /sbin/md5 if it
is available, otherwise uses the first md5sum in PATH. The output of
the chosen command is read via an open() pipe and matched against the
appropriate regexp. If the command returns failure or its output was
not in the expected format, the program dies with an error message.

=cut

sub file_MD5_checksum {
	my $filename = shift;
	my ($pid, $checksum, $md5cmd, $match);

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
	close(MD5SUM) or die "Error on closing pipe  $md5cmd: $!\n";

	if (not defined $checksum) {
		die "Could not parse results of '$md5cmd $filename'\n";
	}

	return $checksum;
}

=item get_arch

    my $arch = get_arch;

Returns the architecture string to be used on this platform. For
example, "powerpc" for ppc.

=cut

sub get_arch {
	if(not defined $arch) {
		foreach ('/usr/bin/uname', '/bin/uname') {
			# check some common places (why aren't we using $ENV{PATH}?)
			if (-x $_) {
				chomp($arch = `$_ -p 2>/dev/null`);
				chomp($arch = `$_ -m 2>/dev/null`) if ($arch eq "");
				last;
			}
		}
		if (not defined $arch) {
			die "Could not find an 'arch' executable\n";
		}
	}
	return $arch;
}

=item enforce_gcc

	my $gcc = enforce_gcc($message);
	my $gcc = enforce_gcc($message, $gcc_abi);

Check to see if the gcc version optionally supplied in $gcc_abi is the
same as the default GCC ABI for the installed version of Mac OS X or Darwin.
If it is not, we return the value for the deafult GCC ABI.

If it is, or if $gcc_abi is not supplied, then we check to see if the
gcc version obtained from /usr/sbin/gcc_select agrees with the expected 
(default) gcc version corresponding to the installed version of
Mac OS X or Darwin.  If the versions agree, the common value is returned.
If they do not agree, we print $message and exit fink.

The strings CURRENT_SYSTEM, INSTALLED_GCC, EXPECTED_GCC, and 
GCC_SELECT_COMMAND within $message are converted to appropriate values.

Sample message:

This package must be compiled with GCC EXPECTED_GCC, but you currently have
GCC INSTALLED_GCC selected.  To correct this problem, run the command:

    sudo gcc_select GCC_SELECT_COMMAND

(You may need to install a more recent version of the Developer Tools to be 
able to do so.)

=cut

sub enforce_gcc {
	my $message = shift;
	my $gcc_abi = shift;
	my ($gcc, $gcc_select, $gcc_command, $current_system);
	my ($dummy, $darwin_version);

# Note: we no longer support 10.1 or 10.2-gcc3.1 in fink, we don't
# specify default values for these.

	my %osx_default = ('10.2' => '3.3', '10.3' => '3.3', '10.4' => '4.0.0');
	my %darwin_default = ('6' => '3.3', '7' => '3.3', '8' => '4.0.0');
	my %gcc_name = ('2.95.2' => '2', '2.95' => '2', '3.1' => '3', '3.3' => '3.3', '4.0.0' => '4.0');
	my %gcc_abi_default = ('2.95' => '2.95', '3.1' => '3.1', '3.3' => '3.3', '4.0.0' => '3.3');

	my $sw_vers = get_sw_vers();
	if ($sw_vers ne 0) {
		$current_system = "Mac OS X $sw_vers";
		$sw_vers =~ s/^(\d*\.\d*).*/${1}/;
		$gcc = $osx_default{$sw_vers};
	} else {
        ($dummy,$dummy,$darwin_version) = uname();
		$current_system = "Darwin $darwin_version";
		$darwin_version =~ s/^(\d*).*/${1}/;
		$gcc = $darwin_default{$darwin_version};
	}

	if (defined $gcc_abi) {
		if ($gcc_abi_default{$gcc} !~ /^$gcc_abi/) {
			return $gcc_abi_default{$gcc};
		}
	}

	chomp($gcc_select = `gcc_select`);
	if (not $gcc_select =~ s/^.*gcc version (\S+)\s+.*$/$1/gs) {
		$gcc_select = 'an unknown version';
	}

	$gcc_command = $gcc_name{$gcc};

    $message =~ s/CURRENT_SYSTEM/$current_system/g;
	$message =~ s/INSTALLED_GCC/$gcc_select/g;
	$message =~ s/EXPECTED_GCC/$gcc/g;
	$message =~ s/GCC_SELECT_COMMAND/$gcc_command/g;

    ($gcc_select =~ /^$gcc/) or die($message);

	return $gcc;

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

=item count_files

    my $number_of_files = &count_files($path, $regexp);

Returns the number of files in $path. If $regexp is set only 
files matching the regexp are returned.

=cut

sub count_files {
	my $path = shift;
	my $regexp = shift || undef;
	my $numoffiles;
	
	opendir(DH, $path) or die "Couldn't open directory '$path'";
	if ($regexp) {
		$numoffiles = grep(/$regexp/, readdir(DH));
	}
	else {
		# only count real files
		$numoffiles = grep(!/^\.{1,2}$/, readdir(DH));
	}
	closedir DH;
	return $numoffiles;
}

=item eval_conditional

    my $bool = &eval_conditional($expr, $where);

Evaluates the logical expression passed as a string in $expr and
returns its logical value. If there is a parsing error, abort and
print a message (including $where) is printed. Two syntaxes are
supported:

=over 4

string1 op string2

=over 4

The two strings are compared using one of the operators defined as a
key in the %compare_subs package-global. The three components may be
separated from each other by "some whitespace" for legibility.

=back

string

=over 4

"False" indicates the string is null (has no non-whitespace
characters). "True" indicates the string is non-null.

=back

=back

Leading and trailing whitespace is ignored. The strings themselves cannot
contain whitespace or any of the op operators (no quoting, delimiting,
or protection syntax is implemented).

=cut

# need some variables, may as well define 'em here once
our %compare_subs = ( '>>' => sub { $_[0] gt $_[1] },
					  '<<' => sub { $_[0] lt $_[1] },
					  '>=' => sub { $_[0] ge $_[1] },
					  '<=' => sub { $_[0] le $_[1] },
					  '='  => sub { $_[0] eq $_[1] },
					  '!=' => sub { $_[0] ne $_[1] }
					);
our $compare_ops = join "|", keys %compare_subs;

sub eval_conditional {
	my $expr = shift;
	my $where = shift;

	if ($expr =~ /^\s*(\S+)\s*($compare_ops)\s*(\S+)\s*$/) {
		# syntax 1: (string1 op string2)
#		print "\t\ttesting syntax 1 '$1' '$2' '$3'\n";
		return $compare_subs{$2}->($1,$3);
	} elsif ($expr =~ /^\s*\S+\s*$/) {
		# syntax 2: (string): true if string is non-null
#		print "\t\ttesting syntax 2 '$expr': non-null\n";
		return 1;
	} elsif ($expr =~ /^\s*$/ ) {
		# syntax 2: (string): false if string is null
#		print "\t\ttesting syntax 2 '$expr': null\n";
		return 0;
	} else {
		die "Error: Invalid conditional expression \"$expr\"\nin $where.\n";
	}
}


=item growl

    growl($notificationName, $notificationTitle, $notificationDescription);

Notifies the system that $notificationName event occurred, if Growl is
installed.

Currently available notifications used by fink are:

=over 4

=item packageInstallationPassed

One or more packages was successfully installed.

=item packageInstallationFailed

One or more packages failed to install.

=item packageRemovalPassed

One or more packages was successfully removed.

=item packageRemovalFailed

One or more packages failed to be removed.

=back

=cut

sub growl {
	eval {
		require Mac::Growl;
	};
	return undef if ($@);
	my ($notificationName, $notificationTitle, $notificationDescription) = @_;

	my @events = qw(
		finkPackageInstallationPassed
		finkPackageInstallationFailed
		finkPackageRemovalPassed
		finkPackageRemovalFailed
	);

	unless (grep(/^${notificationName}$/, @events)) {
		warn "unknown notification $notificationName\n";
		return undef;
	}

	eval {
		Mac::Growl::RegisterNotifications("Fink", \@events, \@events);
		Mac::Growl::PostNotification("Fink", $notificationName, $notificationTitle, $notificationDescription);
	};

	return 1;
}

=back

=cut

### EOF
1;
