#!/usr/bin/perl -w
use strict;
use lib qw(. /usr/lib/cgi-bin/game);
use CGI qw(param);
use JSON;
my $response = {};
kfgameshared::init();
$kfgameshared::dbh=kfdb::connectdb();
unless ($kfgameshared::loggedin){
    kfgameshared::end();
    exit;
}
my $game=param("game");
$kfgameshared::game = $game;
kfgameshared::loadgame($kfgameshared::game);

if ($kfgameshared::gamedata->{ended} > 0){
    $response->{status} = "Failed";
    $response->{message} = "game has ended";
    kfgameshared::end($response);
    exit;
}

if (!$kfgameshared::gamedata->{forceplay}){
    $response->{Status}="failed";
    $response->{Message} = "No forced action needed";
    kfgameshared::end($response);
    exit;
}

our $weare=0;
our $opp =0;

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
    $response->{message} = "Not our turn $weare $kfgameshared::gamedata->{turn} ";
    kfgameshared::end($response);
}
my $trigger= param("trigger");
my $target = param("target");
my @targets;

my $lane=param("target");
kfgameshared::debuglog("we recieved: $lane");
my $targets = from_json($lane);
my @targets2;
my $alltargets;
my @a=split(/,/,$kfgameshared::alltriggers->{$kfgameshared::gamedata->{forceplay}[0]{trigger}}{targetindex});
if ($kfgameshared::alltriggers->{$kfgameshared::gamedata->{forceplay}[0]{trigger}}{targettype} eq "multi"){
    @a=split(/,/,$kfgameshared::alltriggers->{$kfgameshared::gamedata->{forceplay}[0]{trigger}}{targetindexes});
}
my $newvariables;
my $variables = $kfgameshared::gamedata->{forceplay}[0]{variables};
	my $targets2;
	kfgameshared::debuglog("Checking for target: $target");
	
	($targets2, $alltargets, $newvariables )= kfgameshared::verifytargets(\@a, $targets, $kfgameshared::gamedata->{forceplay}[0]{source}, $weare);
	foreach my $key (keys %{$newvariables}){
        $variables->{$key}=$newvariables->{$key};
	}
			if (!$targets2){
				$response->{status} = "Failed";
				$response->{message} = "invalid target";
				kfgameshared::end($response);
				exit;
			}
			@targets2= @{$targets2};
			kfgameshared::debuglog("targets2 is:" . Data::Dumper::Dumper(\@targets2));
			kfgameshared::debuglog("alltargets is:" . Data::Dumper::Dumper($alltargets));
	

my @effects = split(/,/, $kfgameshared::alltriggers->{$trigger}{effectindexes});
foreach my $effect (@effects){
	if ($kfgameshared::alltargets->{$kfgameshared::alltriggers->{$kfgameshared::gamedata->{forceplay}[0]{trigger}}{targetindex}}{Selector} eq "All"){
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
 						loop => $kfgameshared::alleffects->{$effect}{loop},
						} );
        		}
	}else {

        kfgameshared::applyeffects({
            effecttype => $kfgameshared::alleffects->{$effect}{effecttype}, 
            effecttarget => $kfgameshared::alleffects->{$effect}{effecttarget},
            effectmod1 => $kfgameshared::alleffects->{$effect}{effectmod1},
            expires => $kfgameshared::alleffects->{$effect}{expires},
            target =>  \@targets2, 
            effectcontroller => $weare,
            variables => $variables,
            loop => $kfgameshared::alleffects->{$effect}{loop},
        });
    }
}
kfgameshared::debuglog(Data::Dumper::Dumper($kfgameshared::gamedata->{forceplay}), $game );
shift(@{$kfgameshared::gamedata->{forceplay}});
if ( (scalar @{$kfgameshared::gamedata->{forceplay}}) == 0){
	delete ($kfgameshared::gamedata->{forceplay});
	kfgameshared::checkplays();
    $kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `forcedaction`) VALUES(?, ? )", undef, (0,  0));
}else {
    #we should recalc targets!
    kfgameshared::debuglog("another forced play", $game);
    #my $string = to_json($kfgameshared::gamedata->{forceplay}[0]);
    #$kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `forcedaction`) VALUES(?, ? )", undef, (0,  $string));
    my $done = 0;
    outer: while (defined $kfgameshared::gamedata->{forceplay} && scalar @{$kfgameshared::gamedata->{forceplay}} > 0 && $done == 0 ){
        #we should check targets here again.
        if (!defined ($kfgameshared::gamedata->{forceplay}[0]{trigger})){
            shift(@{$kfgameshared::gamedata->{forceplay}});
            next;
        }
        
        my ($lane, $olane, $raw, $totalvalidtargets, $variables, $players);
        my @targetinfo;
        if ($kfgameshared::alltriggers->{$kfgameshared::gamedata->{forceplay}[0]{trigger}}{targettype} eq "multi"){
            my @targetindexes = split(/,/, $kfgameshared::alltriggers->{$kfgameshared::gamedata->{forceplay}[0]{trigger}}{targetindexes});
                        
                        foreach my $index (@targetindexes){
                            
                            my ($lane, $olane, $totalvalidtargets, $variables)  = kfgameshared::findtargets($kfgameshared::gamedata->{turn}, $index, $kfgameshared::gamedata->{forceplay}[0]{source}); 
                                                    
                            if ($totalvalidtargets < $kfgameshared::alltargets->{$index}{mintargets} ){
                                shift(@{$kfgameshared::gamedata->{forceplay}});
                                next outer;
                            }
                            my $targetinfo ={};
                            $targetinfo->{text} = $alltargets->{$index}{text};
                            $targetinfo->{l} = $lane;
                            $targetinfo->{o} = $olane;
                            push (@targetinfo, $targetinfo);
                        }
                        
                       
        }else{
            ($lane, $olane, $raw, $totalvalidtargets, $variables, $players)  = kfgameshared::findtargets_revised($kfgameshared::gamedata->{turn}, $kfgameshared::alltriggers->{$kfgameshared::gamedata->{forceplay}[0]{trigger}}{targetindex}, $kfgameshared::gamedata->{forceplay}[0]{source});
            my $targetinfo ={};
            $targetinfo->{text} = $kfgameshared::alltargets->{$kfgameshared::alltriggers->{$kfgameshared::gamedata->{forceplay}[0]{trigger}}{targetindex}}{text};
            $targetinfo->{l} = $lane;
            $targetinfo->{o} = $olane;
            $targetinfo->{raw}= $raw;
            $targetinfo->{players} = $players;
            push (@targetinfo, $targetinfo);
        
            if ($totalvalidtargets < $kfgameshared::alltargets->{ $kfgameshared::alltriggers->{$kfgameshared::gamedata->{forceplay}[0]{trigger}}{targetindex} }{mintargets} ){
            #we don't have targets,
                debuglog("lack of targets");
                shift(@{$kfgameshared::gamedata->{forceplay}});
                next;
            }
        
        }
        $kfgameshared::gamedata->{forceplay}[0]{targets} = \@targetinfo;
        $kfgameshared::gamedata->{forceplay}[0]{variables} = $variables;
        
		my $string = to_json($kfgameshared::gamedata->{forceplay}[0]);
		
		my $weare = $kfgameshared::gamedata->{turn};
		
		$kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `forcedaction`) VALUES(?, ? )", undef, ($kfgameshared::gamedata->{players}{$weare}{playerid},  $string));
		if ($kfgameshared::gamedata->{forceplay}[0]{revealtargets} ){
			foreach my $target (@{$kfgameshared::gamedata->{forceplay}[0]{targets}[0]{raw}}){
				
				my $objectstring = "$target:".to_json($kfgameshared::gamedata->{objects}{ $target});
				$kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `object`) VALUES(?, ? )", undef, ($kfgameshared::gamedata->{players}{$weare}{playerid},  $objectstring ));
			
			}
		}
		$done=1;
	}
    
    
    
    
}



kfgameshared::savegame($game);
$response->{messages}=kfgameshared::sendnewmessages($game);
kfgameshared::end($response);
