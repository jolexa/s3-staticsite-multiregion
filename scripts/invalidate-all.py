#!/usr/bin/env python

from time import time
import sys
import boto3

client = boto3.client('cloudfront')
def get_id(url):
    print("get_id args: {0}".format(url))
    # url: asdf.cloudfront.net
    # return: E2134123ASDF
    # where E2134123ASDF is the id of asdf.cloudfront.net
    paginator = client.get_paginator('list_distributions')
    response_iterator = paginator.paginate()
    for i in response_iterator:
        for j in i['DistributionList']['Items']:
            if j['Aliases']['Items'][0] == url:
                return j['Id']

response = client.create_invalidation(
    DistributionId=get_id(sys.argv[1]),
    InvalidationBatch={
        'Paths': {
            'Quantity': 1,
            'Items': [
                '/*'
                ],
            },
        'CallerReference': str(time()).replace(".", "")
        }
    )
