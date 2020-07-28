#!/usr/bin/python

import sys
import os.path
import json
import signal
from pprint import pprint

def usage():
    print "usage: {} <json_result>".format(sys.argv[0]) 
    sys.exit(1)

def lassert(m):
    if m != None:
        print "ASSERT: {}".format(m)
    sys.exit(1)

def sigint_handler(signum, frame):
    None

# validate commandline parameters
if len(sys.argv) != 2:
    usage()

# assign commandine parameters
json_file = sys.argv[1]

# validate json_file
if not os.path.isfile(json_file):
    lassert("failed to open jsonFile: {}".format(json_file))

# read json_file
try:
    json_data=open(json_file)
    data = json.load(json_data)
    json_data.close()
except:
    sys.exit(1)
else:
    try:
        data['attachments']
    except:
        None
    else:
        for d in data['attachments']:
            try:
                d['device']
            except:
                continue
            else:
                print "{}".format(d['device'])

# exit cleanly
sys.exit(0)

