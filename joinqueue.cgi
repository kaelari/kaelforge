#!/usr/bin/perl -w
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);

use CGI qw(param);
$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response = {};
kfplatformshared::init();

my $eventid=param("eventid");
my $deckid=param("deckid");
my $eventdata;
my $eventbasedata;

if ($eventid){
	$eventdata= $kfplatformshared::dbh->selectrow_hashref("SELECT * from `Playerevents` WHERE `rowid` = ?", undef, ($eventid));
	$eventbasedata=$kfplatformshared::dbh->selectrow_hashref("SELECT * from `events` where `EventId` = ?", undef, ($eventdata->{eventid}));
	if ($eventdata->{Status} ne "Entered"){
		$response->{status}="failed";
		$response->{reason}="Already queued or haven't finished drafting or some other issue. $eventdata->{Status}";
		kfplatformshared::end($response);
		exit;
	}
	$kfplatformshared::dbh->do("UPDATE `Playerevents` SET `status` = ? WHERE `rowid` = ?", undef, ("Queued", $eventid));
	$kfplatformshared::dbh->do("INSERT INTO `queue`(`playerid`,`queuekey`, `deckid`,`eventid`)VALUES(?,?,?,?)", undef, ( $kfplatformshared::player->{userId}, $eventbasedata->{queuekey}, $eventdata->{DeckId}, $eventid ));

}elsif ($deckid) {
	my $alreadyin = $kfplatformshared::dbh->selectrow_hashref("SELECT * from `queue` WHERE `queuekey` = ? and `playerid` = ?", undef, ("constructed", $kfplatformshared::player->{userId}));
	if ($alreadyin) {
		$response->{status}="failed";
		$response->{reason}="Already in Queue";
		kfplatformshared::end($response);
		exit;
	}
	my $deckinfo= $kfplatformshared::dbh->selectrow_hashref("SELECT * from `Decks` WHERE `deckid` = ? AND `ownerid` = ?", undef , ($deckid, $kfplatformshared::player->{userId}));
	if ($deckinfo->{formats}=~/standard/i){
		$kfplatformshared::dbh->do("INSERT INTO `queue`(`playerid`,`queuekey`, `deckid`,`eventid`)VALUES(?,?,?,?)", undef, ( $kfplatformshared::player->{userId}, "constructed", $deckid, 0));
	}else {
		$response->{status}="failed";
		$response->{reason}="Deck Not Legal";
		kfplatformshared::end($response);
		exit;
	}

}else {
	$response->{status}="failed";
	$response->{reason}="no event or deck";
	kfplatformshared::end($response);
	exit;
}



kfplatformshared::end($response);
