#!/usr/bin/perl -w
use strict;
use lib qw(. /usr/lib/perl);
use CGI qw(param);
use List::Util 'shuffle';

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
my @deck;
foreach my $card ( @{$kfgameshared::gamedata->{"deck$weare"}}){
    push (@deck, $kfgameshared::gamedata->{objects}{$card}{CardId});
}
@deck = shuffle(@deck);
$response->{deck} = \@deck;
my @discard;
foreach my $card ( @{$kfgameshared::gamedata->{players}{$weare}{discard} } ){
    push (@discard, $kfgameshared::gamedata->{objects}{$card}{CardId});
}
@discard = shuffle(@discard);

$response->{discard} = \@discard;

kfgameshared::debuglog("response is ".Data::Dumper::Dumper($response));
kfgameshared::end($response);
