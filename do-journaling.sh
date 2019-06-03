#!/bin/bash

running_commands=$(ps -ef | grep -v grep | grep -c `basename $0`)
if (($running_commands > 3))
then
  echo "already running $running_commands"
  exit 0
fi

for cfile in /var/lib/courier/journaling/*/C*
do
  dfile=${cfile/C/D}
  recipients_argument=""
  while read -r line
  do
    recipients_argument="$recipients_argument --recipient $line"
  done < <(grep -P '^r' $cfile | cut -c 2-)
  
  /usr/local/bin/pyjournal.py $recipients_argument \
    --smtp_server smtp-relay.gmail.com:587 \
    --journal_from journal@MAILHOST \
    --journal_address journal@MAILHOST \
    --file $dfile --debug

  journal_returncode=$?
  if [ $journal_returncode -eq 0 ]
  then
    rm $cfile
    rm $dfile
  fi
done
