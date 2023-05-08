#!/usr/bin/perl -w

use Data::Dumper;

unless (open FILE, "$ARGV[0]") {
	die("$!");
}

local $/;
my $data =<FILE>;
my $result = parse_csv($data);
#print Dumper($result);
$z=1;
my %names;
for( my $i=0; $i+39< @{$result}; $i+=39) {
	
	my $a=0;
	if ($result->[$i+31] eq "set1"){
		if ($result->[$i+5] eq "Creature"){
			$names{ $result->[$i+1] } +=1;
			my $levelsto=0;
			if ($names{ $result->[$i+1] } == 3){
				#print $result->[$i+1]." $z levels to: ".($z);
				$levelsto = $z;
			}else {
				#print $result->[$i+1]." $z levels to: ".($z+1);
				$levelsto = $z+1;
			}
			my $levelsfrom=0;
			if ($names{ $result->[$i+1] } == 1){
				#print " levels from 0";
			}else {
				#print " levels from ".($z-1);
				$levelsfrom = $z-1;
			}
			my $text = $result->[$i+6];
			$text=~s/'/\\'/g;
			my $rarity = $result->[$i+16];
			if (!$rarity) {
				if ($result->[$i+22]){
					$rarity="Token";
				}
			}
			#print "\n";
			print "INSERT INTO `carddata` (`CardId`, `Name`, `levelsto`, `levels from`, `level`, `CardType`, `cost`, `subtype`, `Text`, `Cardart`, `Attack`, `Health`, `Faction`, `rarity`, `keywords`) VALUES ( $z, '".$result->[$i+1]."', $levelsto, $levelsfrom, ".$names{ $result->[$i+1] }.", '". $result->[$i+5]."', 1, '".$result->[$i+9]."', '".$text."', '".$result->[$i+17]."', ".$result->[$i+10].", ".$result->[$i+11].", '".$result->[$i+8]. "', '".$rarity."', '".$result->[$i+7]."');\n";
			
			#print "$result->[$i+1], $result->[$i+2], $result->[$i+5], \"$result->[$i+6]\", $result->[$i+7], $result->[$i+8], $result->[$i+9], $result->[$i+10]/ $result->[$i+11], set: $result->[$i+31]\n";
			$z++;
		}else {
		#	print $result->[$i+1]." Spell \n";
		}
	}
}


while (0 ){
	#CardID,CardName,Level,PrevCardID,NextCardID,CardType,CardText,Keywords,Faction,CreatureType,Power 10 ,Health,ActionsToPlay,AdditionalContinuous,AdditionalTriggers,AdditionalActivated,Rarity 16 ,Art 17,ArtistCredit,#ArtCheck,FlavorText,Tag,Token 22 ,AIBaselineScore,ConditionalTestTarget,ConditionalTest0,ConditionalTest1,ConditionalTest2,Condition,CountPerDeck,Set1Booster,Set,InPacks,InDraft,#PlaytestName,#4.x,InDraftPool2,InDraftPool3,#PlaytestName,#testfield
	$data = parse_csv( $line);
	if ($data->[31] eq "set1"){
		print "$data->[1], $data->[2], $data->[5], \"$data->[6]\", $data->[7], $data->[8], $data->[9], $data->[10], set: $data->[31]\n";	
	}
	
	
	#exit;
}


sub parse_csv {
    my $text = shift;      # record containing comma-separated values
    my @new  = ();
	while ($text =~ m{
        # the first part groups the phrase inside the quotes.
        # see explanation of this pattern in MRE
        "([^\"\\]*(?:\\.[^\"\\]*)*)",?
           |  ([^,]+),?
           | ,
       }gxsm) {
			my $part = $+;
			if (!defined($part)){
				$part= "";
			}
			push(@new, $part)
       }
       push(@new, "") if substr($text, -1,1) eq ',';
       return \@new;      # list of values that were comma-separated
}
