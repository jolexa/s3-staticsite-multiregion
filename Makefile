STACKNAME_BASE="static-s3-region-failure"
PRIMARY_REGION="ca-central-1"
PRIMARY_STACKNAME="$(STACKNAME_BASE)-primary"
STANDBY_REGION="us-west-2"
STANDBY_STACKNAME="$(STACKNAME_BASE)-standby"
PRIMARY_URL="static-site.jolexa.us"
STANDBY_URL="static-site-standby.jolexa.us"

deploy-all: deploy-standby deploy-primary

deploy-standby-infra: deploy-acm
	aws cloudformation deploy \
		--template-file standby-region-infra.yml \
		--stack-name $(STANDBY_STACKNAME)-infra \
		--region $(STANDBY_REGION) \
		--parameter-overrides "ACMCertArn=$(shell scripts/find-cfn-output-value.py --region us-east-1 --stack-name $(STACKNAME_BASE)-acm-certs --output-key ACMCertArn)" "SiteURL=$(STANDBY_URL)" \
		--capabilities CAPABILITY_IAM || exit 0

deploy-standby: deploy-standby-infra
	# HACK alert: Sigh, alarms for route53 healthchecks MUST be in us-east-1
	# This is starting to smell like a SPOF
	aws cloudformation deploy \
		--template-file standby-region-alarms.yml \
		--stack-name $(STANDBY_STACKNAME)-alarms \
		--region us-east-1 \
		--parameter-overrides "DestinationHealthCheckId=$(shell scripts/find-cfn-output-value.py --region $(STANDBY_REGION) --output-key HealthCheckId --stack-name $(STANDBY_STACKNAME)-infra)" \
		--capabilities CAPABILITY_IAM || exit 0

deploy-acm:
	# HACK: ACM Must be in us-east-1 for CloudFront distros
	aws cloudformation deploy \
		--template-file acm-certs.yml \
		--stack-name $(STACKNAME_BASE)-acm-certs \
		--region us-east-1 \
		--parameter-overrides "ACMUrl=$(PRIMARY_URL)" \
		--capabilities CAPABILITY_IAM || exit 0

deploy-primary-infra: deploy-acm
	aws cloudformation deploy \
		--template-file primary-region-infra.yml \
		--stack-name $(PRIMARY_STACKNAME)-infra \
		--region $(PRIMARY_REGION) \
		--parameter-overrides "StandbyReplBucketArn=$(shell scripts/find-cfn-output-value.py --region $(STANDBY_REGION) --output-key StandbyReplBucketArn --stack-name $(STANDBY_STACKNAME)-infra)" "ACMCertArn=$(shell scripts/find-cfn-output-value.py --region us-east-1 --stack-name $(STACKNAME_BASE)-acm-certs --output-key ACMCertArn)" "SiteURL=$(PRIMARY_URL)" \
		--capabilities CAPABILITY_IAM || exit 0

deploy-primary: deploy-primary-infra
	# HACK alert: Sigh, alarms for route53 healthchecks MUST be in us-east-1
	# This is starting to smell like a SPOF
	aws cloudformation deploy \
		--template-file primary-region-alarms.yml \
		--stack-name $(PRIMARY_STACKNAME)-alarms \
		--region us-east-1 \
		--parameter-overrides "DestinationHealthCheckId=$(shell scripts/find-cfn-output-value.py --region $(PRIMARY_REGION) --output-key HealthCheckId --stack-name $(PRIMARY_STACKNAME)-infra)" \
		--capabilities CAPABILITY_IAM || exit 0
