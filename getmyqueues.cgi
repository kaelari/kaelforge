#!/usr/bin/perl -w
use lib qw(. /usr/lib/cgi-bin/kfplatform);
use Data::Dumper qw (Dumper);
	
	use strict;
	use CGI qw(param);	
	$kfplatformshared::dbh=kfdbplatform::connectdb();
	

my $response = {};
kfplatformshared::init();

$response->{result}=$kfplatformshared::dbh->selectall_arrayref("SELECT * from `queue` where `playerid` = ?", {Slice=>{}}, ($kfplatformshared::player->{userId}));
foreach my $data (@{$response->{result}}){
	my $deckname = $kfplatformshared::dbh->selectrow_hashref("SELECT * from `Decks` WHERE `deckid` = ?", undef, ($data->{deckid}));
	$data->{deckname}=$deckname->{deckname};

}

kfplatformshared::end($response);
