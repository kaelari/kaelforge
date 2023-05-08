#!/usr/bin/perl -w
use strict;
import CGI qw(param);
use Data::Dumper;
use warnings FATAL => 'all';
$kfgameshared::dbh = kfdb::connectdb();
my $response = {};
kfgameshared::init();

unless ($kfgameshared::loggedin){
    $response->{"status"} = "Not Logged in";
    kfgameshared::end($response);
    exit;
}
my $game=param("game");
kfgameshared::loadgame($game);
our $weare=0;
our $opp=0;
if (!$kfgameshared::gamedata ){
	kfgameshared::logmessage("ERROR CAn't LOAD GAME");
	exit;
	
}


if (!$kfgameshared::player->{userId} ){
    warn "AHHH no userID!";
    exit;
    
}


if ($kfgameshared::gamedata->{players}{1}{playerid} != $kfgameshared::player->{userId}){
    #we are 2
    $weare=2;
    $opp=1;
}else {
    $weare=1;
    $opp=2;
}


foreach my $playerid (keys %{$kfgameshared::gamedata->{players}}){
    if ($kfgameshared::gamedata->{players}{$playerid}{playerid} == $kfgameshared::player->{userId}){

    }else {
        
        $kfgameshared::gamedata->{players}{$playerid}{hand} = scalar @{$kfgameshared::gamedata->{players}{$playerid}{hand}};
    }
    @{$kfgameshared::gamedata->{"deck$weare"}}=sort(@{$kfgameshared::gamedata->{deck1}});
    @{$kfgameshared::gamedata->{"deck$opp"}}=[];
}
kfgameshared::debuglog(Data::Dumper::Dumper($kfgameshared::gamedata->{forceplay}));
$response->{messages} = kfgameshared::sendnewmessages($game);
foreach my $object (keys %{$kfgameshared::gamedata->{objects} } ){
	if ($kfgameshared::gamedata->{forceplay}[0]){
		kfgameshared::debuglog("We have a forceplay");
		if ($kfgameshared::gamedata->{forceplay}[0]{revealtargets}){
			kfgameshared::debuglog("We have a revealtargets");
			my $found=0;
			foreach my  $showobject (@{$kfgameshared::gamedata->{forceplay}[0]{targets}[0]{raw}}) {
				if ($showobject == $object){
					$found=1;
					last;
				}
			}
			if ($found){
				kfgameshared::debuglog("We should see $object");
				next;
			}
		}
	}
	if (defined ($kfgameshared::gamedata->{objects}{$object}{zone} ) and $kfgameshared::gamedata->{objects}{$object}{zone} eq "play"){
		next;
	}
	if (defined ($kfgameshared::gamedata->{objects}{$object}{zone}) and  $kfgameshared::gamedata->{objects}{$object}{zone} eq "hand" and $kfgameshared::gamedata->{objects}{$object}{owner} == $weare){
		next;
	}
	if (!defined $kfgameshared::gamedata->{objects}{$object}{owner}){
        #kfgameshared::debuglog("not found! ".Data::Dumper::Dumper($kfgameshared::gamedata->{objects}{$object}));
        
        next;
	}
	if ($kfgameshared::gamedata->{objects}{$object}{owner} == $weare){
		next;
	}
	delete $kfgameshared::gamedata->{objects}{$object};
}

$response->{gamedata}=$kfgameshared::gamedata;
if ($response->{gamedata}{hidden}{$opp} ){
    delete($response->{gamedata}{hidden}{$opp});
}
kfgameshared::end($response);
