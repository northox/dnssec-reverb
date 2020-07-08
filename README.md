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
* standard unix tools such as sed & awk

## Installation
1. Copy dnssec-reverb in a directory in your $PATH.

    `$ sudo cp dnssec-reverb /usr/local/sbin/`

2. Create a configuration file. The config file will be searched in the following order 1) by looking at the `$DNSSEC_REVERB_CONF` environment variable, 2) within the same directory than the script (`dirname $0`), 3) within `/etc/` and finally 4) within `/usr/local/etc/`. At the very least it must specify the master zone file directory using the MASTERDIR variable. Optionnaly, specific domain parameters can be set - see the configuration section.

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
    
You can validate your DNSSEC setup using this web app: http://dnsviz.net/d/mantor.org/dnssec/

## Configuration
To override the default configuration (as describe below in parentheses), simply edit `dnssec-reverb.conf`.

Paths | default value:
* MASTERDIR: Master zone file directory | **mandatory - no default**
* DBDIR: directory used to store state and data | $MASTERDIR/dnssec-reverb-db
* keygen: ldns-keygen path | $(which ldns-keygen)
* signzone: ldns-signzone path | $(which ldns-signzone)
* key2ds: ldns-key2ds path | $(which ldns-key2ds)
* checkzone: nsd-checkzone path | $(which nsd-checkzone)
* control: nsd-control path | $(which nsd-control)
* RELOAD_COMMAND: reload command | (echo -n 'reload is '; $control reload) && (echo -n 'notify is '; $control notify)

Params - default value:
* KSK_PARAM: keygen's options for KSK | '-a ECDSAP256SHA256 -k'
* ZSK_PARAM: keygen's options for ZSK | '-a ECDSAP256SHA256'
* SIGN_PARAM: signzone options | '-n' (NSEC3)
* DS_PARAM: key2ds or dsfromkey options | '-2' (SHA256)

Signatures expiration:
* EXPIRE_DAYS: used to calculate the expiration date of the signatures to this date. Defaults to 33.

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
1. Generate KSK and ZSK.

    `dnssec-reverb keygen example.org`

2. Retrieve your fresh KSK's digest and setup the DS at your registrar.

    `dnssec-reverb status example.org` 

3. Sign zone using keys generated in step #1.

    `dnssec-reverb sign example.org`

## Rollover of the KSK

### Manual
1. Add and publish an additional but not valid/signed KSK. After this operation you will have two KSK, one active/signed by your registrar and a new one not active/signed.

   `dnssec-reverb --sign ksk-add example.org`

2. After allowing some time for propagation use the information provided by the `status` command to change the valid KSK within the DNSSEC interface of your domain registrar. You'll need the id, type of algo, type of hash and the digest of the active KSK.

   ```
   # dnssec-reverb status example.org
   example.org
    type state  id    algo hash (digest)
    KSK  active 27288 13   2    4b80b5003008cb032c31748e8b4ea139627dd75359f1bba415ae6695b5b47b26
    ZSK  active 02272 13   2
         next   06178 13   2
   ```

3. After allowing some time for propagation, roll our the new KSK and remove the old one.

   `dnssec-reverb ksk-roll example.org`

### Automated
1. Set something similar in your crontab. It will automatically add a new KSK and - assuming your email are setup correctly - send an email when you need to take action with your registrar. Optionally, you could replace the later with a script calling your registrar API to complete the rollover automagically.

```
0	0	1	dec		*   dessec-reverb ksk-add example.org
0	0	1	jan		*   dessec-reverb ksk-roll example.org
```

## Rollover of the ZSK

### Manual
1. Add and publish an additional and valid/signed ZSK. After this operation you will have two active ZSK.

    `dnssec-reverb --sign zsk-add example.org`

2. After allowing some time for the propagation you are ready to remove the old ZSK.

    `dnssec-reverb -s zsk-roll example.org`

3. Remove the old ZSK from reverb active records

    `dnssec-reverb zsk-rmold example.org`  
    `dnssec-reverb sign example.org`

### Automated
Set something similar in your crontab. It will roll the ZSK at a 3 months interval by adding the new ZSK one month before publishing it and removing the old a month later.
```
0       6       1       jan,apr,jul,oct *   dnssec-reverb -s zsk-add example.org
0       6       1       feb,may,aug,nov *   dnssec-reverb -s zsk-roll example.org
0       6       1       mar,jun,sep,dec *   dnssec-reverb -s zsk-rmold example.org
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
