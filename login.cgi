#!/usr/bin/perl
use strict "vars";

use lib qw(. /usr/lib/cgi-bin/kfplatform);
use Digest::MD5 qw(md5_hex);
use shared;
use CGI param;
use Data::Dumper;
my $ip=$ENV{'REMOTE_ADDR'};
my $response={};
$kfplatformshared::dbh=kfdbplatform::connectdb();
my %input;
foreach my $a (qw(username password)){
	if (param($a)){
		$input{$a}=param($a);
	}
}


if (!$input{username} or !$input{password}){
    $response->{status}="Failed";    
    $response->{message}="no username or password Failed";    
    kfplatformshared::end($response);
}

my $sql = "SELECT * from `UserLogin` WHERE `email` = ?";
my $hashref = $kfplatformshared::dbh->selectrow_hashref($sql, undef, ($input{username}));

if (!$hashref->{email}){
    $response->{status}="Failed";
    $response->{message}="No username in db: '$input{username}'".Dumper($hashref);
    kfplatformshared::end($response);
}
my $playerdata = $kfplatformshared::dbh->selectrow_hashref("SELECT * from `Users` WHERE `userid` = ?", undef, ($hashref->{userId}));
my $sid;    
my $password=param("password");
if ( (crypt($password, $playerdata->{password}) eq $playerdata->{password}) and $hashref->{email}  ) {
# successful login
    
    for (1..40){
        $sid .= ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64];    
    }
    $kfplatformshared::dbh->do("INSERT INTO `sessionId`(session, userid) VALUES(?, ?)", undef, ($sid, $hashref->{userId}));
    $response->{session}=$sid;
    $response->{status}="Success";   
    $response->{lastNumber} = $kfplatformshared::dbh->selectrow_arrayref("SELECT `messageId` from `messages` ORDER BY `messageId` DESC limit 1", undef)->[0];
	$playerdata->{password} = "";
	$response->{playerid} = $playerdata->{userId};
    $response->{name} = $playerdata->{username};
    $response->{avatarnum} = $playerdata->{avatarnum};
    kfplatformshared::end($response);
    
}else {
#bad pw
    $response->{status}="Failed";    
    
    
    kfplatformshared::end($response);

}
