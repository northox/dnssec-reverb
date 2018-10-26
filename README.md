# dnssec-reverb
Shell script based DNSSEC key management tool

I was looking for something that would take care of the rotation of my DNSSEC keys that wouldn't require many dependencies, was simple to manage and that I could actually trust - easily auditable. I found an unmaintained script called dnsseczonetool from @kfujiwara and refactor it to fit my needs. It is used and tested on OpenBSD but should work pretty much anywhere with the proper paths.

Reverb is straightforward and couldn't be more trustable/easy to audit. Enjoy!

## Features
* Supports nsd and bind servers
* Supports ldns and bind's dnssec tools
* Should run on any unix-like systems&trade;
* Don't trust me, audit the code!&trade;
* KISS&reg;
* auto increment of the serial (date format)

## Requirements
* nsd or bind
* ldns from NLnet labs or bind's DNSSEC tools
* standard unix tools such as sed

## Installation
1. Copy dnssec-reverb into some directory.

    `$ sudo cp dnssec-reverb /usr/local/sbin/`

2. Create a configuration file. In order of priority, the config will be searched 1) by looking at the `$DNSSEC_REVERB_CONF` environment variable, 2) within the same directory than the script (`dirname $0`), 3) within `/etc/` and finally 4) within `/usr/local/etc/`. It must specify the master zone file directory using the MASTERDIR variable.

    ```
    echo MASTERDIR="/var/nsd/zones/master" >> /etc/dnssec-reverb.conf
    echo ZSK_PARAM_example.org="-a RSASHA1-NSEC3-SHA1" >> /etc/dnssec-reverb.conf
    ```

3. Prepare the traditional zone files and set the serial to this special tag: `_SERIAL_`. The file name should be equal to the zone name.

    ```
    $ grep serial example.org
    @ IN SOA ns1.example.org. dnsmaster.example.org. (
    _SERIAL_   ; serial
    1h         ; refresh (1 hours)
    1h         ; retry (1 hour)
    5w         ; expire (4 weeks)
    30m        ; minimum (30 minutes)

    ```
    
4. Edit nsd.conf to load the **signed** zone file:

    ```
    zone "example.org" {
        type master;
        file "/var/nsd/zones/master/example.org.signed";
    }
    ```

5. Generate first key and sign zone:

    ```
    dnssec-reverb keygen example.org
    dnssec-reverb sign example.org
    ```
    
You can debug your DNSSEC chain using this tool: http://dnsviz.net/d/mantor.org/dnssec/

## Configuration
To override the default configuration (as describe below in parentheses), simply edit `dnssec-reverb.conf`.

Path:
* MASTERDIR: Master zone file directory (**mandatory - no default**)
* DBDIR: directory used to store state and data ($MASTERDIR/dnssec-reverb-db)
* keygen: ldns-keygen path (/usr/local/bin/ldns-keygen)
* signzone: ldns-signzone path (/usr/local/bin/ldns-signzone)
* key2ds: ldns-key2ds path (/usr/local/bin/ldns-key2ds-n)
* checkzone: nsd-checkzone path (/usr/sbin/nsd-checkzone)
* control: nsd-control path (/usr/sbin/nsd-control)
* RELOAD_COMMAND: reload command ($checkzone \$ZONE \$ZONE || exit 1; $control reload && $control notify)

Signatures expiration:
* EXPIRE_DAYS: used to calculate the expiration date of the signatures to this date. Defaults to 33.

Params:
* KSK_PARAM: keygen's options for KSK (-a ECDSAP256SHA256 -k)
* ZSK_PARAM: keygen's options for ZSK (-a ECDSAP256SHA256)
* SIGN_PARAM: signzone options (-n)
* DS_PARAM: key2ds or dsfromkey options (-n -2)

The previous configuration set can be overridden by zone by simply adding "\_$zone" at the end of the variable. For example: ZSK_PARAM_example.org="-a RSASHA1-NSEC3-SHA1" to change the cipher for example.org's keys only. All zone name must be lowercase. Zone whose name contains '.' and '-' characters are replaced by '_'.

## Usage
```
$ dnssec-reverb
usage: dnssec-reverb keygen <zone>
       dnssec-reverb rmkeys <zone>
       dnssec-reverb [-s] ksk-add <zone>
       dnssec-reverb [-s] ksk-roll <zone>
       dnssec-reverb [-s] zsk-add <zone>
       dnssec-reverb [-s] zsk-roll <zone>
       dnssec-reverb [-s] zsk-rmold <zone>
       dnssec-reverb sign <zone>
       dnssec-reverb status <zone>
```

### Initial setup - assuming your zone has no DNSSEC keys published
1. Generate KSK and ZSK:

    `dnssec-reverb keygen example.org`

2. Retrieve your fresh KSK's fingerprint and setup the DS at your registrar:

    `dnssec-reverb status example.org`  

3. Sign zone using keys generated in step #1:

    `dnssec-reverb sign example.org`

## Rollover of the KSK
TODO

## Rollover of the ZSK

### Manual
1. Add next ZSK for future ZSK rollover (publish the upcomming ZSK and sign with active key) 

    `dnssec-reverb --sign zsk-add example.org`

2. ZSK rollover (set the published but latent ZSK created at step #3 as the active ZSK) 

    `dnssec-reverb -s zsk-roll example.org`

3. ZSK remove old (remove the old ZSK from your records)

    `dnssec-reverb zsk-rmold example.org`  
    `dnssec-reverb sign example.org`

### Automated
Set something similar in your crontab. This will roll the ZSK at a 4 months interval by adding the new ZSK one month ahead before publishing it and removing the old one one month later.
```
0       6       1       feb,jun,oct *   dnssec-reverb -s zsk-add example.org
0       6       1       mar,jul,nov *   dnssec-reverb -s zsk-roll example.org
0       6       1       apr,aug,dec *   dnssec-reverb -s zsk-rmold example.org
```

## License
Simplified BSD

## Source
https://github.com/northox/dnssec-reverb

## Acknowledgements
This code is heavily based on @kfujiwara [work's](https://github.com/kfujiwara/dnsseczonetool).

# Author(s)
Danny Fullerton - Mantor Organization  
@kfujiwara
