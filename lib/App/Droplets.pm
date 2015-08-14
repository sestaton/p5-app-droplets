package App::Droplets;

use 5.010;
use File::Spec;
use File::Basename;
use Expect;
use Config::Tiny;
use UUID::Tiny      qw(:std);
use WebService::DigitalOcean;
use Data::Dump;

our $VERSION = '0.01';

#
# methods
#
sub new {
    my ($class, %args) = @_;

    my $self = bless {}, $class;
    $self->{opts} = $args{opts};

    return $self;
}

sub run {
    my $self = shift;
    my $opt  = $self->{opts};

    $opt = $self->configure($opt);
    my $token = $self->get_token($opt);
 
    my $do_obj = WebService::DigitalOcean->new({ token => $token });
    
    if ($opt->{available}) {
	$self->report_available($do_obj, $opt->{available});
    }
    
    if ($opt->{running}) {
	$self->get_droplets($do_obj);
	exit(0);
    }

    my $server_addr = $self->create_droplet($do_obj, $config, $opt) if $opt->{create};
    
    if ($opt->{login}) {
	my $cmd;
	if (defined $opt->{serverid}) {
	    my $ip = $self->get_address_for_droplet($do_obj, $opt->{serverid});
	    $cmd = sprintf "ssh root@%s", $ip;
	    my $ssh = Expect->new;
	    $ssh->raw_pty(1);
	    $ssh->slave->clone_winsize_from(\*STDIN);
	    $ssh->spawn($cmd);
	    $ssh->interact();
	    $ssh->close();
	}
	else {
	    $cmd = sprintf "ssh root@%s", $server_addr;
	    my $ssh = Expect->new;
	    $ssh->raw_pty(1);
	    $ssh->slave->clone_winsize_from(\*STDIN);
	    $ssh->spawn($cmd);
	    $ssh->interact();
	    $ssh->close();
	}
    }

    if ($opt->{destroy}) {
	my @ids = split /\,/, $opt->{serverid};
	$self->destroy_droplet($do_obj, \@ids);
    }

    if ($opt->{destroyall}) {
	$self->destroy_all($do_obj);
    }
}

sub configure {
    my $self = shift;
    my ($opt) = @_;

    my $conf_file = File::Spec->catfile($ENV{HOME}, '.droplets');;
    if (-e $conf_file) {
	my $config = Config::Tiny->read( $conf_file, 'utf8' );
	return $opt if defined $config->{droplets}->{api_token};
    }
    elsif (defined $opt->{configfile}) {
	my $config = Config::Tiny->read( $opt->{configfile}, 'utf8' );
	return $opt if defined $config->{droplets}->{api_token};
    }
    else {
	print STDERR "\nApp::Droplets is not configured. Please provide your API token: ";
	my $token = <STDIN>;
	chomp $token;
	open my $out, '>', $conf_file;
	say $out "[droplets]";
	say $out "api_token = $token";
	close $out;

	$opt->{configfile} = $conf_file;
	return $opt;
    }
}

sub get_token {
    my $self = shift;
    my ($opt) = @_;

    $opt->{configfile} //= File::Spec->catfile($ENV{HOME}, '.droplets');
    my $config = Config::Tiny->read( $opt->{configfile}, 'utf8' );

    unless (defined $config->{droplets}->{api_token}) {
	say "\nERROR: The configuration is not formatted correctly. Exiting.\n";
	exit(1);
    }
    
    return $config->{droplets}->{api_token};
}

sub destroy_all {
    my $self = shift;
    my ($do_obj) = @_;

    my $droplets = $do_obj->droplet_list();

    my @ids;
    if ($droplets->{meta}{total} > 0) {
	for my $drop (@{$droplets->{content}}) {
	    if (defined $drop) {
		for my $ip (@{$drop->{networks}{v4}}) {
		    push @ids, $drop->{id};
		}
	    }
	}
    }

     $self->destroy_droplet($do_obj, \@ids);
}

sub destroy_droplet {
    my $self = shift;
    my ($do_obj, $ids) = @_;

    unless (@$ids) {
	say "\nERROR: Need at least 1 server ID to call destroy method. Exiting.\n";
	exit(1);
    }
    
    say "====> Before destroy...";
    $self->get_droplets($do_obj);
    for my $id (@$ids) {
	if (defined $id) {
	    $do_obj->droplet_delete($id);
	}
    }
    sleep 10;
    say "====> After destroy...";
    $self->get_droplets($do_obj);
}

sub create_droplet {
    my $self = shift;
    my ($do_obj, $config, $opt) = @_;

    my $ssh_id = $self->get_keys($config);
    $opt->{region}  //= 'sfo1';        # San Francisco
    $opt->{size}    //= '512mb';       # 512MB
    $opt->{name}    //= create_uuid_as_string(UUID_V1);
    $opt->{imageid} //= 10322623;      # CentOS 7 x64
    
    my $t0 = time;
    my $droplet = $do_obj->droplet_create({
	name       => $opt->{name},
	size       => $opt->{size},
	image      => $opt->{imageid},
	region     => $opt->{region},
	ssh_keys   => [ $ssh_id ],
    });
    my $t1 = time;

    sleep 5;
    my $server = $do_obj->droplet_get($droplet->{content}{id});
    my $ip = $self->get_address_for_droplet($do_obj, $server->{content}{id});
        
    say "---------------------------------------------------";
    say "Created Droplet:         ", $server->{content}{id}; 
    say "Droplet name:            ", $server->{content}{name}; 
    say "Distribution:            ", $server->{content}{image}{distribution}.q{ }.$server->{content}{image}{name};
    say "Region:                  ", $server->{content}{region}{name};
    say "Disk:                    ", $server->{content}{size}{disk};
    say "Memory:                  ", $server->{content}{size_slug};
    say "CPUs:                    ", $server->{content}{vcpus};
    say "Server IP:               ", $ip;
    say "Creation time (seconds): ", $t1-$t0;
    say "---------------------------------------------------";

    return $server->{content}{networks}{v4}[0]{ip_address};
}

sub report_available {
    my $self = shift;
    my ($obj, $available) = @_;

    my %disp = (
	'sizes'   => sub { $self->get_sizes($obj)   },
	'images'  => sub { $self->get_images($obj)  },
	'regions' => sub { $self->get_regions($obj) },
    );

    if (defined $available && exists $disp{$available}) {
	$disp{$available}->();
    }
    else {
	say "\nERROR: '$available' is not recognized. ".
	    "Argument must be one of: sizes, images, or regions. Exiting.\n";
	exit(1);
    }
    
    exit(0);
}
	
	
sub get_sizes {
    my $self = shift;
    my ($do_obj) = @_;
    
    my $sizes = $do_obj->size_list();

    say join "\t", "Name", "Disk_space", "Memory", "CPUs", "Cost_per_month", "Cost_per_hour", "Regions";
    for my $s (@{$sizes->{content}}) {
	say join "\t", $s->{slug}, $s->{disk}, $s->{memory}, $s->{vcpus}, 
	    $s->{price_monthly}, $s->{price_hourly}, join ',', @{$s->{regions}};
    }

    exit(0);
}

sub get_regions {
    my $self = shift;
    my ($do_obj) = @_;

    my $region_id;
    my $regions = $do_obj->region_list();
    
    say join "\t", "Name", "Slug", "Sizes";
    for my $r (@{$regions->{content}}) {
	say join "\t", $r->{name}, $r->{slug}, join ',', @{$r->{sizes}};
    }

    exit(0);
}

sub get_images {
    my $self = shift;
    my ($do_obj) = @_;
    
    my $image_id;
    my $images = $do_obj->image_list();

    say join "\t", "Distribution", "ID", "Name";
    for my $img (@{$images->{content}}) {
	say join "\t", $img->{distribution}, $img->{id}, $img->{name};
    }

    exit(0);
}

sub get_keys {
    my $self = shift;
    my ($config) = @_;

    ## this creates a new key fingerprint
    my $key = File::Spec->catfile($ENV{HOME}, '.ssh', 'id_rsa.pub');
    my $cmd = "ssh-keygen -lf $key";
    my $out = qx($cmd);
    chomp $out;
    my ($bits, $fingerprint, $identity) = split /\s+/, $out;

    return $fingerprint;
}

sub get_address_for_droplet {
    my $self = shift;
    my ($do_obj, $id) = @_;

    my $sid = ref($id) ? shift(@$id) : $id;

    #if (ref($id) eq 'ARRAY') {
	#$sid = shift @$id;
    #}
    #else {
	#$sid = $id;
    #}

    #say STDERR join q{ }, $sid, $id; # and exit;
    my $server = $do_obj->droplet_get($sid);
    my $ip = $server->{content}{networks}{v4}[0]{ip_address};
    
    return $ip;
}

sub get_droplets {
    my $self = shift;
    my ($do_obj) = @_;

    my $droplets = $do_obj->droplet_list();

    my @ips;
    if ($droplets->{meta}{total} > 0) {
	say "Running Droplets: ";
	for my $drop (@{$droplets->{content}}) {
	    if (defined $drop) {
		for my $ip (@{$drop->{networks}{v4}}) {
		    printf "Droplet %s has id %s, IP address %s, Gateway %s, and Netmask %s\n", 
	            $drop->{name}, $drop->{id}, $ip->{ip_address}, $ip->{gateway}, $ip->{netmask};
		}
	    }
	}
    }
    else {
	say "No running droplets.";
    }
}

1;