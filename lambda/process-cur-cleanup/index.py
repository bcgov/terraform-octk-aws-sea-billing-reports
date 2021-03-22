import os
import io
import sys


def handler(event, context):
        
    local_file = event['local_file']
    
    print("Cleaning up file '{}'".format(local_file))
    
    if os.path.exists(local_file):
        os.remove(local_file)
    else:
        print("The file does not exist")    
        
