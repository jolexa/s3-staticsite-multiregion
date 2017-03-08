ACCOUNT=$(shell aws sts get-caller-identity --query Account --output text)

deploy-standby:
	aws cloudformation deploy \
		--template-file backup-region-template.yml \
		--stack-name static-s3-region-failure-standby \
		--region us-west-2 \
		--capabilities CAPABILITY_IAM || exit 0
