
use strict;
use Data::Dumper;

my $source = shift || "crap";

die "'$source' not found or empty\n" unless -f $source && -s $source;

my $line = 0;
open IN,$source;
while ( <IN> )
{
	++$line;
	print;
	last if /^Slice/;
}

my $slices = partition_input( $line );
foreach my $slice ( @$slices )
{
	foreach my $line ( @{$slice->{lines}} )
	{
		print $line, "\n";
	}
	#print Data::Dumper->Dump( [$slice] );
}
exit;

sub partition_input {
my ($fileLine) = @_;

use constant Slice 	=> 0;
use constant Section 	=> 1;

my @results;
	my $currentSlice;
	my $inProcess;
	while ( <IN> )
	{
		++$line;
		chomp;
		my @vals = split ',';
		if ( (not defined $currentSlice) || ($currentSlice != $vals[Slice]))
		{
			fixupSlice( $inProcess ) if $inProcess ;
			$inProcess = { 
				"lines" => [],
				"offsets" => {
					"origin" => $line,
					"0" => {},
					"1" => {},
					"2" => {},
				},
			};
			push @results, $inProcess;
			$currentSlice = $vals[Slice];
		}

		push @{$inProcess->{lines}}, $_;
		my $tag = "$vals[Section]";
		{
			$tag = 0, last if $tag <= 0;
			$tag = 1, last if $tag == 1;
			$tag = 2;
		}
		my $offset = $inProcess->{offsets}->{$tag};
		$offset->{start} = $line unless $offset->{start};
		$offset->{end} = $line;

	}
	fixupSlice( $inProcess ) if $inProcess ;
	\@results;
}

sub fixupSlice {
my ($slice) = @_;
#print Data::Dumper->Dump( [$slice] );
	my $lines = $slice->{lines};
	my $offsets = $slice->{offsets};
	my $origin = $offsets->{origin};

# append close to last line of 'pre' section
	my $lineOffset = $offsets->{0}->{end};
	my $line = $lines->[$lineOffset-$origin];
	my @vals = split ",",$line;
	$line =~ s/,$//;
	$line = $line . ",$vals[-1],";
	$lines->[$lineOffset-$origin] = $line;

# fixup exdiv line
	my $startMax = $lineOffset = $offsets->{1}->{start};
	$line = $lines->[$lineOffset-$origin];
	$line =~ s/,$//;
	$line .= ",\"=INDIRECT(ADDRESS(ROW()-1,COLUMN()))-G$lineOffset\""; # add delta column
	$line .= ",=I$lineOffset\/C$lineOffset,";	# add ratio column
	$lines->[$lineOffset-$origin] = $line;

	my $rowOffset = 1;
	foreach my $lineOffset ( $offsets->{2}->{start} .. $offsets->{2}->{end} )
	{
		++$rowOffset;
		$line = $lines->[$lineOffset-$origin];
		$line =~ s/,$//;
		$line .= ",\"=INDIRECT(ADDRESS(ROW()-$rowOffset,COLUMN()))-G$lineOffset\""; # add delta column
		$line .= ",=I$lineOffset\/C$lineOffset,";	# add ratio column
		$line .= "=MAX(J$startMax\:J$lineOffset),"
			if $lineOffset == $offsets->{2}->{end};
		$lines->[$lineOffset-$origin] = $line;
	}
	#	print Data::Dumper->Dump( [$slice] );
}	
