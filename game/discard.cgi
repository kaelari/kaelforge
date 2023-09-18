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

my $card=param("card");
my $found;
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
if ($kfgameshared::gamedata->{playsremaining} <=0 ){
    $response->{status} = "Failed";
    $response->{message} = "no plays remaining";
    kfgameshared::end($response);
    exit;
}

$kfgameshared::gamedata->{playsremaining}-=1;

splice @{$kfgameshared::gamedata->{players}{$kfgameshared::gamedata->{turn} }{hand}}, $z, 1;
$kfgameshared::dbh->do("INSERT INTO `GameMessages_$game` (`playerid`, `draws`) VALUES(?, ?)", undef, ($kfgameshared::player->{userId}, -$card));
$kfgameshared::gamedata->{objects}{$card}{zone}="graveyard";

if ($kfgameshared::gamedata->{objects}{$card}{levelsto}>0 ) {
    #need to add the leveled version to the discard
    my $newcard= kfgameshared::createobject($kfgameshared::gamedata->{objects}{$card}{levelsto}, $weare);
    $kfgameshared::gamedata->{objects}{$newcard}{zone}="discard";
    push (@{$kfgameshared::gamedata->{players}{$weare}{discard}}, $newcard);    
}else {
    $kfgameshared::gamedata->{objects}{$card}{zone}="discard";
    push (@{$kfgameshared::gamedata->{players}{$weare}{discard}}, $card);    
}
kfgameshared::logmessage("$kfgameshared::gamedata->{players}{$weare}{username} discards a card to level it.");

kfgameshared::checkstatebased($game);
kfgameshared::checkplays();
kfgameshared::savegame($game);

$response->{messages}=kfgameshared::sendnewmessages($game);

kfgameshared::end($response);
