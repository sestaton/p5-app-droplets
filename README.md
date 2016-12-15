# App::Droplets

Create, destroy, inspect, and log on to your droplets from the command line

[![Build Status](https://travis-ci.org/sestaton/p5-app-droplets.svg?branch=master)](https://travis-ci.org/sestaton/p5-app-droplets)

**ABOUT**

This is a command-line tool for [DigitalOcean's](https://www.digitalocean.com/?refcode=c4cc062482a8) REST API called `droplets`. After setting up an API key on the [DigitalOcean](https://www.digitalocean.com/community/tutorials/how-to-use-the-digitalocean-api-v2) website, you can check on all your existing droplets, query the available droplet sizes and prices by region, create new droplets, or log on to droplets (either existing droplets or ones you just created) without leaving the command line. You can also destroy one or all your droplets in one command.

**INSTALLATION**

The following command will install the `droplets` application (note that this requires [git](http://git-scm.com/)):

    curl -sL cpanmin.us | perl - https://github.com/sestaton/digitalocean-cli.git

Alternatively, download the latest [release](https://github.com/sestaton/p5-app-droplets/releases) and run the following command in the top directory:

    perl Makefile.PL

If any Perl dependencies are listed after running this command, install them through the CPAN shell or any method you like. Then build and install the package.

    perl Makefile.PL
    make 
    make test
    make install

**USAGE**

The first time you run the tool you will be prompted for your API key (there is a link to a guide for setting up this token provided above in the **ABOUT** section of this document), so have that ready. Note that you also need to have your ssh keys set up with DigitalOcean. A configuration file (called ".droplets") will be stored in your home directory so you will not be prompted again. Once your key is stored, you are ready to go!

 Examples:

Let's see get some basic information.

    $ droplets --available sizes
    Name	Disk_space	Memory	CPUs	Cost_per_month	Cost_per_hour	Regions
    512mb	20	512	1	5	0.00744	nyc1,sgp1,ams1,sfo1,nyc2,lon1,nyc3,ams3,ams2,fra1
    1gb	30	1024	1	10	0.01488	nyc2,sgp1,ams1,sfo1,lon1,nyc3,ams3,nyc1,ams2,fra1
    2gb	40	2048	2	20	0.02976	nyc2,sfo1,ams1,sgp1,lon1,nyc3,ams3,nyc1,ams2,fra1
    4gb	60	4096	2	40	0.05952	nyc2,ams1,sgp1,lon1,nyc3,ams3,nyc1,ams2,sfo1,fra1
    8gb	80	8192	4	80	0.11905	nyc2,sgp1,ams1,nyc1,lon1,nyc3,ams3,ams2,sfo1,fra1
    16gb	160	16384	8	160	0.2381	sgp1,nyc1,nyc3,lon1,nyc2,ams1,ams3,ams2,sfo1,fra1
    32gb	320	32768	12	320	0.47619	nyc2,sgp1,nyc1,lon1,ams3,nyc3,ams2,sfo1,fra1
    48gb	480	49152	16	480	0.71429	sgp1,nyc1,lon1,nyc2,ams3,nyc3,ams2,sfo1,fra1
    64gb	640	65536	20	640	0.95238	sgp1,nyc1,nyc2,lon1,ams3,nyc3,ams2,sfo1,fra1

In the above output we can see the options available in different regions, along with the prices. Now, find out the available images..

    $ droplets --available images
    Distribution	ID	Name
    CoreOS	12789350	723.3.0 (beta)
    CentOS	6372321	5.10 x64
    CentOS	6372425	5.10 x32
    Debian	6372581	6.0 x64
    Debian	6372662	6.0 x32
    Fedora	9640922	21 x64
    FreeBSD	10144573	10.1
    Ubuntu	10321756	12.04.5 x64
    Ubuntu	10321777	12.04.5 x32
    Debian	10322059	7.0 x64
    Debian	10322378	7.0 x32
    CentOS	10322623	7 x64
    Fedora	12065782	22 x64
    Ubuntu	12658446	15.04 x64
    Ubuntu	12660649	15.04 x32
    Debian	12778278	8.1 x64
    Debian	12778337	8.1 x32
    CoreOS	13068283	723.3.0 (stable)
    Ubuntu	13089493	14.04 x64
    Ubuntu	13089823	14.04 x32

Now, let's create a droplet (in this case, Fedora 22)

    $ droplets --imageid 12065782 --create
    ---------------------------------------------------
    Created Droplet:         6588509
    Droplet name:            187ebaa6-42ac-11e5-bd97-de968ce03bd5
    Distribution:            Fedora 22 x64
    Region:                  San Francisco 1
    Disk:                    20
    Memory:                  512mb
    CPUs:                    1
    Server IP:               
    Creation time (seconds): 1
    ---------------------------------------------------

You can give the server a name, or just let a default be chosen, as above. If you want something you can remember, then specify a server name when you create the droplet. We should be able to see this droplet running if we check...

    $ droplets --running
    Running Droplets: 
    Droplet 187ebaa6-42ac-11e5-bd97-de968ce03bd5 has id 6588509, IP address 198.199.102.123, Gateway 198.199.102.1, and Netmask 255.255.255.0

You can log on to an existing server from the command line, or create one and log on. Here, we just use the defaults...

    $ droplets --create --login
    Droplet name:            908c31cf-42af-11e5-8d52-9bf6c9a52cfe
    Distribution:            CentOS 7 x64
    Region:                  San Francisco 1
    Disk:                    20
    Memory:                  512mb
    CPUs:                    1
    Server IP:               104.236.151.89
    Creation time (seconds): 1
    ---------------------------------------------------
    [root@908c31cf-42af-11e5-8d52-9bf6c9a52cfe ~]# ls
    [root@908c31cf-42af-11e5-8d52-9bf6c9a52cfe ~]# exit
    logout
    Connection to 104.236.151.89 closed.

You will notice the default is to log on as the root user. For images you plan to keep around, it is probably best to create regular user accounts using whatever methods apply for the Linux OS you created. Then, you can log on to the image using that user account instead of root:

    $ droplets --user evan --password somesecurepass --serverid 6588509 --logon
    [evan@908c31cf-42af-11e5-8d52-9bf6c9a52cfe ~]$

One final note about logging on to your droplets: you can use `--login`, `--logon` or `-l' to achieve the same purpose. I find this easier to work with than trying to remember the name of the command or having to look it up each time.

We can destroy a single droplet...

    $ droplets --destroy --serverid 6588509
    ====> Before destroy...
    Running Droplets:
    Droplet 187ebaa6-42ac-11e5-bd97-de968ce03bd5 has id 6588509, IP address 198.199.102.123, Gateway 198.199.102.1, and Netmask 255.255.255.0
    ====> After destroy...
    No running droplets.

Or, destroy all running droplets in one go. This convenient when you have a bunch of images that are no longer needed.

    $ droplets --destroyall
    ====> Before destroy...
    Running Droplets: 
    Droplet 908c31cf-42af-11e5-8d52-9bf6c9a52cfe has id 6588977, IP address 104.236.151.89, Gateway 104.236.128.1, and Netmask 255.255.192.0
    ====> After destroy...
    No running droplets.    


**SUPPORT AND DOCUMENTATION**

After installation, you can find documentation for App::Droplets with the `perldoc` command.

    perldoc droplets

The documentation can also be accessed by specifying the manual option with `droplets -m` or `droplets --man`. The `droplets` program will also print a diagnostic help message when executed with no arguments. **NB:** I mostly used long versions of options in the examples for clarity, but typing `droplets` will show the short versions of the options.

**ISSUES**

Report any issues or feature requests at the [issue tracker](https://github.com/sestaton/p5-app-droplets/issues).

**ATTRIBUTION**

This project uses the [Webservice::DigitalOcean](https://metacpan.org/pod/WebService::DigitalOcean) library to access the DigitalOcean APIv2.

**TODO**

- Add the option to change the defaults and store them in the configuration.

**LICENSE**

The MIT License should included with the project. If not, it can be found at: http://opensource.org/licenses/mit-license.php

Copyright (C) 2015-2016 S. Evan Staton