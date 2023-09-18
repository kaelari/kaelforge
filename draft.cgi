#!/usr/bin/perl -w
package draft;

use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);
use shared;
use CGI qw(param);
use JSON;
use List::Util 'shuffle';

$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response = {};
kfplatformshared::init();

my $eventid = param("event");
my $eventdata= $kfplatformshared::dbh->selectrow_hashref("SELECT * from `Playerevents` where `playerid` = ? and `eventid` = ? and `finished` =0", undef, ($kfplatformshared::player->{userId}, $eventid));
our $baseeventdata = $kfplatformshared::dbh->selectrow_hashref("SELECT * from `events` WHERE `eventid` = ?", undef, ($eventid));
our $basedraftdata = $kfplatformshared::dbh->selectall_arrayref("SELECT * from `draft` WHERE `draftid` = ?", {Slice=>{}}, ($baseeventdata->{draftid} ) );
if ($eventdata->{Status} ne "Drafting"){
    $response->{status}="failed";
    $response->{message}="Not drafting";
    kfplatformshared::end($response);
}

my $draftdata;
if ($eventdata->{DraftStatus}){
    #loading existing data here
    $draftdata = from_json($eventdata->{DraftStatus});
    
    my $success = 0;
    if (my $pick=param("pick")){
        foreach my $card (@{$draftdata->{cardsavailable}}){
            
            if ($card == $pick){
                $success = 1;
            }
        }
        if ($success){
            push (@{$draftdata->{cardspicked}}, $pick);
            $kfplatformshared::dbh->do("UPDATE `KF_cards`.carddata SET `draftpicks` = `draftpicks`+1 WHERE `CardId` = ?", undef, ($pick));
            foreach my $card (@{$draftdata->{cardsavailable}}){
                $kfplatformshared::dbh->do("UPDATE `KF_cards`.carddata SET `draftoptions` = `draftoptions`+1 WHERE `CardId` = ?", undef, ($card));
            }
            my $faction = $kfplatformshared::allcards->{$pick}{Faction};
            $draftdata->{factions}{$faction}+=1;
            if ( (int @{$draftdata->{cardspicked}}) >= $baseeventdata->{Packs}) {
                #done with this draft
                
                
                $kfplatformshared::dbh->do("UPDATE `Playerevents` SET `Status` = \"Entered\" WHERE `rowid` = ?", undef, ($eventdata->{rowid}));
                $response->{result}="Draft Complete";
                my $string= "";
                $kfplatformshared::dbh->do("UPDATE `Playerevents` SET `DraftStatus` = ? WHERE `rowid` = ?", undef, ($string, $eventdata->{rowid}));
                #my $data=from_json($eventdata->{DraftStatus});
                my $cards = join(",", @{$draftdata->{cardspicked}});
                undef $draftdata;
                $kfplatformshared::dbh->do("INSERT INTO `Decks`(`eventid`, `ownerid`, `deckname`, `cards`) values(?, ?, 'Draft Deck', ?)", undef, ($eventdata->{eventid}, $kfplatformshared::player->{userId}, $cards));
                my $deckid = $kfplatformshared::dbh->last_insert_id();;
                $kfplatformshared::dbh->do("UPDATE `Playerevents` SET `deckid` = ? WHERE `rowid` = ?", undef, ($deckid, $eventdata->{rowid}));
               
                
                
                kfplatformshared::end($response);
                exit;
            }else {
                $draftdata->{cardsavailable}=generatepicks($draftdata);
            }
            my $string= to_json($draftdata);
            $kfplatformshared::dbh->do("UPDATE `Playerevents` SET `DraftStatus` = ? WHERE `rowid` = ?", undef, ($string, $eventdata->{rowid}));
        }else {
            
            my $response;
            $response->{result}= "Can't pick that card!";
            $response->{status} = "Failed";
            kfplatformshared::end($response);
            exit;
        }
        
        
    }
    
    
    
    
}else {
    #this should do more
    $draftdata->{cardspicked} = [];
    $draftdata->{factions}={};
    $draftdata->{cardsavailable}= generatepicks($draftdata);
    my $string= to_json($draftdata);
    $kfplatformshared::dbh->do("UPDATE `Playerevents` SET `DraftStatus` = ? WHERE `rowid` = ?", undef, ($string, $eventdata->{rowid}));

}

$response->{result}=$draftdata;


kfplatformshared::end($response);

sub generatepack {
    my $pack = shift;
    my $factions = shift;
    my $packs= $kfplatformshared::dbh->selectall_arrayref("SELECT * from `pack_data` WHERE `packid` = ?", {Slice=>{}}, ($pack));
    my $z= 1;
    my %slots;
    my @cards;
    foreach my $line (@{$packs}){
        if (!defined ($slots{$line->{slot} } ) ){
            $slots{$line->{slot}}=[]
        }
        push (@{$slots{$line->{slot}}}, $line);
    }
    my $notin="0";
    while ($slots{$z}){
        
        my $total=0;
        foreach my $row (@{$slots{$z}}){
            $total+= $row->{weight};
        }
        my $rand = rand ($total);
        foreach my $row (@{$slots{$z}}){
            $rand -= $row->{weight};
            if ($rand <= 0){
                #this one
                my $card= $kfplatformshared::dbh->selectrow_hashref("SELECT `CardId` FROM `KF_cards`.`carddata` WHERE `rarity` = ? and `level` = 1 and `set` = ? $factions AND `working` like \"Released\" AND `CardId` not in ( $notin ) ORDER BY RAND() limit 1", {Slice=>{}}, ($row->{rarity}, $row->{CardSet}));
                push (@cards, $card->{CardId});
                $notin.=", $card->{CardId}";
                
                last;
            }
        }
        
        $z++;
        
    }
    
    
    
    return @cards;
}

sub generatepicks {
	my $draftdata=shift;
	my $rarity = "common";
	
	my $pack = $basedraftdata->[scalar @{$draftdata->{cardspicked}} ]{packid};
	my $remove = $basedraftdata->[scalar @{$draftdata->{cardspicked}} ]{cardstaken};
	my $factions="";
    if (scalar keys %{$draftdata->{factions}} >= 2 ){
    	my @string;
    	foreach my $faction (keys %{$draftdata->{factions}}){
				push (@string, "`faction` like \"$faction\"");
    	}
		$factions = "AND (".join(" or ", @string)." )";
	}
   
    my @cardstopick;
    
    @cardstopick = generatepack($pack, $factions);
    while ($remove > 0) {
        my %weights;
        my $totalweight;
        foreach my $card (@cardstopick){
            $weights{$card}=1;
            my $carddata= $kfplatformshared::dbh->selectrow_hashref("SELECT * FROM `KF_cards`.`carddata` WHERE `CardId` = ?  limit ?", {Slice=>{}}, ($card, 1));
            if ($carddata->{draftpicks}){
                $weights{$card} = ($carddata->{draftpicks} / $carddata->{draftoptions}) * 100;
            }
            $totalweight += $weights{$card};
        }
        my $rand = rand ($totalweight);
        my $z=0;
        while ($z <= 100){
            my $card = $cardstopick[$z];
            $rand-= $weights{$card};
            if ($rand <= 0){
                splice(@cardstopick, $z, 1);
                last;
            }
            $z++;
        }

        $remove-=1;
        
    }
    
    return \@cardstopick;
}


