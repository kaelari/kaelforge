#!/usr/bin/perl -w
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);
use Digest::MD5 qw(md5_hex);
use CGI param;
$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response = {};
kfplatformshared::init();
if (!$kfplatformshared::loggedin){
    $response->{status}="failed";
    $response->{message}="Not logged in";
    kfplatformshared::end($response);
}
my $event=param("event");
my $sku=param("sku");

my $eventdata=$kfplatformshared::dbh->selectrow_hashref("SELECT * from `events` WHERE `eventid` = ?", undef, ($event));

unless ($eventdata){
    $response->{status}="failed";
    $response->{message}="Event Not Found";
    end($response);

}

#check if we're already in the event
my $eventin = $kfplatformshared::dbh->selectrow_hashref("SELECT * from `Playerevents` WHERE `eventid` = ? and `playerid` = ? and `finished` = 0", undef, ($event, $kfplatformshared::player->{userId}));
if ($eventin){
    $response->{status}="failed";
    $response->{message}="Already joined this event";
    kfplatformshared::end($response);
}


my @costs = split(/,/, $eventdata->{EntryFees});
my $amount=0;
foreach my $cost (@costs){
    my ($costamount, $costsku) = split(/:/, $cost);
    
    if ($costsku eq $sku){
        #this is what we're paying with
        
        $amount = $costamount;
        last;
    }

}
if ($amount == 0 ){
    $response->{status}="failed";
    $response->{message}="Wrong currency selected?";
    
    kfplatformshared::end($response);
}
my $result=$kfplatformshared::dbh->selectrow_hashref("SELECT * from `Inventory` Where `sku` = ? and `number` >= ? and `userId` = ?", undef, ($sku, $amount, $kfplatformshared::player->{userId}));

if (!$result){
    $response->{status}="failed";
    $response->{message}="insufficient currency";
    kfplatformshared::end($response);
}
$kfplatformshared::dbh->do("UPDATE `Inventory` SET `number` = `number` - ? WHERE `rowid` = ?", undef, ($amount, $result->{rowid}));

if ($eventdata->{EventType} eq "Draft"){
    $kfplatformshared::dbh->do("INSERT INTO `Playerevents` (`playerId`, `eventid`, `status`, `gamesneeded`) VALUES(?,?,?, ?)", undef, ($kfplatformshared::player->{userId}, $event, "Drafting", $eventdata->{gamesneeded}));
}else {
    $kfplatformshared::dbh->do("INSERT INTO `Playerevents` (`playerId`, `eventid`, `status`, `gamesneeded`) VALUES(?,?,?, ?)", undef, ($kfplatformshared::player->{userId}, $event, "Entered", $eventdata->{gamesneeded}));
}
$amount=0-$amount;
kfplatformshared::sendmessage("new:$sku:$amount", $kfplatformshared::player->{playerId});


kfplatformshared::end($response);
