
use strict;
use Data::Dumper;

# Dividend history format, c&p from nasdaq.com, no header, convert tabs to commas
my $priceTemplate = 'SYM-Pricing.csv';
my $divTemplate = 'SYM-Distributions.csv';
my $sym = shift || 'Usb';
my $preRange = 3;
my $postRange = 5;
my $divMultiple = 2;

use constant PriceDate 	=> 0;
use constant BarNumber 	=> 1;
use constant BarIndex 	=> 2;
use constant PriceTickRange 	=> 3;
use constant PriceOpen 	=> 4;
use constant PriceHigh 	=> 5;
use constant PriceLow 	=> 6;
use constant PriceClose => 7;
use constant PriceVol 	=> 8;

print "Symbol, PreDayRange, PostDayRange, DivMultiple\n";
print "$sym,$preRange,$postRange,$divMultiple\n";

my $priceSource = $priceTemplate;
$priceSource =~ s/SYM/$sym/;
my $divSource = $divTemplate;
$divSource =~ s/SYM/$sym/;

my $divInfo = loadDiv( $divSource );
#print Data::Dumper->Dump( [$divInfo] );
my ($priceInfo,$divIndex) = loadPricing( $priceSource, $divInfo );
#print Data::Dumper->Dump( [$priceInfo] );
#print Data::Dumper->Dump( [$divIndex] );
my $pricingRange = getPriceRange( $divIndex, $preRange, $postRange, scalar(@$priceInfo)-1 ); 
#print Data::Dumper->Dump( [$pricingRange] );
my $correlated = correlate( $priceInfo, $pricingRange, $divInfo );
#print Data::Dumper->Dump( [$correlated] );
report( $correlated );
exit;

sub report {
my ($data) = @_;

use constant Pre 	=> 0;
use constant ExDiv 	=> 1;
use constant Post 	=> 2;
	#print Data::Dumper->Dump( [$data] );
	print "Slice,Section,Div,Date,Open,High,Low,Close,Post Deltas,Div Ratios,Max Ratio\n"; 
	my $slice = 0;
	my $portion = Pre;
	my $print = sub { my ($slab,$section,$vals,$amount,$rowBack) = @_;
			my $rowLine = "";
			$rowLine = "INDIRECT(ADDRESS(ROW()-$rowBack,COLUMN()))-G1" if 0 && $rowBack;
			print 
			$slab,
			",",
			$section,
			",",
			$amount,
			",",
			$vals->[PriceDate],
			",",
			$vals->[PriceOpen],
			",",
			$vals->[PriceHigh],
			",",
			$vals->[PriceLow],
			",",
			$vals->[PriceClose],
			",",
			$rowLine,
			"\n";
	};

	foreach my $blob ( @$data )
	{
		++$slice;
		my $portion = Pre;
		#use constant PriceDate 	=> 0;
		#use constant PriceOpen 	=> 4;
		#use constant PriceHigh 	=> 5;
		#use constant PriceLow 	=> 6;
		#use constant PriceClose => 7;
		#use constant PriceVol 	=> 8;
		
		my $amount = $blob->{amount};
		#print Data::Dumper->Dump( [$blob] );
		my $section = $blob->{preSection};
		my $row = 0;
		foreach my $dayVals ( @$section )
		{
			$print->( $slice,$portion,$dayVals,$amount,$row );
		}

		$portion = ExDiv;
		$print->( $slice,$portion,$blob->{exDiv},$amount,++$row );
		$portion = Post;
		$section = $blob->{postSection};
		foreach my $dayVals ( @$section )
		{
			$print->( $slice,$portion,$dayVals,$amount,++$row );
		}
	}
}

sub correlate {
my ($priceInfo, $pricingRange, $divInfo ) = @_;
my @results;

	foreach my $range ( @$pricingRange )
	{
		my $exdivRange = {
			preSection => [],
			exDiv => {},
			postSection => [],
			amount	=> $range->{amount},
			};
		$exdivRange->{amount} =~ s/\$//;
		push @results,$exdivRange;

		my $activeSection = $exdivRange->{preSection};
		my $divTarget = 0;
		foreach my $index ( $range->{pre} .. $range->{post} )
		{
			my $pricing = $priceInfo->[$index];
			if ($index == $range->{exdiv}) {
				$exdivRange->{exDiv} = $pricing;
				$activeSection = $exdivRange->{postSection};
				next;
			}
			push @$activeSection, $pricing;

		}
	}
	\@results;
}

sub makeDateKey {
my ($date) = @_;
	my ($month, $day, $year) = split '/', $date;
	my $key = sprintf( "$year%02d%02d", $month, $day );
	return $key;
}

sub getPriceRange {
my ($divIndex,$preRange,$postRange, $endPriceRange ) = @_;
my @ranges;

	my @indices = sort { $a cmp $b } keys %$divIndex;
	--$postRange;	# exdiv is part of postrange;
	foreach my $priceIndex ( @indices )
	{
		my $divIndexAmount = $divIndex->{$priceIndex};
		my $exdiv = $divIndexAmount->{index};
		my $pre = $exdiv-$preRange;
		$pre = 0 if $pre < 0;
		my $post = $exdiv+$postRange;
		$post = $endPriceRange if $post > $endPriceRange;
		push @ranges, {
			pre => $pre,
			exdiv => $exdiv,
			post => $post,
			amount => $divIndexAmount->{amount},
		};
	}
	\@ranges;
}

sub loadPricing {
my ($source, $divHash ) = @_;
my @pricing;
my %divIndex;

	die( "Pricing file '$source' not found or empty\n" )
		unless -f $source && -s $source;
	open IN,$source;
	my $hdr = <IN>;
	chomp $hdr;

	my $i = 0;
	while ( <IN> )
	{
		chomp;
		my @vals = split ',';
		my $key = makeDateKey( $vals[0] );
		#print "$vals[0] .. $key\n";
		push @pricing, \@vals;
		my $divInfo = $divHash->{$key};
		$divIndex{$key} = {index=>$i, amount=>$divInfo->{Amount} } if $divInfo;
		++$i;
	}
	(\@pricing, \%divIndex);
}


sub loadDiv {
my ($source) = @_;

use constant ExDate 	=> 0;
use constant Type 	=> 1;
use constant Amount 	=> 2;
use constant DeclDate 	=> 3;
use constant RecDate 	=> 4;
use constant PayDate 	=> 5;

my %results;

	die( "Distribution file '$source' not found or empty\n" )
		unless -f $source && -s $source;
	open IN,$source;
	#my $hdr = <IN>;
	#chomp $hdr;

	while ( <IN> )
	{
		chomp;
		my @vals = split ',';
		my $key = makeDateKey( $vals[ExDate] );
		die ( "Duplicated exdiv date $key\n" )
			if $results{$key};
		$results{$key} = {
			"Date" => $vals[ExDate],
			"Amount" => $vals[Amount],
			};
	}
	\%results;	

}

