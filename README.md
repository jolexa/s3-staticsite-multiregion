# https://static-site.jolexa.us/
=======

## Motivation
On [Feburary 28th](https://aws.amazon.com/message/41926/), AWS S3
in us-east-1, was
[down](https://techcrunch.com/2017/02/28/amazon-aws-s3-outage-is-breaking-things-for-a-lot-of-websites-and-apps/)
for several
[hours](https://techcrunch.com/2017/03/02/aws-cloudsplains-what-happend-to-s3-storage-on-monday/).
Many people, myself included, host static site on S3. Static sites backed by AWS
S3 are great because they actually don't require servers to host a website
(#serverless, :D). However, this event broke many SLAs for customers and was a
general annoyance or even embarressing. It is true that other regions were not
effected too much but us-east-1 is the most popular region and the biggest.

I don't want my personal sites to go down in this event. Companies don't want
their assets to be unavailable, or down. Many people can benefit by a better
solution here, surprisingly Amazon is not helping the masses in this topic.

My goal is to provide a reference implementation of a multi-region s3 backed
static site (or CDN). Your mileage may vary here but it is a simple enough
concept for me and does not require maintenance (or extra cost) so I will be
switching my own assets to this model until something better is available.

## What?


## How?
If you want to deploy this for yourself. Modify the top 5 lines of the Makefile
and run `make` - this will deploy multiple cloudformation stacks.

1.
2.
3.
4.

## Questions / Contact
I will answer question on GitHub Issues and review Pull Requests to make this
reference even better. Feel free to reach on on Twitter as well.
