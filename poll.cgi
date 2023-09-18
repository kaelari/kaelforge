#!/usr/bin/perl -w
local $/;
#warn "Starting poll request";
use strict;
use CGI qw(param);


$kfplatformshared::dbh=kfdbplatform::connectdb();

my $response = {};
kfplatformshared::init();
my $lastNumber=(param("lastNumber") or 0);
$response->{messages}=$kfplatformshared::dbh->selectall_arrayref("SELECT `date`, `messageId`, `message` from `messages` WHERE `messageId` > ? AND `userId` = ?", {Slice => {}}, ($lastNumber, $kfplatformshared::player->{userId}));



kfplatformshared::end($response);


