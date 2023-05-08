#!/usr/bin/perl -w
package empty;
use lib qw(. /usr/lib/cgi-bin/kfplatform);

BEGIN {
	
	use strict;
	use CGI qw(param);	
	$kfplatformshared::dbh=kfdbplatform::connectdb();
	
}
my $response = {};

kfplatformshared::init();
if (!kfplatformshared::loggedin){
	$response->{status} = "Failed";
	$response->{message} = "Not Logged in";
	kfplatformshared::end($response);
}

my $deckid=param("deckid");
my $deckname = param("deckname");
my $deck = param("deck");

if (!$deck) {
	exit;
}
if (!$deckname) {
	my $foo=$kfplatformshared::dbh->selectrow_hashref("SELECT count(*) as total from `Decks` WHERE `ownerid` = ?", undef,  ($kfplatformshared::player->{userId}));
	$deckname="unnamed deck($foo->{total})";
}
my @cards = split(/, ?/, $deck);
my @formats;
if (checkstandard(\@cards)){
	push (@formats, "Standard");
}

$formatstring=join(", ", @formats);

my $foo=$kfplatformshared::dbh->selectrow_hashref("Select * from `Decks` where `ownerid` = ? and `deckname` = ? and `eventid` = 0 and `deckid` <> ?", undef, ($kfplatformshared::player->{userId}, $deckname, $deckid));
	my $count=0;
	my $decknamebase=$deckname;
	while ($foo) {
		$count+=1;
		$deckname=$decknamebase."($count)";
		$foo=$kfplatformshared::dbh->selectrow_hashref("Select * from `Decks` where `ownerid` = ? and `deckname` = ? and `eventid` = 0 and `deckid` <> ?", undef, ($kfplatformshared::player->{userId}, $deckname, $deckid));		
	}



if ($deckid <=0){ 
	#not overwrite, this is a new deck. will check if we already have a deck with this name;
	
	
	$kfplatformshared::dbh->do("INSERT INTO `Decks`(`ownerid`, `deckname`, `cards`, `formats`) VALUES(?,?,?, ?)", undef, ($kfplatformshared::player->{userId}, $deckname, $deck, $formatstring));
}else {
	
	
	
	
	$kfplatformshared::dbh->do("UPDATE `Decks` SET `deckname` = ?, `cards` = ?, `formats` = ? WHERE `deckid` = ? and `ownerid` = ? and `eventid` = 0", undef, ($deckname, $deck, $formatstring, $deckid, $kfplatformshared::player->{userId}) );
}




kfplatformshared::end($response);


sub checkstandard {
	my $cards = shift;
	if (scalar @{$cards} != 30){
		return 0;
	}
	my %cards;
	foreach my $card (@{$cards}){
		$cards{$card}+=1;
	}
	 foreach my $card (keys %cards){
		if ($cards{$card}>3){
			return 0
		}
	 }
	 return 1;
}

