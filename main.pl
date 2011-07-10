#########################################################################
#########################################################################
### 
### Intel
### CloneZilla HWDEP Imaging
### Reads INI from the AWL Deployment Server
### and transposes the customer job information into clonezilla switches
###
### Re Written by david.m.oneill@intel.com ( dave@feeditout.com )
### Escalations and support
### oleg.v.gumenyuk@intel.com
### rafik.f.saliev@intel.com
###
#########################################################################
#########################################################################



###
### Includes
#########################################################################

use English;





###
### Globals
#########################################################################

my $debugEnabled = 1;

# network devices
my @validIfaces = ();

# hard drives
my @devices = ();

#partitions
my @volumes = ();

# ini file
my %job = ();





###
### Begin
#########################################################################

main();





###
### SUB : main
###
### Main subroutine and flow
#########################################################################

sub main
{
	@validIfaces = getNetAddress();

	for( my $x = 0 ; $x < @validIfaces; $x = $x + 2 )
	{
		#print getJob( $validIfaces[ $x ] );
	}

	getVolumes();

	%job = readJob();

	#mountVolume(  $job{ 'BackupImagesPath' } );

	imageOperation( %job , \@devices , \@volumes );
}





###
### SUB : getNetAddress
###
### Gets a list of network addresses and mac address
###
### @return an array where index n%2==0 ( mac ) , n%2==1 ( ip )
#########################################################################

sub getNetAddress
{
	my @validIfaces = ();
	my $tmp = "";	

	# get the ifconfig information
	my $if = `ifconfig -a`;	
	my @ifaces = split( /\n\n/ , $if );

	# look at each device
	foreach my $face ( @ifaces )
	{
		my @lines = split( /\n/ , $face );
				
		# get the mac address for the device
		$tmp = "echo \"$lines[0]\" | grep 'HWaddr' | tr -s ' ' | cut -d ' ' -f5";		
		my $mac = `$tmp`;

		# trim off any spaces and remove the : for use in the URL to the DS server later	
		$mac =~ s/\s+$//;
		$mac =~ s/\://g;
		
		# get the ip address of the device
		$tmp = "echo \"$lines[1]\" | grep 'inet ' | sed -n '1p' | tr -s ' ' | cut -d ' ' -f3 | cut -d ':' -f2";	
		my $ip = `$tmp`;

		# trim off unwanted spaces
		$ip =~ s/\s+$//;
		
		# if the mac or ip is empty ignore the device eg. ( lo )
		if( $mac ne "" && $ip ne "" )
		{
			push( @validIfaces , ( $mac , $ip ) );			
		}
	}
	
	return @validIfaces;
}





###
### SUB : buildDeviceList
###
### Creates and array of the physical volumes given the logical volumes
###
### @param the logical volume
### @param a reference to the array holding the list of phyical devices
#########################################################################

sub buildDeviceList
{
	use vars qw( $devices );

	my $vol = shift;	

	# trim away the number at the end of the volume 
	my $tmp = substr( $vol , 0 , -1 );
	
	# if there is still a number at the end, trim it again 
	if( substr( $tmp , length( $tmp ) - 2 , length( $tmp ) - 1 ) =~ /[0-9]/ )
	{
		$tmp = substr( $tmp , 0 , -1 );
	}
	
	# if there is still a number at the end, trim it again 
	if( substr( $tmp , length( $tmp ) - 2 , length( $tmp ) - 1 ) =~ /[0-9]/ )
	{
		$tmp = substr( $tmp , 0 , -1 );
	}

	# if there are no device currently
	# push the device into the devices array and return
	if( @devices == 0 )
	{
		push( @devices , $tmp );		
		return;
	}
	
	my $exists = 0;

	# check to see if we already have the device listed
	for( my $t = 0 ; $t < @devices ; $t++ )
	{
		if( $devices[ $t ] eq $tmp )
		{
			$exists = 1;
		}
	}
	
	# push the new device into the device list
	if( $exists == 0 )
	{
		push( @devices , $tmp );
	}	
}





###
### SUB : getVolumes
###
### Reads fdisk -l information and parsing it for a list of logical
### volumes, finally each logical volume is passed to the buildDeviceList
### subroutine where the list of unique phyical devices is created
###
#########################################################################

sub getVolumes
{
	use vars qw( $volumes );

	# get the fdisk information
	my $fdiskInfo = `fdisk -l 2>&1`;
	my @lines = split( /\n/ , $fdiskInfo );	

	# loop through the lines
	for( my $i = 0; $i < @lines; $i++ ) 
	{
		$subStr = substr( $lines[ $i ] , 0 , 5 );
		# only look at the device maps
		if( $subStr eq "/dev/" )
		{
			# trim away the * that represent the active partition
			$lines[$i] =~ s/\Q*\E/ /g;
			# now we can assign the columes of the match into these variables
			my( $vol , $startCynliner , $endCylinder , $Blocks , $id , $system ) = split( /\s+/ , $lines[ $i ] );	
			
			# split of the matched volume by "/"
			@parts = split( /\// , $vol );
			my $size = @parts;
			my $last = $parts[ $size - 1 ];	
			# pass the partition to the build device List to create a list of phyical devices	
			buildDeviceList( $last );		
			# make note of the partition
			push( @volumes , $last );
		}
	}
}





###
### SUB : getJob
###
### Attempts to retreive the job from the altiris server till given the 
### mac addresses present in the machines
###
### @param mac address to use in the job lookup
### @return 0 if not found or 1 found and downloaded
#########################################################################

sub getJob
{
	my $mac = shift;
	$mac = uc( $mac );	
	
	# fetch the ini file from the deployment server
	my $url = "http://altiris-ds/AWL/get_cfg_by_mac.asp?mac=" . $mac . "&cfgType=ini";
	#my $http_proxy = `export $proxy`;
	my $wgetResult = `wget $url -O /tmp/job.ini`;
	
	if( $wgetResult =~ /404 Not Found/ )
	{
		return 0;
	}
	
	return 1;
}





###
### SUB : mountVolume
###
### Attempts to mount the network share 
###
### @param the URI eg. 10.1.1.1:/some/share
### @return 0 ( failure )  / 1 ( success )
#########################################################################

sub mountVolume
{
	my $share = shift;
	my $cmd = "sudo mount $share /home/partimag";

	my $attempts = 0;
	my $check = "0";

	# simple loop to attempt the connection 3 times untill eventually fails
	# allow for network timeouts and dodgey connections
	while( $maxAttempts < 3 && $check ne "1" )
	{
		# execute the mount command and check if mounted
		my $exec = `$cmd`;
		my $check = `mount | grep $share | wc -l`;

		if( $check eq "0" )
		{
			# sleep for 3 seconds if mount not found
			sleep( 3 );
		}
		$maxAttempts++;
	}
	
	if( $check eq "1" )
	{
		return 1;
	} 
	else
	{
		return 0;
	}	
}





###
### SUB : readJob
###
### Atempts to prepare the Job.ini into an associstive array ( hash )
###
### @return 0 if failure or 1 succcess
#########################################################################

sub readJob
{
	$data_file = "/tmp/job.ini";
	# open the file
	if( open( FILE , $data_file ) )
	{
		# prep hash
		my %job = ();
		@data = <FILE>;

		foreach $line ( @data )
		{
			# time unwanted spaces
			$line =~ s/\s+$//;

			#ignore comments
			if( substr( $line , 0 , 1 ) ne ";" && $line ne "" )
			{
				#split by colon
				@entry = split( /:/ , $line );
				# set the key to be the entry name
				# set the value to be the entry value
				$job{ $entry[ 0 ] } = $entry[ 1 ];
			}
		}
		close( FILE );	
		return %job;
	}
	else
	{
		return 0;
	} 	
}





###
### SUB : imageOperation
###
### Constructs OCS-SR command given the job details present in the ini
#########################################################################

sub imageOperation
{
	my $job = shift;
	my $devices = shift;
	my $volumes = shift;
	my @nonmatching = ();
	my @matching = ();

	
	my @partitions = split( /,/ , $job{ 'Partitions' } );
	my $parts = "";


	# user requested operation on a disk number that is not available
	if( int( $devices[ $job{ 'DiskNumber' } ] ) > @devices )
	{
		debug( "Sub : " . ( caller( 0 ) )[ 3 ] . " , Line : " . __LINE__ );
		debug( "Harddrive number in imaging operation bigger than available drives" );
		debug( "Please resubmit the job confirming the correct disk, counting from 0 eg ( sda ) disk 0" ); 
		debug( "Available devices in order : @devices" );
		die "quitting";
	}

	# loop through the user requested partitions
	foreach my $vol( @partitions )
	{
		# given the disk append the user requested parition number to it
		my $tmp = $devices[ $job{ 'DiskNumber' } ] . $vol;

		# does this volume exist
		if( in_array( \@volumes , $tmp ) == 1 )
		{
			push( @matching , $tmp );
		}
		else
		{
			push( @nonmatching , $tmp );
		}
	}
	
	# request the userinput to confrim the job if there are any issues
	if( @nonmatching > 0 )
	{
		debug( "Sub : " . ( caller( 0 ) )[ 3 ] . " , Line : " . __LINE__ );		
		debug( "The $job{ 'Operation' } operation requested as found some questionable options" );	
		debug( "Unknown requested partitions : @nonmatching" );
		my $input = getUserInput( "Would you like to continue with the operation on \" @matching\" [y/n] : " );	
		
		while( $input !~ /^[y|n]/i )
		{
			$input = getUserInput( "Would you like to continue with the operation on \" @matching\" [y/n] : " );
		}

		if( $input =~ /[n]/i )
		{
			debug( "Dropping you to the console" );
			debug( "run /usr/bin/prerun.sh to restart" );
			die "";
		}
	}
	

	my $cmd;

	if( $job{ 'Operation' } eq "Backup" )
	{
	
		$cmd = "ocs-sr -q2 -j2 -z1 -p true -nogui saveparts \"" . $job{ 'ImageName' } . "\" \"@matching\"";
	
	}
	else
	{
		$cmd = "ocs-sr -p true -nogui restoreparts \"" . $job{ 'ImageName' } . "\" \"@matching\"";
	}

	print $cmd . "\n";
	
}





###
### SUB : in_array
###
### Searchs an array for a key
### @param array
### @param key to search for
### @return 1 found / 0  not found
#########################################################################

sub in_array
{
	my( $arr , $search_for ) = @_;
	my %items = map { $_ => 1 } @$arr;
	return ( exists( $items{ $search_for } ) ) ? 1 : 0;
}





###
### SUB : getUserInput
###
### Gets the user input from the console
### @param the question to ask
### @return the user input
#########################################################################

sub getUserInput
{
	$msg = shift;
	print "$msg";
	$input = <>;
	return $input;
}





###
### SUB : reportJob
###
### Report the job details to the altiris provisioning team server
#########################################################################

sub reportJob
{
	# to be done
}





###
### SUB : debug
###
### Used for debugging
### debugEnabled must be set to 1
###
### @param msg to be printed
#########################################################################

sub debug
{
	use vars qw( $debugEnabled );
	my $msg = shift;
	if( $debugEnabled == 1 )
	{
		print $msg . "\n";
	}
}

