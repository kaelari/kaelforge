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

	my $targets2;
	kfgameshared::debuglog("Checking for target: $target");
	
	($targets2, $alltargets )= kfgameshared::verifytargets(\@a, $targets, $kfgameshared::gamedata->{forceplay}[0]{source}, $weare);
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
# 						variables => $target->{variables},
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
        });
    }
}
kfgameshared::debuglog(Data::Dumper::Dumper($kfgameshared::gamedata->{forceplay}));
shift(@{$kfgameshared::gamedata->{forceplay}});
if ( (scalar @{$kfgameshared::gamedata->{forceplay}}) == 0){
	kfgameshared::checkplays();
    delete ($kfgameshared::gamedata->{forceplay});
    $kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `forcedaction`) VALUES(?, ? )", undef, (0,  0));
}else {
    kfgameshared::debuglog("another forced play");
    my $string = to_json($kfgameshared::gamedata->{forceplay}[0]);
    $kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `forcedaction`) VALUES(?, ? )", undef, (0,  $string));
		
}



kfgameshared::savegame($game);
$response->{messages}=kfgameshared::sendnewmessages($game);
kfgameshared::end($response);
