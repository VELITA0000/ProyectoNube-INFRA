# INFRA - Infrastructure (Terraform modules)

## Introduction

### Resume 

Lumière is a cloud-native photography marketplace that lets photographers sell session-based portfolios online without managing any infrastructure of their own. Photographers sign up, create portfolios, upload originals, and invite specific clients to private galleries. Behind the scenes the originals land in a private S3 bucket and trigger an asynchronous SQS + Lambda pipeline that generates watermarked previews and thumbnails. Clients only ever see the watermarked variants until they pay, at which point Stripe Checkout fires a webhook, the purchase is recorded in PostgreSQL (Neon), and the original images become downloadable for that client only.

The whole stack runs serverless on AWS and is provisioned end-to-end with Terraform: Cognito for authentication, API Gateway + Lambda for the Express API, S3 + CloudFront for the React SPA, SQS for the watermark queue, SNS + CloudWatch for transactional notifications and operational alarms, and Neon Postgres for relational state. Three independent repositories (INFRA, API, APP) ship through GitHub Actions — linting and validation on every push, plus automated aws lambda update-function-code and aws s3 sync + CloudFront invalidations on every merge to main — so the same codebase can be torn down and redeployed cleanly into the AWS Academy lab whenever the four-hour session expires.

### Infraestructure Integration

This folder provisions the entire AWS stack of the project. The root stack lives in **`environments/prod/`** and composes eight reusable modules under **`modules/`**. Each module exposes inputs/outputs.

The PostgreSQL database is **not** in Terraform: it is provisioned externally on **Neon** to save resources.

Once the infraestructure is created with the **Usefull Outputs** we have the variables to launch our Frontend and Backend, first we upload the API and then the Frontend.
- https://github.com/VELITA0000/ProyectoNube-FRONT
- https://github.com/VELITA0000/ProyectoNube-BACK

## Description

### Production environment

Composition layer with possible extension for development. It only wires modules together and exposes outputs:
- Sets the AWS provider region.
- Builds ```storage_cors_origins```, ```frontend_origin_for_api``` and the API Lambda env map which includes ```DATABASE_URL``` from ```var.database_url``` and ```SNS_TRANSACTIONS_TOPIC_ARN``` from ```module.notifications```
- Reads bucket names from ```TF_VAR_originals_bucket_name``` and ```TF_VAR_frontend_bucket_name``` set by ```INFRA/create.sh```
- Computes the IAM execution role ARN from ```var.existing_iam_role_name``` (default ```LabRole```).

### Module map

| Module | Purpose | Key AWS resources |
|---|---|---|
| **`storage`** | Bucket for image originals (out-of-band) | S3 sub-resources (CORS, encryption, versioning, PAB) |
| **`frontend_cdn`** | SPA hosting (out-of-band bucket) + CDN | CloudFront distribution, OAC, response headers policy, S3 sub-resources |
| **`messages`** | Async pipeline queue | SQS main queue + DLQ + redrive policy |
| **`auth`** | User authentication | Cognito user pool + SPA client + groups |
| **`api_http`** | Public API entry point | HTTP API Gateway + API Lambda + integration |
| **`lambda`** | Watermark / thumbnail worker | Lambda function + SQS event source mapping |
| **`notifications`** | Transactional notifications | SNS topic + optional email subscription |
| **`observability`** | Metrics, logs, alarms | CloudWatch log groups, alarms, dashboard |

(Database integrated from **Neon**: managed serverless Postgres)

### Outputs

**All outputs**  
```
api_lambda_function_name
cloudfront_distribution_id
cloudfront_domain_name
cloudfront_origin_url
cloudwatch_dashboard_name
cognito_client_id
cognito_endpoint_url
cognito_issuer_url
cognito_user_pool_id
database_url
http_api_endpoint
lambda_execution_role_arn
s3_bucket_originals
s3_bucket_originals_arn
s3_frontend_bucket
sns_transactions_topic_arn
sqs_watermark_dlq_arn
sqs_watermark_dlq_url
sqs_watermark_queue_arn
sqs_watermark_queue_url
stripe_webhook_url
watermark_lambda_function_arn
watermark_lambda_function_name
```

**Usefull Outputs**
```
HTTP_API_ENDPOINT
DATABASE_URL
COGNITO_USER_POOL_ID
COGNITO_CLIENT_ID
COGNITO_ENDPOINT_URL
COGNITO_ISSUER_URL
S3_BUCKET_ORIGINALS
SQS_WATERMARK_QUEUE_URL
CLOUDFRONT_ORIGIN_URL
SNS_TRANSACTIONS_TOPIC_ARN
VITE_API_BASE_URL
S3_FRONTEND_BUCKET
CLOUDFRONT_DISTRIBUTION_ID
```

## Launch

### Prerequisites

**1. AWS credentials**   
```bash
aws configure
aws sts get-caller-identity
```

**2. Terraform (build IaC)**    
```bash
terraform --version
```

**3. Node + npm (watermark Lambda zip + Neon CLI)**     
```bash
node --version
npm --version
```

**4. Neon database**    
```bash
npm install -g neonctl
```

### First apply (Standalone)

**1. Execution permission for the scripts**    
```bash
chmod +x INFRA/*.sh
```

**2. Setup variables**   
Copy ```terraform.tfvars.example``` to ```terraform.tfvars```

```database_url = "postgresql://neondb_owner:...@ep-xxx.aws.neon.tech/neondb?sslmode=require"```

```default_photo_unit_price_usd = 12```

```stripe_secret_key = ""```

```notification_email = "ops@example.com"```

```# api_lambda_bundle_file = "../../../API/.lambda-build/index.js"```

```# stripe_webhook_secret = "whsec_..."```

**3. Run create.sh**   
```bash
INFRA/create.sh
```

The script executes the following sequence internally:
- Verifies that ```terraform.tfvars``` exists and that AWS credentials work ```aws sts get-caller-identity```
- Computes bucket names ```${PROJECT_NAME}-prod-orig-…``` / ```…-spa-…```
- Creates the two S3 buckets out of band with ```aws s3api create-bucket```
- Pre-cleans CloudFront ```OAC``` and ```Response Headers Policy``` with the same name
- Saves the bucket names in ```INFRA/environments/prod/.bucket-names``` and exports ```TF_VAR_originals_bucket_name``` / ```TF_VAR_frontend_bucket_name```
- Runs ```npm install --omit=dev``` in ```INFRA/modules/lambda/src``` so the watermark Lambda zip ships with its dependencies
- Runs ```terraform init``` -> ```terraform plan -input=false``` -> ```terraform apply -auto-approve -input=false```
- Prints the values needed by the ```API/``` and ```APP/``` scripts

**4. Outputs**  
```bash
cd INFRA/environments/prod
terraform output
```

| Output | Typical use |
|--------|-------------|
| ```http_api_endpoint``` | API base URL |
| ```stripe_webhook_url``` | Stripe endpoint made from API base URL |
| ```api_lambda_function_name``` | Lambda name for CLI |
| ```watermark_lambda_function_name``` | Watermark worker (SQS) name |
| ```database_url``` | Neon postgresql://… echoed in clear text |
| ```cloudfront_origin_url``` | HTTPS URL of the SPA on CloudFront |
| ```s3_frontend_bucket``` | Bucket for static front build |
| ```s3_bucket_originals``` | Bucket for image originals |
| ```cloudfront_distribution_id``` | Invalidation after SPA upload |
| ```sqs_watermark_queue_url``` | Queue URL injected to API |
| ```sqs_watermark_dlq_url``` | Dead-letter queue (failed messages) |
| ```sns_transactions_topic_arn``` | SNS topic for transactional notifications |
| ```cloudwatch_dashboard_name``` | Dashboard with metrics |
| ```lambda_execution_role_arn``` | Execution role |

(Save ```http_api_endpoint``` to get ```stripe_webhook_secret```)
(Save ```api_lambda_function_name``` to export when uploading API)

### Updates

This command reuses ```.bucket-names```, refreshes the watermark Lambda dependencies, and runs ```terraform plan``` / ```terraform apply```

**1. Edit**  
- Modify ```.tf``` or ```terraform.tfvars```     
- Modify the watermark Lambda code under ```INFRA/modules/lambda/src``` 
- Change variables in ```terraform.tfvars```.

**2. Apply changes**    
```bash
bash INFRA/update.sh
```

**3. Update Frontend**   
When ```http_api_endpoint``` or CloudFront URL changes you need to rebuilt frontend with the new ```VITE_API_BASE_URL``` route.

### Tear down

**1. Run destroy.sh**    
```bash
bash INFRA/destroy.sh
```

The script executes the following sequence internally:
- Verifies AWS credentials and that Terraform was already initialized in ```environments/prod```
- Asks for the confirmation word ```destroy```
- Migrates legacy state if the buckets were managed as ```aws_s3_bucket``` resources in older runs
- Runs ```terraform destroy -auto-approve -input=false -refresh=false```
- Empties and deletes the two S3 buckets out of band ```aws s3 rb --force```
- Best-effort delete of CloudFront
- Removes ```.bucket-names``` so the next ```create.sh``` starts clean

**2. Drop the Neon database**     
The command to create the database also deletes the old one. The Neon project lives outside Terraform. To remove it run:

```bash
npx neonctl@latest projects list
npx neonctl@latest projects delete <project-id>
```