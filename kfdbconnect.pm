#!/usr/bin/perl
use DBI;
package kfdbplatform;
use strict "vars";
sub connectdb {
	my $dbh;
	my $host = "localhost";
	my $dbuser = "ladder";
	my $dbpass = "Zfe9utHrh2maFC6G";
	my $dbname = "KF_Platform";
	$dbh = DBI-> connect("DBI:mysql:$dbname:$host","$dbuser","$dbpass", {RaiseError=> 1, AutoCommit => 1,}) or die ("ACK! Can't connect to db");
	return $dbh;
}

sub checkconnect {
	my $dbh=shift;
	if ($dbh->ping){
		return $dbh;
	}
	return connectdb();
}
1;
