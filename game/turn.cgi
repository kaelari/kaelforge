#!/usr/bin/perl -w
use lib qw(. /usr/lib/cgi-bin/game);
use CGI qw(param);
use List::Util 'shuffle';
use JSON;
my $response = {};
$kfgameshared::dbh=kfdb::connectdb();
kfgameshared::init();
unless ($kfgameshared::loggedin){
    kfgameshared::end();
    exit;
}
my $game=param("game");
kfgameshared::loadgame($game);
if ($kfgameshared::gamedata->{ended}>0){
	$response->{status} = "Failed";
    $response->{message} = "Game has ended";
    kfgameshared::end($response);
}
if ($kfgameshared::gamedata->{forceplay}){
    $response->{status} = "Failed";
    $response->{message} = "Must do forced play first";
    kfgameshared::end($response);
}

if ($kfgameshared::gamedata->{players}{1}{playerid} != $kfgameshared::player->{userId}){
    #we are 2
    $weare=2;
    $opp=1;
}else {
    $weare=1;
    $opp=2;
}

if ($kfgameshared::gamedata->{turn} != $weare ){
    #it's not our turn!
    $response->{status} = "Failed";
    $response->{message} = "Not our turn";
    kfgameshared::end($response);
}
if ($kfgameshared::gamedata->{turnphase} == 0){
    #time to B-B-Battle
    kfgameshared::checktriggers("Attack");
    our $lanestring="";
    #if niether ship exists or both have summoning sickness
    for my $lane (1..5){
    	my $battle1 = kfgameshared::checkcanbattle($kfgameshared::gamedata->{lane}{1}{$lane});
    	my $battle2 = kfgameshared::checkcanbattle($kfgameshared::gamedata->{lane}{2}{$lane});
        if ( $battle1==0 and  $battle2==0) {
            next;
        }
        my $damage = 0;
        if ( $battle1 and $kfgameshared::gamedata->{lane}{2}{$lane} == 0) {
            $damage = $kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{1}{$lane} }{"Attack"};
            if ($damage > 0 ) {
				$kfgameshared::gamedata->{players}{2}{life}-= $damage;
				if (kfgameshared::checkkeyword("Drain", $kfgameshared::gamedata->{lane}{1}{$lane}) ) {
						$kfgameshared::gamedata->{players}{1}{life} += $damage;
				}
            }
            kfgameshared::checktriggers("Playerdamage", $kfgameshared::gamedata->{lane}{1}{$lane}, {Damage=> $damage});
            
            kfgameshared::logmessage("$kfgameshared::gamedata->{players}{2}{name} takes $damage damage");
        }
        if ($kfgameshared::gamedata->{lane}{1}{$lane} ==0 and $battle2) {
            $damage = $kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{2}{$lane} }{"Attack"};
            
            if ($damage > 0){
				$kfgameshared::gamedata->{players}{1}{life}-= $damage;
				if (kfgameshared::checkkeyword("Drain", $kfgameshared::gamedata->{lane}{2}{$lane} ) ) {
						$kfgameshared::gamedata->{players}{2}{life} += $damage;
				}
            }
            kfgameshared::checktriggers("Playerdamage", $kfgameshared::gamedata->{lane}{2}{$lane}, {Damage=> $damage});
            
            kfgameshared::logmessage("$kfgameshared::gamedata->{players}{1}{name} takes $damage damage");
        }
        if ($kfgameshared::gamedata->{lane}{1}{$lane} >=1 and $kfgameshared::gamedata->{lane}{2}{$lane} >= 1) {
            #player1's creature first (but actually at the same time)
            $damage = $kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{1}{$lane} }{"Attack"};
			if (kfgameshared::checkkeyword("Armor", $kfgameshared::gamedata->{lane}{2}{$lane}) >0 ){
				$damage -= kfgameshared::checkkeyword("Armor", $kfgameshared::gamedata->{lane}{2}{$lane});
			}
            if ($damage >0 ){
                $kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{2}{$lane} }{"Health"}-=$damage;
                if (kfgameshared::checkkeyword("Drain", $kfgameshared::gamedata->{lane}{1}{$lane} )) {
					$kfgameshared::gamedata->{players}{1}{life} += $damage;
				}
				if (kfgameshared::checkkeyword("Breakthrough", $kfgameshared::gamedata->{lane}{1}{$lane}) and $kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{2}{$lane} }{"Health"} < 0 and $battle1){
					$kfgameshared::gamedata->{players}{2}{life}  += $kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{2}{$lane} }{"Health"};
					kfgameshared::checktriggers("Playerdamage", $kfgameshared::gamedata->{lane}{1}{$lane}, {Damage=> abs( $kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{2}{$lane} }{"Health"} ) } );
            
				}
            }
            
            #player2's creature hits back at the same time
            $damage = $kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{2}{$lane} }{"Attack"};
            if (kfgameshared::checkkeyword("Armor", $kfgameshared::gamedata->{lane}{1}{$lane}) >0 ){
				$damage -= kfgameshared::checkkeyword("Armor", $kfgameshared::gamedata->{lane}{1}{$lane});
			}
            if ($damage >0 ){
                $kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{1}{$lane} }{"Health"}-=$damage;
                if (kfgameshared::checkkeyword("Drain", $kfgameshared::gamedata->{lane}{2}{$lane})) {
					$kfgameshared::gamedata->{players}{2}{life} += $damage;
				}
				if (kfgameshared::checkkeyword("Breakthrough", $kfgameshared::gamedata->{lane}{2}{$lane}) and $kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{1}{$lane} }{"Health"} < 0  and $battle2){
					$kfgameshared::gamedata->{players}{1}{life}  += $kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{1}{$lane} }{"Health"};
					kfgameshared::checktriggers("Playerdamage", $kfgameshared::gamedata->{lane}{2}{$lane}, {Damage=> abs( $kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{1}{$lane} }{"Health"} ) } );
				}

            }
            
            my $objectstring = "$kfgameshared::gamedata->{lane}{1}{$lane}:".to_json($kfgameshared::gamedata->{objects}{ $kfgameshared::gamedata->{lane}{1}{$lane} });
            $kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0, $objectstring ));
            $objectstring = "$kfgameshared::gamedata->{lane}{2}{$lane}:".to_json($kfgameshared::gamedata->{objects}{$kfgameshared::gamedata->{lane}{2}{$lane}});
            $kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0, $objectstring ));
    
            
            
        }
       
        
    }
    my $healthstring="1:$kfgameshared::gamedata->{players}{1}{life};2:$kfgameshared::gamedata->{players}{2}{life}";
    $kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, life) VALUES(?, ? )", undef, (0, $healthstring ) );
    kfgameshared::logmessage("Combat Over");
    kfgameshared::checkendgame();
    $kfgameshared::gamedata->{turnphase} = 1;
    kfgameshared::checkstatebased($game);
    kfgameshared::checkplays();
}else {
    kfgameshared::logmessage("$kfgameshared::player->{username} ended their turn");
    $kfgameshared::gamedata->{players}{$kfgameshared::gamedata->{turn} }{levelprogress} += 1;
    warn "calling discard!";
    kfgameshared::discard($kfgameshared::gamedata->{turn});
    
    
    
    if ($kfgameshared::gamedata->{players}{$kfgameshared::gamedata->{turn} }{levelprogress} >= 4) {
        $kfgameshared::gamedata->{players}{$kfgameshared::gamedata->{turn} }{levelprogress} = 0;
        $kfgameshared::gamedata->{players}{$kfgameshared::gamedata->{turn} }{level} += 1;
        #need to move all cards from the discard to the player's deck and then shuffle;
        my $weare = $kfgameshared::gamedata->{turn};
        kfgameshared::shufflediscardintodeck($weare);
        
        kfgameshared::checktriggers("rankup");
        kfgameshared::logmessage("$kfgameshared::player->{username} has leveled up!");
   
    }
    
    kfgameshared::drawcard($kfgameshared::gamedata->{turn} , 5);
    
    
    $kfgameshared::gamedata->{turnphase}=0;
    $kfgameshared::gamedata->{turn}+=1;
    if ($kfgameshared::gamedata->{turn}>=3){
        $kfgameshared::gamedata->{turn}=1;
    }
    $kfgameshared::gamedata->{playsremaining}=2;
    delete $kfgameshared::gamedata->{hidden}{$weare}{handplayable};
    $kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `turn`, `handplayable`) VALUES(?, ?, ?)", undef, ($kfgameshared::gamedata->{players}{ $weare }{playerid}, $kfgameshared::gamedata->{turn}, "[]"));
    foreach my $a (1..5) {
		if (my $object=$kfgameshared::gamedata->{lane}{ $kfgameshared::gamedata->{turn} }{$a}) {
			next unless $object;
			$kfgameshared::gamedata->{objects}{$object}{activatedthisturn}={};
			if (defined $kfgameshared::gamedata->{objects}{$object}{expires}){
				kfgameshared::debuglog("expires is defined");
				kfgameshared::debuglog(Data::Dumper::Dumper($kfgameshared::gamedata->{objects}{$object}{expires}));
				foreach my $expires (@{$kfgameshared::gamedata->{objects}{$object}{expires}}){
					if ($expires == undef){
						next;
					}
					$expires->{turns}-=1;
					if ($expires->{turns} <= 0 ){ 
						kfgameshared::debuglog("expired removing effect\r\n\r\n");
						kfgameshared::removeeffect2($object, $expires->{data});
						kfgameshared::debuglog("expired removing effect2");
						undef $expires;
						
					}
				}
			}
			my $changed=0;
			if ((my $decay= kfgameshared::checkkeyword("Poison", $object) )> 0 ){
				$kfgameshared::gamedata->{objects}{$object}{Health}-= $decay;
				$changed=1;
			}
			if ((my $repair= kfgameshared::checkkeyword("Regenerate", $object) )> 0 ){
				$kfgameshared::gamedata->{objects}{$object}{Health}+= $repair;
				if ($kfgameshared::gamedata->{objects}{$object}{Health} > $kfgameshared::gamedata->{objects}{$object}{maxhealth}){
					$kfgameshared::gamedata->{objects}{$object}{Health} = $kfgameshared::gamedata->{objects}{$object}{maxhealth};
				}
				$changed=1;
			}
			if  ($kfgameshared::gamedata->{objects}{$object}{ss}) {
				$kfgameshared::gamedata->{objects}{$object}{ss}=0;
				$changed=1;
			}
			if ($changed){
				my $objectstring = "$object:".to_json($kfgameshared::gamedata->{objects}{$object });
				$kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0, $objectstring ));
            }
		}
		if (my $object=$kfgameshared::gamedata->{lane}{ (($kfgameshared::gamedata->{turn} % 2) +1) }{$a}) {
			my $changed=0;
			if (defined $kfgameshared::gamedata->{objects}{$object}{expires}){
				kfgameshared::debuglog("expires is defined");
				kfgameshared::debuglog(Data::Dumper::Dumper($kfgameshared::gamedata->{objects}{$object}{expires}));
				foreach my $expires (@{$kfgameshared::gamedata->{objects}{$object}{expires}}){
					if ($expires == undef ){
						next;
					}
					$expires->{turns}-=1;
					if ($expires->{turns} <= 0 ){ 
						kfgameshared::removeeffect2($object, $expires->{data});
						undef $expires;
						kfgameshared::debuglog("expired removing effect");
					}
				}
				@{$kfgameshared::gamedata->{objects}{$object}{expires}} = grep defined, @{$kfgameshared::gamedata->{objects}{$object}{expires}};
			}
			if ((my $decay= kfgameshared::checkkeyword("Poison", $object) )> 0 ){
				$kfgameshared::gamedata->{objects}{$object}{Health}-= $decay;
				$changed=1;
			}
			if ((my $repair= kfgameshared::checkkeyword("Regenerate", $object) )> 0 ){
				$kfgameshared::gamedata->{objects}{$object}{Health}+= $repair;
				if ($kfgameshared::gamedata->{objects}{$object}{Health} > $kfgameshared::gamedata->{objects}{$object}{maxhealth}){
					$kfgameshared::gamedata->{objects}{$object}{Health} = $kfgameshared::gamedata->{objects}{$object}{maxhealth};
				}
				$changed=1;
			}
			if ($changed){
				my $objectstring = "$object:".to_json($kfgameshared::gamedata->{objects}{$object });
				$kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, (0, $objectstring ));
            }
		}
    }
	kfgameshared::logmessage("$kfgameshared::gamedata->{players}{$kfgameshared::gamedata->{turn}}{name} begins their turn.");
    kfgameshared::checktriggers("startturn");
    kfgameshared::checkstatebased($game);
    kfgameshared::checkplays();

}



my $levelstring = "1:$kfgameshared::gamedata->{players}{1}{level} - $kfgameshared::gamedata->{players}{1}{levelprogress};2:$kfgameshared::gamedata->{players}{2}{level} - $kfgameshared::gamedata->{players}{2}{levelprogress}";
$kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `levels`) VALUES(?, ?)", undef, (0, $levelstring));

kfgameshared::savegame($game);
$response->{messages}=kfgameshared::sendnewmessages($game);

kfgameshared::end($response);
