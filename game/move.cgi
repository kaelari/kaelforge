#!/usr/bin/perl -w
use lib qw(. /usr/lib/cgi-bin/game);
use strict;
use warnings FATAL => 'all';
use CGI qw(param);

use JSON;
my $response = {};
ksgameshared::init();
unless ($ksgameshared::loggedin){
	$response->{status}="Not logged in";
    ksgameshared::end($response);
    exit;
}
our $game=param("game");
ksgameshared::loadgame($game);
if ($ksgameshared::gamedata->{ended} > 0){
    $response->{status} = "Failed";
    $response->{message} = "game has ended";
    ksgameshared::end($response);
    exit;
}

if ($ksgameshared::gamedata->{forceplay}){
    $response->{status} = "Failed";
    $response->{message} = "Must do forced play first";
    ksgameshared::end($response);
    exit;
}

our $weare=0;
our $opp=0;

if ($ksgameshared::gamedata->{players}{$ksgameshared::gamedata->{turn}}{playerid} != $ksgameshared::player->{userId}){
    #it's not our turn!
    $response->{status} = "Failed";
    $response->{message} = "Not our turn - $ksgameshared::gamedata->{turn} is $ksgameshared::gamedata->{players}{$ksgameshared::gamedata->{turn}}{playerid}";
    ksgameshared::end($response);
}
if ($ksgameshared::gamedata->{turnphase} != 0){
    #it's not our move phase!
    $response->{status} = "Failed";
    $response->{message} = "Not our move phase";
    ksgameshared::end($response);
}
if ($ksgameshared::gamedata->{players}{1}{playerid} != $ksgameshared::player->{userId}){
    #we are 2
    $weare=2;
    $opp=1;
}else {
    $weare=1;
    $opp=2;
}
my $newposition=param("newposition");
my %validpositions;
for my $z (1..3){
    my $position = $ksgameshared::gamedata->{players}{$ksgameshared::gamedata->{turn} }{position} + $z;
    if ($position>= scalar @{ $ksgameshared::gamedata->{players}{ $ksgameshared::gamedata->{turn} }{wheel}} ){
        $position -= scalar @{ $ksgameshared::gamedata->{players}{ $ksgameshared::gamedata->{turn} }{wheel}};
    }
    $validpositions{$position}=1;
}
foreach my $foo (@{$ksgameshared::gamedata->{players}{$ksgameshared::gamedata->{turn} }{canmove}}){
	if (defined $foo ) {
		$validpositions{$foo} = 1;
	}
}
if (!$validpositions{$newposition} and $ksgameshared::gamedata->{players}{$ksgameshared::gamedata->{turn} }{position} >=0){
    $response->{status} = "Failed";
    $response->{message} = "Can't move that far! $newposition : $ksgameshared::gamedata->{players}{$ksgameshared::gamedata->{turn}}{position}";
    ksgameshared::end($response);
}
if ($newposition >=  scalar @{ $ksgameshared::gamedata->{players}{ $ksgameshared::gamedata->{turn} }{wheel}} ){
    $newposition -=  scalar @{ $ksgameshared::gamedata->{players}{ $ksgameshared::gamedata->{turn} }{wheel}};
}

delete($ksgameshared::gamedata->{hidden}{$weare}{moveoptions});
delete($ksgameshared::gamedata->{players}{$ksgameshared::gamedata->{turn} }{canmove} );
$ksgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `changeposition`, `moveoptions`) VALUES(0, ?, ?)", undef, ("$ksgameshared::player->{userId} : $newposition", "-1"));
my @wheel = @{$ksgameshared::gamedata->{players}{ $ksgameshared::gamedata->{turn} }{wheel}};
ksgameshared::logmessage("$ksgameshared::player->{username} moved to new position $wheel[$newposition]");


#we moved, now do we need to do something for the new phase? 
if ($wheel[$newposition] eq "Ritual") {
    ksgameshared::checktriggers("Ritual");
}
if ($wheel[$newposition] eq "Draw"){
	#we need to draw a card;
        ksgameshared::drawcard($weare, 1);
	
}

if ($wheel[$newposition] eq "Attack"){
    
}

if ($wheel[$newposition] eq "Explore"){
	#we can explore
	my $canplay="";
	my @canplay;

        foreach my $card (@{$ksgameshared::gamedata->{players}{$ksgameshared::gamedata->{turn} }{hand} }){
                my $card2=$card;
                my $targets=[];
                
                
                $card2="$card2:".to_json($targets);
                push (@canplay, $card2);
        }
        
        
        $canplay=join(";", @canplay);
        $ksgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `handplayable`) VALUES(?, ?)", undef, ($ksgameshared::player->{userId}, $canplay ));
	$ksgameshared::gamedata->{hidden}{$ksgameshared::gamedata->{turn}}{handplayable}=$canplay;
}
if ($wheel[$newposition] eq "Cast"){
    ksgameshared::checkcast();
    
}
if ($wheel[$newposition] eq "Train"){
	#we can train
	
	ksgameshared::checktrain();
	
}
if ($wheel[$newposition] eq "Station"){
	#we can train
	
	ksgameshared::checkstation();
	
}

$ksgameshared::gamedata->{turnphase}=1;
$ksgameshared::gamedata->{players}{$ksgameshared::gamedata->{turn}}{position} = $newposition;
ksgameshared::savegame($game);
$response->{messages}=ksgameshared::sendnewmessages($game);
ksgameshared::end($response);
