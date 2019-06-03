#!/usr/bin/env python
#
# Python Exchange Journal Creation Script
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""pyJournal is a command line tool that allows journaling of RFC822 messages.

"""

#global __name__, __author__, __email__, __version__, __license__
__program_name__ = 'pyJournal'
__author__ = 'Jay Lee'
__email__ = 'jayhlee@google.com'
__version__ = '0.01 Alpha'
__license__ = 'Apache License 2.0 (http://www.apache.org/licenses/LICENSE-2.0)'

import smtplib
from optparse import OptionParser
import sys
import string
import os
import random
import time
import datetime
import email
from email.parser import Parser
import email.utils
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.message import MIMEMessage

def SetupOptionParser():
  # Usage message is the module's docstring.
  parser = OptionParser(usage=__doc__)
  parser.add_option('-v', '--version',
    action='store_true',
    dest='version',
    help='just print version and then quit')
  parser.add_option('-d', '--debug',
    action='store_true',
    dest='debug',
    help='Turn on verbose debugging and connection information (for troubleshooting purposes only)')
  parser.add_option('-r', '--recipient',
    dest='recipients',
    action='append',
    default=[],
    help='Optional: Recipient to be associated with journaled message. Can be specified multiple times.')
  parser.add_option('--journal_from',
    dest='journal_from_address',
    help='Address to send journal addresses from')
  parser.add_option('-j', '--journal_address',
    dest='journal_address',
    help='Address to send journaled message to')
  parser.add_option('-f', '--file',
    dest='mail_file',
    help='Optional: file with rfc822 format email message to journal. If not specified a random message is generated')
  parser.add_option('-s', '--smtp_server',
    dest='smtp_server',
    help='SMTP Server/port to send journal message to, default is aspmx-l.google.com:25',
    default='aspmx-l.google.com:25')
  parser.add_option('--days_ago',
    dest='days_ago',
    type=int,
    help='day the message should be from.',
    default=0)
  return parser

def getProgPath():
  if os.path.abspath('/') != -1:
    divider = '/'
  else:
    divider = '\\'
  return os.path.dirname(os.path.realpath(sys.argv[0]))+divider

def restart_line():
  sys.stdout.write('\r')
  sys.stdout.flush()

def rand_email_part():
  return ''.join(random.choice(string.ascii_lowercase) for _ in range(random.randrange(3,10)))

def gen_random_email(days):
  _from = '%s@%s.com' % (rand_email_part(), rand_email_part())
  _to = '%s@%s.com' % (rand_email_part(), rand_email_part())
  _subject = rand_email_part()
  _body = ''.join(random.choice(string.ascii_lowercase + string.digits + string.ascii_uppercase) for _ in range(random.randrange(50,4000)))
  _id = "%s-%s-%s@%s-%s.com" % (rand_email_part(), rand_email_part(), rand_email_part(), rand_email_part(), rand_email_part())
  days_ago = datetime.date.today() - datetime.timedelta(days)
  days_ago = int(days_ago.strftime("%s"))
  _date = email.utils.formatdate(days_ago)
  
  return '''From: <%s>
To: <%s>
Subject: %s
Message-ID: <%s>
Date: %s

%s''' % (_from, _to, _subject, _id, _date, _body)

def main(argv):
  options_parser = SetupOptionParser()
  (options, args) = options_parser.parse_args()
  if options.version:
    print '%s %s' % (__program_name, __version__)
    sys.exit(0)
  if options.mail_file:
    f = open(options.mail_file, 'rb')
    original_message = f.read()
    f.close()
  else:
    original_message = gen_random_email(options.days_ago)
  headers = Parser().parsestr(original_message)
  if headers.get_all('x-ms-journal-report') != None:
    print 'refusing to journal a journal message.'
    sys.exit(0)
  from_address = email.utils.getaddresses(headers.get_all('from', []))[0][1]
  if from_address[:4] == 'root@':
    print 'refusing to journal root message'
    sys.exit(0)
  subject = headers.get_all('subject', [])[0]
  #to_emails = email.utils.getaddresses(headers.get_all('to', []))
  to_field_entry = ''
  #for to_email in to_emails:
  #  to_field_entry += "To: %s\r\n" % to_email[1]
  for recipient in options.recipients:
    to_field_entry += "To: %s\r\n" % recipient
  journal_message = MIMEMultipart()
  journal_message['From'] = '<%s>' % options.journal_from_address
  journal_message['To'] = '<%s>' % options.journal_address
  journal_message['Message-ID'] = "<%s-%s-%s@journal.report.generator>" % (rand_email_part(), rand_email_part(), rand_email_part())
  journal_message['Subject'] = headers['Subject']
  journal_message['Date'] = email.utils.formatdate()
  journal_message['X-MS-Journal-Report'] = ''
  envelope_part = '''Sender: %s
Subject: %s
Message-Id: %s
%s''' % (from_address, subject, headers['Message-Id'], to_field_entry)
  journal_message.attach(MIMEText(envelope_part, 'plain'))
  journal_message.attach(MIMEMessage(headers, 'rfc822'))
  retries = 5
  for i in range(retries):
   try:
     s = smtplib.SMTP(options.smtp_server)
     s.starttls()
     if options.debug:
       print journal_message
       s.set_debuglevel(1)
     s.sendmail(options.journal_from_address, options.journal_address, journal_message.as_string())
     s.quit()
     break
   except smtplib.SMTPServerDisconnected, e:
     if i+1 == retries:
       sys.exit(1)
     wait_on_fail = 2 ** i if 2 ** i < 60 else 60
     print u'Error: %s. Sleeping %s...' % (e, wait_on_fail)
     time.sleep(wait_on_fail)     

if __name__ == '__main__':
  try:
    main(sys.argv)
  except KeyboardInterrupt:
    sys.exit(1)
