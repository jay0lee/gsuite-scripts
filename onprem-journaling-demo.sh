#!/bin/bash

# make sure we only run once at VM creation
# additional reboots exit immediately
if [ -a /root/.startup-script-ran ]
then
  echo "startup script already ran once"
  exit 0
else
  touch /root/.startup-script-ran
fi

drive_url="https://3b8fad79b5c747b79cb1b61b95c7899523af31b5.googledrive.com/host/0B0YvUuHHn3MnTFM4azVHSm9waFE"
metadata_url="http://metadata.google.internal/computeMetadata/v1/instance/attributes/"
mailhost=`curl $metadata_url/mailhost -H "Metadata-Flavor: Google"`
userpass=`curl $metadata_url/userpass -H "Metadata-Flavor: Google"`

# start by making sure all installed packages
# are up to date.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y dist-upgrade

# install dbconfig-common ahead of other packages
# so we can preseed roundcube db settings
until apt-get -y install dbconfig-common
do
  echo "failed to install dbconfig-common, sleeping and trying again"
  sleep 10
  apt-get update
done

# write roundcube database settings ahead of package
# installation so that sqlite3 is used for the database
echo "dbc_install='true'
dbc_upgrade='true'
dbc_remove=''
dbc_dbtype='sqlite3'
dbc_dbuser='roundcube'
dbc_dbpass=''
dbc_dbserver=''
dbc_dbport=''
dbc_dbname='roundcube'
dbc_dbadmin=''
dbc_basepath='/var/lib/dbconfig-common/sqlite3/roundcube'
dbc_ssl=''
dbc_authmethod_admin=''
dbc_authmethod_user=''" > /etc/dbconfig-common/roundcube.conf

# install the packages we need. For some reason it
# fails every now and again so loop until success
packages="sqlite3 courier-mta courier-ssl courier-imap courier-maildrop roundcube whois php-mail-mimedecode"
echo "installing $packages"
until apt-get -y install $packages
do
  echo "failed to install packages, sleeping and trying again"
  sleep 10
  apt-get update
done

# turn on SSL for roundcube
a2enmod ssl
a2ensite default-ssl

# turn on mcrypt for roundcube
php5enmod mcrypt

# make roundcube app accessible at http://ip-or-hostname/
ln -s /usr/share/roundcube /var/www/html/roundcube
echo "<html><head><META http-equiv=\"refresh\" content=\"0;URL=/roundcube\"></head><body></body><html>" > /var/www/html/index.html

# create default maildir tree for Courier IMAP
maildirmake /etc/skel/Maildir
maildirmake /etc/skel/Maildir/.Junk
maildirmake /etc/skel/Maildir/.Drafts
maildirmake /etc/skel/Maildir/.Trash
maildirmake /etc/skel/Maildir/.Sent
echo "INBOX.Sent
INBOX.Drafts
INBOX.Trash
INBOX.Junk" > /etc/skel/Maildir/courierimapsubscribed

# Generate Courier MTA TLS Cert
/usr/lib/courier/mkesmtpdcert
cp /usr/lib/courier/esmtpd.pem /etc/courier
chown daemon.daemon /etc/courier/esmtpd.pem

# Tell Courier MTA what to do with mail for unknown local users
# (forward it to test-google-a.com shadow domain)
echo "||echo \$RECIPIENT.test-google-a.com" > /etc/courier/aliasdir/.courier-default

# Tell Courier MTA to accept mail for our domain
mkdir /etc/courier/esmtpacceptmailfor.dir/
echo $mailhost > /etc/courier/esmtpacceptmailfor.dir/system
echo $mailhost > /etc/courier/defaultdomain
echo $mailhost >> /etc/courier/locals
echo $mailhost > /etc/courier/me
makeacceptmailfor

# Set smtp-relay.gmail.com as smart SMTP host. Use port 587 since GCE
# doesn't allow outbound port 25.
echo ": smtp-relay.gmail.com,587" > /etc/courier/esmtproutes

# Use Courier Maildrop for mailbox filtering rules
ex -s /etc/courier/courierd << END_CMDS
%s/^DEFAULTDELIVERY=.*$/DEFAULTDELIVERY="| \/usr\/bin\/maildrop"/g
wq
END_CMDS

# Maildrop mailbox filter that puts Google-marked spam/phish in user Spam folder
# only used for users who don't exist in Google (mail routed by default
# routing rule)
echo "if (/^X-Gm-Spam:.*1/)
{
  exception {
    to \$DEFAULT/.Junk/
  }
}" > /etc/courier/maildroprc

# Turn on Courier archivedir for journaling
ex -s /etc/courier/courierd << END_CMDS
%s/^.*ARCHIVEDIR=.*$/ARCHIVEDIR="\/var\/lib\/courier\/journaling"/g
wq
END_CMDS

# create and set permissions on archivedr for journaling
mkdir /var/lib/courier/journaling
chown daemon.daemon /var/lib/courier/journaling

# grab shell and python scripts for journaling
wget -O /usr/local/bin/do-journaling.sh $drive_url/do-journaling.sh
wget -O /usr/local/bin/pyjournal.py $drive_url/pyjournal.py
chmod a+x /usr/local/bin/do-journaling.sh
chmod a+x /usr/local/bin/pyjournal.py
ex -s /usr/local/bin/do-journaling.sh << END_CMDS
%s/MAILHOST/$mailhost/g
wq
END_CMDS

# schedule journaling to run every minute. shell script prevents overlapping runs
echo "* * * * * root /usr/local/bin/do-journaling.sh > /dev/null 2>&1" > /etc/cron.d/journaling

# Tell roundcube to use localhost as IMAP server (Courier IMAP)
# en_US as language and mailhost value for user email addresses.
ex -s /etc/roundcube/main.inc.php << END_CMDS
%s/\$rcmail_config\[\'default_host\'\].*/\$rcmail_config['default_host'] = 'localhost';/g
%s/^\$rcmail_config\[\'mail_domain\'\].*/\$rcmail_config['mail_domain'] = '$mailhost';/g
%s/^\$rcmail_config\[\'language\'\].*$/\$rcmail_config['language'] = 'en_US';/g
wq
END_CMDS

# Create users onprem00 - onprem99
for i in {00..99}
do
  useradd -p `echo $userpass | mkpasswd -m sha-512 -s` onprem$i -m
done

# Reboot or restart services as required
# so that upgrades and config changes are applied
if [ -a /var/run/reboot-required ]
then
  reboot
else
  service apache2 restart
  service courier-mta restart
fi
