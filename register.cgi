#!/usr/bin/perl
use strict "vars";
use lib qw(. /usr/lib/cgi-bin/kfplatform);
use Email::Valid;
use MIME::Lite;
use CGI qw(:all);
use shared;
use Digest::MD5  qw(md5 md5_hex md5_base64);
	
$kfplatformshared::dbh=kfdbplatform::connectdb();
my $response={};
my $query=new CGI;
my @errors;
my %input;
foreach my $a ($query->param){
	next unless param("$a");
	$input{$a} = param("$a");
	chomp($input{$a});
}
if ($input{password} ne $input{password2}){
	push(@errors, "Error, passwords don't match, try again\n");
}
foreach my $a (qw(username password password2 email)){
	unless ($input{$a}){
		push(@errors,"Error, field $a required!<BR>");
	}
}
if (@errors){
    $response->{status} = "Failed: @errors";
    kfplatformshared::end($response);
}
#We didn't error, make account now
$kfplatformshared::dbh->do("INSERT INTO `UserLogin`(email) VALUES(?)", undef, $input{email});
my $id=$kfplatformshared::dbh->last_insert_id();
my $key =  join '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[rand 64, rand 64];
my $code = "";
for ( 1..10){
    $code.=('.', 0..9, 'A'..'Z', 'a'..'z')[rand 63];
}
my $password2 = crypt($input{password}, $key);
$kfplatformshared::dbh->do("INSERT INTO `Users` (userid, UserName, Password, verified, code) VALUES(?, ?, ?,?,?)", undef, ($id, $input{username}, $password2, 0, $code));

$kfplatformshared::dbh->do("INSERT INTO `Inventory` (`sku`, `number`, `accountBound`, `userId`) VALUES (?, ?, ?, ?)", undef, ("Currency.Gold", 100000, 1, $id));
#send_account_email(\%input, $code);


$response->{status}="Success";
kfplatformshared::end($response);




sub send_account_email{
	my ( $params, $activation ) = @_;
	foreach my $keys (keys %{$params}){
		$params->{$keys}=~s/'//g;
		$params->{$keys}=~s/\n//gs;
	}
	$params->{activation} = $activation;

        my $msg = MIME::Lite->new(
                 From    => 'Kaelari\'s Game <userhelp@solforgeladder.com>',
                 To      => "$params->{username} <$params->{email}>",
                 Subject => 'Welcome to Kaelari\'s ladder an unofficial solforge ladder.',
                 Data => "Welcome, your code is $params->{activation}",
                );
    
        $msg->send();
	
	
}


