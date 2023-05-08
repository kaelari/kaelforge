#!/usr/bin/perl -w
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);
use shared;
use CGI qw(param);
$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response = {};
#kfplatformshared::init();
my $guest = kfplatformshared::getserverconfig("guest");
$guest+=int rand(10);
kfplatformshared::setserverconfig("guest", $guest);

$kfplatformshared::dbh->do("INSERT INTO `UserLogin`(email) VALUES(?)", undef, ($guest));
my $id=$kfplatformshared::dbh->{mysql_insertid};
my $key =  join '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];
my $code = "";
for ( 1..10){
    $code.=('.', 0..9, 'A'..'Z', 'a'..'z')[rand 63];
}
my $password2 = crypt("password", $key);
$kfplatformshared::dbh->do("INSERT INTO `Users` (userid, UserName, Password, verified, code) VALUES(?, ?, ?,?,?)", undef, ($id, "guest_$guest", $password2, 0, $code));

$kfplatformshared::dbh->do("INSERT INTO `Inventory` (`sku`, `number`, `accountBound`, `userId`) VALUES (?, ?, ?, ?)", undef, ("Currency.Gold", 100000, 1, $id));

#account is created now login to it
    my $sid = "";
    for (1..40){
        $sid .= ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64];    
    }
    $kfplatformshared::dbh->do("INSERT INTO `sessionId`(session, userid) VALUES(?, ?)", undef, ($sid, $id));
    $response->{session}=$sid;
    $response->{status}="Success";   
    $response->{lastNumber} = $kfplatformshared::dbh->selectrow_arrayref("SELECT `messageId` from `messages` ORDER BY `messageId` DESC limit 1", undef)->[0];
	$response->{playerid} = $id;
    



kfplatformshared::end($response);
