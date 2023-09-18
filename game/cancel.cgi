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
    exit;
}
my $trigger= param("trigger");
my $target = param("target");
my @targets;


if ($kfgameshared::gamedata->{forceplay}[0]{cancancel} == 0){
    $response->{status} = "Failed";
    $response->{message} = "Not a cancelable action ";
    kfgameshared::end($response);
    exit;
}

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
                            $targetinfo->{text} = $kfgameshared::alltargets->{$index}{text};
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
        $kfgameshared::gamedata->{forceplay}[0]{cancancel} = $kfgameshared::alltriggers->{$kfgameshared::gamedata->{forceplay}[0]{trigger}}{cancancel};
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
