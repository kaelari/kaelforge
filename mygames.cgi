#!/usr/bin/perl -w
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);
use shared;
use CGI qw(param);
$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response = {};
kfplatformshared::init();


$response->{games}=$kfplatformshared::dbh->selectall_arrayref("SELECT * from `Games` WHERE `ended` = 0 and (`player1` = ? or `player2` = ?)", {Slice=>{}}, ($kfplatformshared::player->{userId}, $kfplatformshared::player->{userId}));
foreach my $game (@{$response->{games}}){
	if ($game->{player1} == $kfplatformshared::player->{userId}){
		$game->{player1} = $kfplatformshared::player->{username};
		$game->{player2} = kfplatformshared::getusername($game->{player2});
		$game->{opponent} = $game->{player2};
		$game->{mydeck}=kfplatformshared::getdeckname($game->{deck1});
		delete ($game->{deck2});
		delete ($game->{deck1});
		
	}else{
		$game->{player2} = $kfplatformshared::player->{username};
		$game->{player1} = kfplatformshared::getusername($game->{player1});
		$game->{mydeck}=kfplatformshared::getdeckname($game->{deck2});
		$game->{opponent} = $game->{player1};
		delete ($game->{deck1});
		delete ($game->{deck2});
	}
	
	
}



kfplatformshared::end($response);
