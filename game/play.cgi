#!/usr/bin/perl -w
use lib qw(. /usr/lib/cgi-bin/game);
use strict;

# Import the database handle and connect to the database
$kfgameshared::dbh=kfdb::connectdb();

# Import the CGI module and use its 'param' method to fetch the 'game' parameter
use CGI qw(param);

# Import the JSON module to handle JSON data
import JSON;

# Create a response object to store the response data
my $response = {};

# Initialize the game
kfgameshared::init();

# If the user is not logged in, end the script
unless ($kfgameshared::loggedin){
    kfgameshared::kfgameshared::end();
    exit;
}

# Fetch the game ID
our $game=param("game");

# If the game ID is not specified, set an error message and end the script
unless ($game){
    $response->{message}="No gameid";
    $response->{status} = "Failed";
    kfgameshared::end($response);
    exit;
}

# Load the game data
kfgameshared::loadgame($game);

# If the game has ended, set an error message and end the script
if ($kfgameshared::gamedata->{ended} > 0){
    $response->{status} = "Failed";
    $response->{message} = "game has ended";
    kfgameshared::end($response);
    exit;
}

# If a forced play must be done first, set an error message and end the script
if ($kfgameshared::gamedata->{forceplay}){
    $response->{status} = "Failed";
    $response->{message} = "Must do forced play first";
    kfgameshared::end($response);
    exit;
}

# Initialize variables to keep track of the current player and the opponent
our $weare=0;
our $opp = 0;
my $nolevel = 0;

# If it's not the current player's turn, set an error message and end the script
if ($kfgameshared::gamedata->{players}{$kfgameshared::gamedata->{turn}}{playerid} != $kfgameshared::player->{userId}){
    $response->{status} = "Failed";
    $response->{message} = "Not our turn - $kfgameshared::gamedata->{turn} is $kfgameshared::gamedata->{players}{$kfgameshared::gamedata->{turn}}{playerid}";
    kfgameshared::end($response);
    exit;
}

# Determine whether the current player is player 1 or 2
if ($kfgameshared::gamedata->{players}{1}{playerid} != $kfgameshared::player->{userId}){
    # The current player is player 2
    $weare=2;
    $opp=1;
}else {
    # The current player is player 1
    $weare=1;
    $opp=2;
}

delete $kfgameshared::gamedata->{hidden}{$weare}{handplayable};



    my $card=param("card");
    #check the card is in fact a Effect;
    if ($kfgameshared::gamedata->{objects}{$card}{CardType} eq "Spell"){
    
        my $lane=param("target");
        my $targets = from_json($lane);    
        my $found = 0;
        my $z=0;
        foreach my $cardinhand (@{$kfgameshared::gamedata->{players}{$kfgameshared::gamedata->{turn} }{hand}}){
            if ($cardinhand == $card){
                $found=1;
                last;
            }
            $z++;
        }
        if ($found == 0) {
            $response->{status} = "Failed";
            $response->{message} = "card not in hand";
            kfgameshared::end($response);
            exit;
        }
		splice @{$kfgameshared::gamedata->{players}{$kfgameshared::gamedata->{turn} }{hand}}, $z, 1;
		$kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `draws`) VALUES(?, ?)", undef, ($kfgameshared::player->{userId}, -$card));
   
        my @targets2;
        my $index=0;
        my $alltargets;
        my $targets2;
        my $variables={};
        kfgameshared::debuglog("targets".Data::Dumper::Dumper($targets));
        kfgameshared::debuglog("weare: ".Data::Dumper::Dumper($weare));
        my @a =split(/,/, $kfgameshared::gamedata->{objects}{$card}{targets});
        kfgameshared::debuglog("a is ".Data::Dumper::Dumper(\@a));
        my $failed=0;
       	($targets2, $alltargets, $variables, $failed )= kfgameshared::verifytargets(\@a, $targets, $card, $weare);
		kfgameshared::debuglog(Data::Dumper::Dumper($variables));
		
		if ($failed ){
				$response->{status} = "Failed";
				$response->{message} = "invalid target";
				kfgameshared::end($response);
				exit;
			}
			@targets2= @{$targets2};
			kfgameshared::debuglog("targets2 is:" . Data::Dumper::Dumper(@targets2));
			kfgameshared::debuglog("alltargets is:" . Data::Dumper::Dumper($alltargets));
			
			
		
        my @effects = split(/,/, $kfgameshared::gamedata->{objects}{$card}{effects});
        foreach my $effect (@effects){
            if ($kfgameshared::alltargets->{$kfgameshared::gamedata->{objects}{$card}{targets}}{Selector} eq "All"){
        		kfgameshared::debuglog("applying effect(All): $effect");
        		foreach my $target (@{$alltargets}){
					kfgameshared::debuglog("applying effect(All): $target");	
					kfgameshared::applyeffects( {
						effecttype=> $kfgameshared::alleffects->{$effect}{effecttype}, 
						effecttarget => $kfgameshared::alleffects->{$effect}{effecttarget},
						effectmod1 => $kfgameshared::alleffects->{$effect}{effectmod1}, 
						expires => $kfgameshared::alleffects->{$effect}{expires},
						target => [$target], 
						effectcontroller => $weare,
 						variables => $variables,
						} );
        		}
        	}else {
        		kfgameshared::debuglog("applying effect: $effect");
				kfgameshared::applyeffects( {
					effecttype => $kfgameshared::alleffects->{$effect}{effecttype}, 
					effecttarget => $kfgameshared::alleffects->{$effect}{effecttarget},
					effectmod1 => $kfgameshared::alleffects->{$effect}{effectmod1},
					expires => $kfgameshared::alleffects->{$effect}{expires},
					target => \@targets2,
					effectcontroller => $weare, 
					variables => $variables
					} );
            }
        }
     $kfgameshared::gamedata->{objects}{$card}{zone}="graveyard";
    kfgameshared::debuglog("card is: $card");
    
    if ($targets2[0]){
    	my $message = " $kfgameshared::player->{username} plays <link=$kfgameshared::gamedata->{objects}{$card}{CardId}><color=#000000>$kfgameshared::gamedata->{objects}{$card}{Name}(lvl $kfgameshared::gamedata->{objects}{$card}{level})</color></link> targetting ";
    	for (my $i=0; $i<scalar @targets2; $i++){
			if ($i>0) {
				$message.=" and ";
			}
			$message .= "<link=$kfgameshared::gamedata->{objects}{$targets2[$i]}{CardId}><color=#000000>$kfgameshared::gamedata->{objects}{$targets2[$i] }{Name}</color></link>";
    	}
        kfgameshared::logmessage($message);
    }else {
        kfgameshared::logmessage("$kfgameshared::player->{username} plays <link=$kfgameshared::gamedata->{objects}{$card}{CardId}><color=#000000>$kfgameshared::gamedata->{objects}{$card}{Name}(lvl $kfgameshared::gamedata->{objects}{$card}{level})</color></link>.");
    }
    if (kfgameshared::checkkeyword("Free", $card) > 0 ) {
    }else {
		$kfgameshared::gamedata->{playsremaining} -= $kfgameshared::gamedata->{objects}{$card}{cost};
    }
    kfgameshared::checktriggers("SpellCast", $kfgameshared::gamedata->{objects}{$card});
    

}elsif ($kfgameshared::gamedata->{objects}{$card}{CardType} eq "Creature" and $kfgameshared::gamedata->{objects}{$card}{zone} eq "play")  {
	kfgameshared::debuglog("This is an activated ability");
	my $abilityindex=(param("index") or 0);
	my $ability =  $kfgameshared::gamedata->{objects}{$card}{activated}[$abilityindex];
	if (!$ability) {
        
        if (my $warp= kfgameshared::checkkeyword("Move", $card)) {
            if ($warp == 1){
                $ability = 1;
            }
            if ($warp == 2){
                $ability = 2;
            }
            if ($warp == 3){
                $ability = 3;
            }
            if ($warp >= 4){
                $ability = 4;
            }
            
            
        }
	}
	my $activated = $kfgameshared::allactivated->{ $ability }{targetindex};
	my $lane=param("target");
    my $targets = from_json($lane);    
    my $index = 0;
	my @targets2;
	my $alltargets;
    if ($kfgameshared::gamedata->{objects}{$card}{activatedthisturn}{$abilityindex} >0){
        $response->{status} = "Failed";
        $response->{message} = "Already Activated $abilityindex";
        kfgameshared::end($response);
        exit;
    }
    kfgameshared::debuglog(Data::Dumper::Dumper($targets));
    my $variables={};
    my @a =split(/,/, $activated);
    my $targets2;
    my $failed=0;
    ($targets2, $alltargets, $variables, $failed) = kfgameshared::verifytargets(\@a, $targets, $card, $weare);
			if ($failed){
				$response->{status} = "Failed";
				$response->{message} = "invalid target";
				kfgameshared::end($response);
				exit;
			}
			@targets2= @{$targets2};
			push (@targets2, $card);
			kfgameshared::debuglog("targets2 is:" . Data::Dumper::Dumper(@targets2));
			kfgameshared::debuglog("alltargets is:" . Data::Dumper::Dumper($alltargets));
	
		
	
		kfgameshared::debuglog("applying effects!\n\n\n\n\n\n");
        my @effects = split(/,/, $kfgameshared::allactivated->{ $ability }{effects});
        foreach my $effect (@effects){
			$variables->{source} = $card;
            if ($kfgameshared::alltargets->{$a[0]}{Selector} eq "All"){
        		foreach my $target (@{$alltargets}){
					
					kfgameshared::applyeffects( {
						effecttype => $kfgameshared::alleffects->{$effect}{effecttype},
						effecttarget => $kfgameshared::alleffects->{$effect}{effecttarget},
						effectmod1 => $kfgameshared::alleffects->{$effect}{effectmod1}, 
						expires => $kfgameshared::alleffects->{$effect}{expires},
						target => [$target, $card], 
						effectcontroller => $weare,
						variables => $variables
						} );
        		}
        	}else {
        		kfgameshared::debuglog("applying effect: $effect");
				kfgameshared::applyeffects({
					effecttype => $kfgameshared::alleffects->{$effect}{effecttype}, 
					effecttarget => $kfgameshared::alleffects->{$effect}{effecttarget},
					effectmod1 => $kfgameshared::alleffects->{$effect}{effectmod1},
					expires => $kfgameshared::alleffects->{$effect}{expires},
					target => \@targets2,
					effectcontroller => $weare,
					variables => $variables,
					} );
            }
        }
        kfgameshared::debuglog("finished activating $ability $abilityindex of $card");
		$kfgameshared::gamedata->{objects}{$card}{activatedthisturn}{$abilityindex}=1;
		$nolevel=1;
}elsif($kfgameshared::gamedata->{objects}{$card}{CardType} eq "Creature"){
    my $lane=param("target");
    my $target = from_json($lane);
    if (!$target->[0] || $target->[0] =~/o/){
        $response->{status} = "Failed";
        $response->{message} = "must play to a lane: ".Data::Dumper::Dumper($target->[0]);
        kfgameshared::end($response);
    }
    $lane = $target->[0];
    $lane =~s/l//;
    #check the card is in fact in our hand
    my $found = 0;
    my $z=0;
    foreach my $cardinhand (@{$kfgameshared::gamedata->{players}{$kfgameshared::gamedata->{turn} }{hand}}){
        if ($cardinhand == $card){
            $found=1;
            last;
        }
        $z++;
    }
    if ($found == 0) {
        $response->{status} = "Failed";
        $response->{message} = "card not in hand";
        kfgameshared::end($response);
    }
    #card in hand, check we have resources for it
    if ($kfgameshared::gamedata->{objects}{$card}{cost} > $kfgameshared::gamedata->{playsremaining} and kfgameshared::checkkeyword("Free", $card) <=0){
        #cost is more than we have
        $response->{status} = "Failed";
        $response->{message} = "not enough actions";
        kfgameshared::end($response);
    }
    
    
    #we have enough gold, and threshold, we can recruit this unit... 
        
    splice @{$kfgameshared::gamedata->{players}{$kfgameshared::gamedata->{turn} }{hand}}, $z, 1;
    if (kfgameshared::checkkeyword("Free", $card) > 0 ) {
    	kfgameshared::debuglog("This card is free");
    }else {
		$kfgameshared::gamedata->{playsremaining} -= $kfgameshared::gamedata->{objects}{$card}{cost};
    }
    $kfgameshared::gamedata->{objects}{$card}{zone}="play";
    $kfgameshared::gamedata->{objects}{$card}{lane}="$lane";
    $kfgameshared::gamedata->{objects}{$card}{maxhealth} =$kfgameshared::gamedata->{objects}{$card}{Health};
    $kfgameshared::gamedata->{objects}{$card}{ss}=1;
    my $objectstring = "$card:".to_json($kfgameshared::gamedata->{objects}{$card});
    #Clean up if theres already a creature here.
    if ($kfgameshared::gamedata->{lane}{$weare}{$lane} > 0 ){
    	$kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{$weare}{$lane} }{zone}="Replaced";
    	$kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{$weare}{$lane} }{lane}=0;
        $kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `lane`) VALUES(?, ?)", undef, (0, "$weare:$lane:0"));
    
    }
    $kfgameshared::gamedata->{lane}{ $kfgameshared::gamedata->{turn} }{$lane} = $card;
    $kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `lane`, `object`) VALUES(?, ?, ? )", undef, (0, "$weare:$lane:$card", $objectstring ));
    
    kfgameshared::logmessage("$kfgameshared::player->{username} plays <link=$kfgameshared::gamedata->{objects}{$card}{CardId}><color=#000000>$kfgameshared::gamedata->{objects}{$card}{Name}(lvl $kfgameshared::gamedata->{objects}{$card}{level})</color></link>");
    kfgameshared::debuglog("start checking triggers for Creaturetrained+ $card");
    kfgameshared::checktriggers("Creaturetrained", $kfgameshared::gamedata->{objects}{$card}, {Forged => 1} );
    kfgameshared::debuglog("done checking triggers for Creaturetrained");

    
    $kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `draws`) VALUES(?, ?)", undef, ($kfgameshared::player->{userId}, -$card));
    
    
    
}
if ($kfgameshared::gamedata->{objects}{$card}{levelsto}>0 and !kfgameshared::checkkeyword("Overload", $card) and !$nolevel ) {
    #need to add the leveled version to the discard
    my $card= kfgameshared::createobject($kfgameshared::gamedata->{objects}{$card}{levelsto}, $weare);
    $kfgameshared::gamedata->{objects}{$card}{zone}="discard";
    push (@{$kfgameshared::gamedata->{players}{$weare}{discard}}, $card);    
}

kfgameshared::checkstatebased($game);
kfgameshared::checkplays();
kfgameshared::savegame($game);

$response->{messages}=kfgameshared::sendnewmessages($game);

kfgameshared::end($response);
