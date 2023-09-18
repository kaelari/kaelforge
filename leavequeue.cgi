#!/usr/bin/perl -w
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);

use CGI qw(param);
$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response = {};
kfplatformshared::init();

my $eventid=param("eventid");
my $queueid = param("queueid");
my $eventdata;
my $eventbasedata;
my $data = $kfplatformshared::dbh->selectrow_hashref("SELECT * from `queue` WHERE `playerid` = ? and `rowid` = ?", undef, ($kfplatformshared::player->{userId}, $queueid));
if (!$queueid){
	$response->{status}="failed";
	$response->{reason}="no queue id.";
	kfplatformshared::end($response);
	exit;
}


if ($data->{eventid}){
	$eventdata= $kfplatformshared::dbh->selectrow_hashref("SELECT * from `Playerevents` WHERE `rowid` = ?", undef, ($data->{eventid}));
#	$eventbasedata=$kfplatformshared::dbh->selectrow_hashref("SELECT * from `events` where `EventId` = ?", undef, ($eventdata->{eventid}));
	if ($eventdata->{Status} ne "Queued"){
		$response->{status}="failed";
		$response->{reason}="not queued or haven't finished drafting or some other issue. $eventdata->{Status}";
		kfplatformshared::end($response);
		exit;
	}
	$kfplatformshared::dbh->do("UPDATE `Playerevents` SET `status` = ? WHERE `rowid` = ?", undef, ("Entered", $data->{eventid}));
}else {
	
}

$kfplatformshared::dbh->do("Delete from `queue` where `rowid` = ? ", undef, ( $data->{rowid} ));


kfplatformshared::end($response);
