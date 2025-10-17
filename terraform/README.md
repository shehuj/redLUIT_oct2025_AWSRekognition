.
├── modules
│   ├── rekognition-lambda
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── lambda_handler.py        # local file to be zipped / deployed
│   └── s3-notify
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── (none or supporting files)
├── envs
│   ├── beta
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   └── prod
│       ├── main.tf
│       ├── variables.tf
│       └── terraform.tfvars
├── versions.tf
├── providers.tf
└── README.md


