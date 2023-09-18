#!/usr/bin/perl -w
local $/;
#warn "Starting poll request";
use strict;
use CGI qw(param);


$kfplatformshared::dbh=kfdbplatform::connectdb();

my $response = {};
kfplatformshared::init();
if (!$kfplatformshared::loggedin){
    exit;
}
my $avatar=(param("avatar") or 0);
$kfplatformshared::dbh->do("UPDATE `Users` SET `avatarnum` = ? WHERE `userid` = ?", undef, ($avatar, $kfplatformshared::player->{userId}));



kfplatformshared::end($response);


