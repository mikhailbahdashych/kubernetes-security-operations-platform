# Uncomment the backend block below after creating the S3 bucket and DynamoDB table.
#
# To create the required backend resources, run:
#   aws s3api create-bucket \
#     --bucket ksop-terraform-state-ACCOUNT_ID \
#     --region eu-central-1 \
#     --create-bucket-configuration LocationConstraint=eu-central-1
#
#   aws s3api put-bucket-versioning \
#     --bucket ksop-terraform-state-ACCOUNT_ID \
#     --versioning-configuration Status=Enabled
#
#   aws s3api put-bucket-encryption \
#     --bucket ksop-terraform-state-ACCOUNT_ID \
#     --server-side-encryption-configuration \
#       '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"aws:kms"}}]}'
#
#   aws dynamodb create-table \
#     --table-name ksop-terraform-locks \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST \
#     --region eu-central-1
#
# Then replace ACCOUNT_ID with your actual AWS account ID and uncomment:

# terraform {
#   backend "s3" {
#     bucket         = "ksop-terraform-state-ACCOUNT_ID"
#     key            = "dev/terraform.tfstate"
#     region         = "eu-central-1"
#     encrypt        = true
#     dynamodb_table = "ksop-terraform-locks"
#   }
# }
