
use strict;
use Data::Dumper;

my $source = shift || "crap";

die "'$source' not found or empty\n" unless -f $source && -s $source;

use constant ID 	=> 0;
use constant Ticker 	=> 1;
use constant ExdivId 	=> 2;
use constant Day 	=> 3;
use constant Div 	=> 4;
use constant Date 	=> 5;
use constant Open 	=> 6;
use constant High 	=> 7;
use constant Low 	=> 9;
use constant Close 	=> 10;

my $lineNum = 0;
open IN,$source;
while ( <IN> )
{
	next unless /^ID/;
	chomp;
	++$lineNum;
	print "$_,Delta,Ratio,MaxRatio\n";
	last;
}

my $slices = partition_input( $lineNum );
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
		++$fileLine;
		chomp;
		my @vals = split ',';
		if ( (not defined $currentSlice) || ($currentSlice != $vals[ExdivId]))
		{
			fixupSlice( $inProcess ) if $inProcess ;
			$inProcess = { 
				"lines" => [],
				"offsets" => {
				"origin" => $fileLine,
				"0" => {},
				"1" => {},
				"2" => {},
				},
			};
			push @results, $inProcess;
			$currentSlice = $vals[ExdivId];
		}

		push @{$inProcess->{lines}}, $_;
		my $tag = "$vals[Day]";
		{
			$tag = 0, last if $tag <= 0;
			$tag = 1, last if $tag == 1;
			$tag = 2;
		}
		my $offset = $inProcess->{offsets}->{$tag};
		$offset->{start} = $fileLine unless $offset->{start};
		$offset->{end} = $fileLine;

	}
	fixupSlice( $inProcess ) if $inProcess ;
	\@results;
}

#use constant ID 	=> 0;
#use constant Ticker 	=> 1;
#use constant ExdivId 	=> 2;
#use constant Day 	=> 3;
#use constant Div 	=> 4;
#use constant Date 	=> 5;
#use constant Open 	=> 6;
#use constant High 	=> 7;
#use constant Low 	=> 9;
#use constant Close 	=> 10;
#
sub fixupSlice {
my ($slice) = @_;
	
	my $deltaColTemplate = "\"=INDIRECT(ADDRESS(ROW()-RowOffset,COLUMN()))-ILineOffset\""; 
	my $ratioColTemplate = "=KLineOffset\/ELineOffset";	

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

	my $rowOffset = 1;

	my $deltaCol = $deltaColTemplate;
	$deltaCol =~ s/RowOffset/$rowOffset/;
	$deltaCol =~ s/LineOffset/$lineOffset/;
	$line .= ",$deltaCol";

	my $ratioCol = $ratioColTemplate;
	$ratioCol =~ s/LineOffset/$lineOffset/g;
	$line .= ",$ratioCol";		# =K$lineOffset\/E$lineOffset,";	# add ratio column
	$lines->[$lineOffset-$origin] = $line;

	foreach my $lineOffset ( $offsets->{2}->{start} .. $offsets->{2}->{end} )
	{
		++$rowOffset;
		$line = $lines->[$lineOffset-$origin];
		$line =~ s/,$//;

		$deltaCol = $deltaColTemplate;
		$deltaCol =~ s/RowOffset/$rowOffset/;
		$deltaCol =~ s/LineOffset/$lineOffset/;
		$line .= ",$deltaCol"; # \"=INDIRECT(ADDRESS(ROW()-$rowOffset,COLUMN()))-I$lineOffset\""; # add delta column

		$ratioCol = $ratioColTemplate;
		$ratioCol =~ s/LineOffset/$lineOffset/g;
		$line .= ",$ratioCol";		# =K$lineOffset\/E$lineOffset,";	# add ratio column

		$line .= ",=MAX(L$startMax\:L$lineOffset),"
			if $lineOffset == $offsets->{2}->{end};
		$lines->[$lineOffset-$origin] = $line;
	}
	#	print Data::Dumper->Dump( [$slice] );
}	
