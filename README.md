# static-s3-region-failure
Reference Implementation of a S3-backed multi-region static website

Typically a static site backed by S3 will have a bucket with the name of "static-site.example.com".

Since buckets are globally namespaced, you cannot have multiple buckets in different regions with the same name.

This means, that in event of a S3 region failure, you much do heroics to provision a new bucket in a new region with the same name. This might not even be possible, depending on the outage.

What choices do you have now? CloudFront in front of a bucket is the most common pattern. How about CloudFront in front of multiple buckets that are in a replication set. Now the problem with this is that you cannot have multiple CloudFront distributions serving the same CNAME.

This reference implementation takes that one step further and automates the CloudFront updates when a backing S3 bucket is not available.

## Archetechure Diagram
![Architecture Diagram](diagram.png)

## Things to try:
Changing the origin vs changing the cname
