
use strict;
use Data::Dumper;
use Getopt::Long;
use 5.010;

=pod
Find 
	1.) the lowest price per day of an issue within an x day window from the exdiv date, inclusive.
	2.) the first day if any, within that window where the low is below a specified ratio of the div from the t-1 closing price.
	3.) the highest price per day following item 2, within y day window from that day.
=cut

my %config = (
	help => 0,
	buyRange => 2,
	sellRange => 10,
	divMultiple => 1.25,
	sellOffset => 0,
	lowBasedSell => 0,
	raw => 0,
	cfg => 0,
);
GetOptions( \%config,
	"help!",
	"buyRange=i",
	"sellRange=i",
	"divMultiple=f",
	"sellOffset=f",
	"lowBasedSell!",
	"raw!",
	"cfg!",
);
Usage( "" ) if $config{help};
#print Data::Dumper->Dump( [%config] );
Usage( "lowBasedSell needs sellOffset" )
	if $config{lowBasedSell} and ($config{sellOffset} == 0);

# Dividend history format, c&p from nasdaq.com, no header, convert tabs to commas
my $priceTemplate = 'SYM-Pricing.csv';
my $divTemplate = 'SYM-Distributions.csv';
my $sym = shift;
Usage( "Need symbol" ) unless $sym;

use constant PriceDate 	=> 0;
use constant BarNumber 	=> 1;
use constant BarIndex 	=> 2;
use constant PriceTickRange 	=> 3;
use constant PriceOpen 	=> 4;
use constant PriceHigh 	=> 5;
use constant PriceLow 	=> 6;
use constant PriceClose => 7;
use constant PriceVol 	=> 8;

{
my $ticker = $sym;
my $cfg = \%config;
	sub buyInCfg {
		print "Sym, BuyWindow, SellWindow, DivMutiple, SellOffset, LowBaseSellPrice\n";
		print "$ticker",
			",$cfg->{buyRange}",
			",$cfg->{sellRange}",
			",$cfg->{divMultiple}",
			",$cfg->{sellOffset}",
			",$cfg->{lowBasedSell}",
			"\n"
			;
		
	}
}

{
my $id = 0;
my $hdrPrinted = 0;
my $ticker = $sym;
	sub buyInRawData{ 
		my ($exdivId,$day,$vals,$div) = @_;
		print( "ID,Ticker,ExdivId,Day,Date,Open,High,Low,Close\n" ), $hdrPrinted = 1
			unless $hdrPrinted == 1;
		print( ++$id,
			",",
			$ticker,
			",",
			$exdivId,
			",",
			$day,
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
			"\n");
	};
}

{
my $id = 0;
my $hdrPrinted = 0;
my $ticker = $sym;
	sub buyInOutline{ 
		my ($exdivId,$vals) = @_;
		print( 	"ID,",
			"Ticker,",
			"ExdivId,",
			"Div,",
			"ExdivDate,",
			"T-1_Close,",
			"BuyDivRatio,",
			"BuyTarget,",
			"SellOffset,",
			"SellTarget,",
			"MaxLow,",
			"MaxHigh,",
			"BuyDay,",
			"SellDay",
			",BuyCushion",
			",SellCushion",
			",Buy2High",
			",Captured",
			"\n" ), $hdrPrinted = 1
			unless $hdrPrinted;

		#print Data::Dumper->Dump( [$vals] );
		my $buyDiff = sprintf( "%0.2f", $vals->{firstBuyDay} ? $vals->{buyTarget}  - $vals->{maxLow} : 0);
		my $sellDiff = sprintf( "%0.2f", $vals->{firstSellDay} ? $vals->{maxHigh} - $vals->{sellTarget} : 0);
		my $buy2High = sprintf( "%0.2f", $vals->{firstBuyDay} ? $vals->{maxHigh} - $vals->{buyTarget} : 0);
		my $captured = sprintf( "%0.2f", ($vals->{firstBuyDay} and $vals->{firstSellDay}) ?  $vals->{sellTarget} - $vals->{buyTarget} : 0);
		print( ++$id,
			",",
			$ticker,
			",",
			$exdivId,
			",",
			$vals->{divAmount},
			",",
			$vals->{tm1_pricing}->[PriceDate],
			",",
			sprintf( "%0.2f", $vals->{tm1_pricing}->[PriceClose]),
			",",
			$config{divMultiple},
			",",
			sprintf( "%0.2f",$vals->{buyTarget}),
			",",
			$config{sellOffset},
			",",
			sprintf( "%0.2f", $vals->{sellTarget}),
			",",
			sprintf( "%0.2f",$vals->{maxLow}),
			",",
			sprintf( "%0.2f",$vals->{maxHigh}),
			",",
			$vals->{firstBuyDay},
			",",
			$vals->{firstSellDay},
			",",
			$buyDiff,
			",",
			$sellDiff,
			",",
			$buy2High,
			",",
			$captured,
			"\n");
	};
}

my $priceSource = $priceTemplate;
$priceSource =~ s/SYM/$sym/;
my $divSource = $divTemplate;
$divSource =~ s/SYM/$sym/;

my $divInfo = loadDiv( $divSource );
#print Data::Dumper->Dump( [$divInfo] );
my ($priceInfo,$divIndex) = loadPricing( $priceSource, $divInfo );
#print Data::Dumper->Dump( [$priceInfo] );
#print Data::Dumper->Dump( [$divIndex] );
my $pricingRange = getPriceRange( $divIndex, \%config, scalar(@$priceInfo)-1 ); 
#print Data::Dumper->Dump( [$pricingRange] );
#exit;
my $correlated = correlate( $priceInfo, $pricingRange, $divInfo, \%config );
#print Data::Dumper->Dump( [$correlated] );
report2( $correlated );
exit;

sub report2 {
my ($data) = @_;


	buyInCfg() if $config{cfg};

	my $slice = 0;
	foreach my $blob ( @$data )
	{
		++$slice;
		buyInOutline( $slice, $blob );
	}

# dump raw data
	if ($config{raw} )
	{
		$slice = 0;
		foreach my $blob ( @$data )
		{
			++$slice;
			my $day = 0;
			my $vals = $blob->{pricings};
			foreach my $rawData (@$vals)
			{
				buyInRawData( $slice, ++$day, $rawData );
			}
		}
	}
}

sub report {
my ($data) = @_;

use constant Pre 	=> 0;
use constant ExDiv 	=> 1;
use constant Post 	=> 2;
	#print Data::Dumper->Dump( [$data] );
	print "ID,Ticker,ExdivId,Day,Div,Date,Open,High,Low,Close\n"; # ,Post Deltas,Div Ratios,Max Ratio\n"; 
	my $slice = 0;
	my $portion = Pre;


	my $print2 = sub { my ($slab,$section,$vals,$amount,$rowBack) = @_;
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
		my $day = -@$section;

		foreach my $dayVals ( @$section )
		{
			outLine( $slice,$day,$dayVals,$amount);
			++$day;
		}

		$day = 1; # ExDiv;
		outLine( $slice,$day,$blob->{exDiv},$amount );
		$section = $blob->{postSection};
		foreach my $dayVals ( @$section )
		{
			outLine( $slice,++$day,$dayVals,$amount );
		}
	}

	foreach my $blob ( @$data )
	{
		# dump raw data
	}
}

sub correlate {
my ($priceInfo, $pricingRange, $divInfo, $config) = @_;
my @results;

	my $dbgMax = 10000;
	my $done = 0;
	foreach my $range ( @$pricingRange )
	{
		last if ++$done > $dbgMax;
		my $divAmount = $range->{amount};
		$divAmount =~ s/\$//;
		my @pricings;
		my $exdivRange = {
			pricings => \@pricings,
			firstBuyDay => 0,
			firstSellDay => 0,
			maxLow => 0,
			maxHigh => 0,
			divAmount => $divAmount,
			buyDiscount => $divAmount*$config->{divMultiple},	#debug
			};


		my $tm1Index = $range->{tminus1};
		my $tm1Pricing = $priceInfo->[ $tm1Index ];
		$exdivRange->{tm1_pricing} = $tm1Pricing;

		my $buyTarget = $tm1Pricing->[PriceClose] - $exdivRange->{buyDiscount};
		$exdivRange->{buyTarget} = $buyTarget; 

		my $sellReference = $config->{lowBasedSell} ? $buyTarget : $tm1Pricing->[PriceClose];
		my $sellTarget = $sellReference + $config->{sellOffset};
		$exdivRange->{sellTarget} = $sellTarget;

		my $startIndex = $tm1Index+1;
		last if $startIndex >= $range->{maxEnd};

		my $firstBuy = 0;
		my $firstSell = 0;
		my $maxLow = -1;
		my $maxHigh = 0;
		my $bought = 0;
		foreach my $curIndex ( $startIndex .. $range->{buyEnd} )
		{
			my $pricing = $priceInfo->[$curIndex];
			push @pricings, $pricing;
			my $curDay = @pricings;

			my $low = $pricing->[PriceLow];
			$maxLow = $low if $maxLow == -1 or $low < $maxLow;
			my $buyIt = $low < $buyTarget;
			$firstBuy = $curDay if $firstBuy == 0 and $buyIt;

		# bit of a hole since sell target (likely) could be reached on same day as buy but don't have the interday t&s
		# .. same with maxHigh
			my $high = $pricing->[PriceHigh];
			my $sellIt = $high > $sellTarget;
			$firstSell = $curDay if $bought and $sellIt and $firstSell == 0;
			$maxHigh = $high if $bought && $high > $maxHigh;

			$bought = 1 if $buyIt;

		}
		$exdivRange->{firstBuyDay} = $firstBuy;
		$exdivRange->{maxLow} = $maxLow;

		$startIndex = $range->{buyEnd}+1;
		last if $startIndex >= $range->{maxEnd};
		foreach my $curIndex ( $startIndex .. $range->{maxEnd} )
		{
			my $pricing = $priceInfo->[$curIndex];
			push @pricings, $pricing;
			my $high = $pricing->[PriceHigh];
			$maxHigh = $high if $high > $maxHigh;
			next unless $firstBuy;
			next if $firstSell;
			next unless $high > $sellTarget;
			$firstSell = @pricings;
		}
		$exdivRange->{maxHigh} = $maxHigh;
		$exdivRange->{firstSellDay} = $firstSell;
		push @results,$exdivRange;
	}
	#print Data::Dumper->Dump( [@results] )
	\@results;
}

sub makeDateKey {
my ($date) = @_;
	my ($month, $day, $year) = split '/', $date;
	my $key = sprintf( "$year%02d%02d", $month, $day );
	return $key;
}

sub getPriceRange {
my ($divIndex, $config, $endPriceRange ) = @_;
my @ranges;

	my @indices = sort { $a cmp $b } keys %$divIndex;
	foreach my $priceIndex ( @indices )
	{
		#print Data::Dumper->Dump( [$divIndex->{$priceIndex} ] );
		my $divIndexAmount = $divIndex->{$priceIndex};
		my $exdiv = $divIndexAmount->{index};
		next if $exdiv <=0;
		my $t_n1 = $exdiv-1;
		my $buyEnd = $t_n1+$config->{buyRange};
		$buyEnd = $endPriceRange if $buyEnd > $endPriceRange;
		my $maxEnd = $t_n1+$config->{buyRange}+$config->{sellRange};
		$maxEnd = $endPriceRange if $maxEnd > $endPriceRange;
		push @ranges, {
			tminus1 => $t_n1,
			buyEnd => $buyEnd,
			maxEnd => $maxEnd,
			amount => $divIndexAmount->{amount},
			divMultiple => $config->{divMultiple},	 # don't need this
		};
	}
	\@ranges;
}

sub loadPricing {
my ($source, $divHash ) = @_;
my @pricing;
my %divIndex;

	Usage( "Pricing file '$source' not found or empty" )
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

	Usage( "Distribution file '$source' not found or empty" ) 
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

sub Usage {
	print join("\n", @_),"\n";
	print<<EOH;

Usage 
DivBuyin.pl [options] sym
Assumes sym-distributions.csv and sym-pricing.csv are present in the working directory
options:
	--buyRange : (default 2) buy window in days, from exdiv day
	--sellRange : (default 10) sell window in days ([should be] from first buy day)
		note: currently number of days is buyRange + sellRange
	--divMultiplier: (default 1.25) sets div ratio, i.e. buy target == (t-1 close)-(div*divratio)
	--sellOffset: (default 0) value to add to t-1 close for sell target
	--raw boolean (default 0) output pricing after summary
	--cfg boolean (default 0) output params -- XXX pending implementation
	--help: print usage

EOH
	die("\n");

}

