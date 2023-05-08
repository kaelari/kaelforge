#!/usr/bin/perl -w
use strict;
use lib qw(. /usr/lib/cgi-bin/kf);
use CGI qw(param);
$kfgameshared::dbh=kfdb::connectdb();
my $response = {};
kfgameshared::init();
unless ($kfgameshared::loggedin){
    kfgameshared::end();
    exit;
}
my $game=param("game");
$kfgameshared::game = $game;
kfgameshared::loadgame($game);

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

$kfgameshared::gamedata->{players}{$weare}{life}=-1000;

kfgameshared::checkendgame();

$response->{messages} = kfgameshared::sendnewmessages($game);
kfgameshared::savegame($game);
kfgameshared::end($response);
