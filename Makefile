ACCOUNT=$(shell aws sts get-caller-identity --query Account --output text)

deploy-standby:
	aws cloudformation deploy \
		--template-file backup-region-template.yml \
		--stack-name static-s3-region-failure-standby \
		--region us-west-2 \
		--capabilities CAPABILITY_IAM || exit 0
	# HACK alert: Sigh, alarms for route53 healthchecks MUST be in us-east-1
	# This is starting to smell like a SPOF
	aws cloudformation deploy \
		--template-file backup-region-alarms.yml \
		--stack-name static-s3-region-failure-standby-alarms \
		--region us-east-1 \
		--parameter-overrides "DestinationHealthCheckId=$(shell aws cloudformation --region us-west-2 describe-stacks --stack-name static-s3-region-failure-standby --query Stacks[0].Outputs[0].OutputValue --output text)" \
		--capabilities CAPABILITY_IAM || exit 0

deploy-primary:
	aws cloudformation deploy \
		--template-file primary-region-template.yml \
		--stack-name static-s3-region-failure-primary \
		--region us-east-2 \
		--capabilities CAPABILITY_IAM || exit 0
	# HACK alert: Sigh, alarms for route53 healthchecks MUST be in us-east-1
	# This is starting to smell like a SPOF
	aws cloudformation deploy \
		--template-file primary-region-alarms.yml \
		--stack-name static-s3-region-failure-primary-alarms \
		--region us-east-1 \
		--parameter-overrides "DestinationHealthCheckId=$(shell aws cloudformation --region us-east-2 describe-stacks --stack-name static-s3-region-failure-primary --query Stacks[0].Outputs[0].OutputValue --output text)" \
		--capabilities CAPABILITY_IAM || exit 0
