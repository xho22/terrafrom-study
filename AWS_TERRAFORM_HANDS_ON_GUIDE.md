# AWS + Terraform 5 天速成：手把手实操指南

这份指南落实 [5 天学习计划](AWS_TERRAFORM_5DAY_SPRINT.md)。全程不需要 AWS 账号或真实 AWS 凭证。

> 目标：每天 3～4 小时。不要只复制粘贴；每次 `plan` 出现变化时，先用一句话解释它为什么发生，再执行 `apply`。

## 0. 你会用到的两种本地练习

| 工具 | 用途 | 会创建真实云资源吗 |
|---|---|---|
| `terraform test` + `mock_provider` | 验证 HCL、变量、模块、命名、标签和输出 | 不会 |
| LocalStack + Docker | 让 Terraform 对本机模拟 AWS API 执行 `apply` | 不会，资源只存在于本机容器 |

LocalStack 用于练工作流，不保证模拟 EKS、ALB、NAT Gateway 或复杂 IAM 的全部真实行为。那些内容先学配置结构；准备面试时再用一次可控的 AWS sandbox 验证即可。

## 1. 环境搭建（Day 0，30 分钟）

下面按 macOS 写；如果你不是 macOS，安装 Terraform 和 Docker Desktop 后，后续命令相同。

### 1.1 安装 Terraform 和 Docker

安装 Homebrew（如果已安装，跳过），然后：

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

安装并启动 [Docker Desktop](https://www.docker.com/products/docker-desktop/)。确认：

```bash
terraform version
docker version
docker compose version
```

`terraform test` 的 provider mock 需要 Terraform 1.7+；只要版本足够新即可。

### 1.2 建立练习目录

在当前项目根目录执行：

```bash
mkdir -p labs/day1 labs/day2/modules/s3_bucket labs/day3 labs/day4 labs/day5
```

推荐在 VS Code 中打开当前目录。Terraform 的文件命名不是语法要求，但使用 `main.tf`、`variables.tf`、`outputs.tf` 会让人一眼看懂项目。

### 1.3 启动 LocalStack

使用 Docker Compose 管理 LocalStack。先在项目根目录创建 `.localstack.env`：

```env
LOCALSTACK_AUTH_TOKEN=粘贴你的LocalStack token
```

限制该文件权限，并确保不提交 token：

```bash
chmod 600 .localstack.env
printf '\n.localstack.env\n' >> .gitignore
```

创建 `docker-compose.localstack.yml`：

```yaml
services:
  localstack:
    image: localstack/localstack
    ports:
      - "4566:4566"
      - "4510-4559:4510-4559"
    env_file:
      - .localstack.env
    environment:
      SERVICES: s3,sqs,dynamodb,iam
```

以后在项目根目录启动、确认状态和停止服务，只需：

```bash
docker compose -f docker-compose.localstack.yml up -d
curl http://localhost:4566/_localstack/health
docker compose -f docker-compose.localstack.yml down
```

启动后健康检查会返回 JSON，其中已启用服务的状态应为可用。`down` 只停止并移除容器；如果要清空本地模拟的所有持久数据，再执行：

```bash
docker compose -f docker-compose.localstack.yml down -v
```

> `.localstack.env` 是本地明文密钥文件：不要提交、不要发到聊天中、不要写进 `~/.zshrc`。它的作用范围只限当前练习项目。LocalStack token 不是 AWS 账号或 AWS 凭证。

### 1.4 每次实验的固定命令

进入当天目录后，按这个顺序执行：

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
terraform destroy
```

在 LocalStack 实验中，先确保 `docker compose -f docker-compose.localstack.yml up -d` 已执行；最后两条命令会对本机模拟环境生效。若终端要求确认，可输入 `yes`；熟悉后可使用 `-auto-approve`，但第一周建议手动确认。当天练习结束后运行 `docker compose -f docker-compose.localstack.yml down`。

---

## 2. Day 1：第一个 S3 bucket

### 2.1 先用原生 Mock，不碰任何 AWS API

创建 `labs/day1/main.tf`：

```hcl
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "environment" {
  type = string
}

locals {
  bucket_name = "terraform-sprint-${var.environment}-logs"
}

resource "aws_s3_bucket" "logs" {
  bucket = local.bucket_name

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

output "bucket_name" {
  value = aws_s3_bucket.logs.bucket
}
```

创建 `labs/day1/main.tftest.hcl`：

```hcl
mock_provider "aws" {}

run "uses_the_environment_in_the_bucket_name" {
  variables {
    environment = "dev"
  }

  assert {
    condition     = aws_s3_bucket.logs.bucket == "terraform-sprint-dev-logs"
    error_message = "bucket 名称必须包含环境"
  }
}

run "adds_required_tags" {
  variables {
    environment = "dev"
  }

  assert {
    condition     = aws_s3_bucket.logs.tags.ManagedBy == "Terraform"
    error_message = "所有资源都必须标注 ManagedBy=Terraform"
  }
}
```

执行：

```bash
cd labs/day1
terraform init
terraform fmt
terraform validate
terraform test
```

预期：两个 test 都显示 `pass`。这里 Terraform 下载 AWS provider 的 schema，但没有 AWS 凭证，也不会调用 AWS。

**故意练一次失败：**将测试中的期望名称改成 `terraform-sprint-prod-logs`，运行 `terraform test` 看 assertion 错误，再改回来。这是理解测试价值最快的方法。

### 2.2 再对 LocalStack 真的 apply

创建 `labs/day1/provider.tf`：

```hcl
provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3 = "http://s3.localhost.localstack.cloud:4566"
  }
}
```

因为 `plan/apply` 不会自动提供 `environment`，创建 `labs/day1/terraform.tfvars`：

```hcl
environment = "dev"
```

现在执行：

```bash
terraform plan
terraform apply
terraform output
terraform destroy
```

你应该依次看到：`plan` 计划创建 1 个资源；`apply` 显示创建成功；`output` 输出 bucket 名；`destroy` 删除该资源。

**Day 1 完成条件：**不用看文档，能解释 `resource`、`variable`、`local`、`output` 和 state 各自做什么。

---

## 3. Day 2：模块、变量和测试

### 3.1 写一个刚好够用的 S3 module

创建 `labs/day2/modules/s3_bucket/variables.tf`：

```hcl
variable "name" {
  type = string
}

variable "environment" {
  type = string
}

variable "project" {
  type = string
}

variable "versioning_enabled" {
  type    = bool
  default = true
}
```

创建 `labs/day2/modules/s3_bucket/main.tf`：

```hcl
resource "aws_s3_bucket" "this" {
  bucket = "${var.project}-${var.environment}-${var.name}"

  tags = {
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}
```

创建 `labs/day2/modules/s3_bucket/outputs.tf`：

```hcl
output "name" {
  value = aws_s3_bucket.this.bucket
}

output "arn" {
  value = aws_s3_bucket.this.arn
}
```

### 3.2 由根模块创建两个 bucket

创建 `labs/day2/main.tf`：

```hcl
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  buckets = toset(["logs", "uploads"])
}

module "buckets" {
  for_each = local.buckets
  source   = "./modules/s3_bucket"

  name               = each.value
  environment        = "dev"
  project            = "file-pipeline"
  versioning_enabled = each.value == "uploads"
}

output "bucket_names" {
  value = { for name, bucket in module.buckets : name => bucket.name }
}
```

创建 `labs/day2/main.tftest.hcl`：

```hcl
mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mock-bucket"
    }
  }
}

run "creates_named_buckets" {
  assert {
    condition     = module.buckets["logs"].name == "file-pipeline-dev-logs"
    error_message = "logs bucket 命名错误"
  }

  assert {
    condition     = module.buckets["uploads"].name == "file-pipeline-dev-uploads"
    error_message = "uploads bucket 命名错误"
  }
}
```

执行：

```bash
cd ../day2
terraform init
terraform fmt -recursive
terraform validate
terraform test
```

这里不必 apply。重点是理解：module 是一个有输入、输出的资源组合；`for_each` 会用稳定的 key（`logs`、`uploads`）定位资源。

### 3.3 只在做完后回答这三个问题

1. 把 `toset(["logs", "uploads"])` 改成 list + `count`，删除 `logs` 时地址会如何变化？
2. 为什么 bucket 模块中不需要再声明 AWS provider？
3. 为什么 `.terraform.lock.hcl` 应提交到 Git？

**Day 2 完成条件：**`terraform test` 通过，且你能新增第三个 bucket 而不复制整段 module 配置。

---

## 4. Day 3：只写 AWS 网络与 IAM 骨架

今天不执行 `apply`。LocalStack 对复杂 VPC 场景不是你的学习重点；目标是写出正确的结构，使用 `validate` 抓配置错误。

创建 `labs/day3/main.tf`：

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "project" {
  type    = string
  default = "file-pipeline"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  for_each = {
    az1 = "10.0.1.0/24"
    az2 = "10.0.2.0/24"
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  map_public_ip_on_launch = true

  tags = { Name = "${var.project}-public-${each.key}" }
}

resource "aws_subnet" "private" {
  for_each = {
    az1 = "10.0.11.0/24"
    az2 = "10.0.12.0/24"
  }

  vpc_id     = aws_vpc.main.id
  cidr_block = each.value

  tags = { Name = "${var.project}-private-${each.key}" }
}

resource "aws_security_group" "app" {
  name   = "${var.project}-app"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTP from load balancer only (CIDR is simplified for this lab)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "read_uploads" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::file-pipeline-dev-uploads/*"]
  }
}

output "s3_read_policy_json" {
  value = data.aws_iam_policy_document.read_uploads.json
}
```

执行：

```bash
cd ../day3
terraform init
terraform fmt
terraform validate
```

然后画出下面这个图，能指着图说清楚每个组件：

```text
Internet → Internet Gateway → public subnet (ALB)
                                  ↓
                           private subnet (app)
                                  ↓
                           private subnet (database)
```

**本练习的简化点：**真实项目中还需要 route table、NAT Gateway、ALB security group 和更严格的 security-group-to-security-group 规则。这里先建立数据流概念；不要为了补齐资源而吞掉 Day 4 时间。

**Day 3 完成条件：**能说清“公有子网”的定义是路由能到 Internet Gateway，不是资源天然安全或天然有公网 IP；能说清应用为何应使用 IAM Role。

---

## 5. Day 4：本地可 apply 的简历项目

今天实现：

```text
文件上传 → S3 → SQS → 消费者/Lambda（本练习只建接口） → DynamoDB 状态表
```

先创建目录：

```bash
mkdir -p labs/day4
cd labs/day4
```

### 5.1 provider 与基础配置

创建 `provider.tf`：

```hcl
terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    dynamodb = "http://localhost:4566"
    iam      = "http://localhost:4566"
    s3       = "http://s3.localhost.localstack.cloud:4566"
    sqs      = "http://localhost:4566"
  }
}
```

创建 `variables.tf`：

```hcl
variable "project" {
  type    = string
  default = "file-pipeline"
}

variable "environment" {
  type    = string
  default = "dev"
}
```

### 5.2 数据面资源

创建 `main.tf`：

```hcl
locals {
  name = "${var.project}-${var.environment}"
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket" "uploads" {
  bucket = "${local.name}-uploads"
  tags   = local.tags
}

resource "aws_sqs_queue" "uploads_dlq" {
  name = "${local.name}-uploads-dlq"
  tags = local.tags
}

resource "aws_sqs_queue" "uploads" {
  name = "${local.name}-uploads"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.uploads_dlq.arn
    maxReceiveCount     = 3
  })

  tags = local.tags
}

resource "aws_dynamodb_table" "file_status" {
  name         = "${local.name}-file-status"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "file_id"

  attribute {
    name = "file_id"
    type = "S"
  }

  tags = local.tags
}
```

### 5.3 事件权限和队列绑定

追加到 `main.tf`：

```hcl
data "aws_iam_policy_document" "allow_s3_to_send_to_queue" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.uploads.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.uploads.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.uploads.id
  policy    = data.aws_iam_policy_document.allow_s3_to_send_to_queue.json
}

resource "aws_s3_bucket_notification" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  queue {
    queue_arn = aws_sqs_queue.uploads.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sqs_queue_policy.allow_s3]
}
```

这里的 `depends_on` 是少数应该显式使用它的场景：notification 依赖的是 queue policy 已经生效，而不是单纯的字段引用。

创建 `outputs.tf`：

```hcl
output "upload_bucket" {
  value = aws_s3_bucket.uploads.bucket
}

output "upload_queue_url" {
  value = aws_sqs_queue.uploads.url
}

output "file_status_table" {
  value = aws_dynamodb_table.file_status.name
}
```

### 5.4 为项目写测试

创建 `main.tftest.hcl`：

```hcl
mock_provider "aws" {}

run "uses_consistent_resource_names" {
  assert {
    condition     = aws_s3_bucket.uploads.bucket == "file-pipeline-dev-uploads"
    error_message = "上传 bucket 命名错误"
  }

  assert {
    condition     = aws_sqs_queue.uploads.name == "file-pipeline-dev-uploads"
    error_message = "上传队列命名错误"
  }
}

run "adds_standard_tags" {
  assert {
    condition     = aws_dynamodb_table.file_status.tags.ManagedBy == "Terraform"
    error_message = "DynamoDB 缺少 ManagedBy 标签"
  }
}
```

执行并修正所有报错：

```bash
terraform init
terraform fmt
terraform validate
terraform test
terraform plan
terraform apply
terraform output
terraform destroy
```

若 LocalStack 对 S3 notification 的实现有版本差异导致 apply 失败，先注释掉 `aws_s3_bucket_notification` resource，完成其余资源的 apply；保留 notification 代码，并在 README 标注“LocalStack 兼容性限制”。不要为了本地模拟器而改坏正确的 AWS 配置。

### 5.5 写 README

创建 `labs/day4/README.md`，最少写这些内容：

```md
# File pipeline IaC

## Architecture
S3 upload bucket sends object-created events to SQS. A future consumer reads
the queue and stores processing status in DynamoDB. Failed messages move to DLQ.

## Run locally
1. Start LocalStack on port 4566.
2. Run `terraform init && terraform apply`.
3. Run `terraform output` to inspect generated names.
4. Run `terraform destroy` when finished.

## Decisions
- SQS decouples upload traffic from processing capacity.
- DLQ preserves messages that repeatedly fail processing.
- DynamoDB uses on-demand billing because traffic is unknown.
- IAM/SQS policy only permits the upload bucket to send messages.
```

**Day 4 完成条件：**你能用 3 分钟讲清：S3、SQS、DLQ、DynamoDB 分别做什么；为什么 queue policy 需要限制来源；为何不把消费者直接写进上传 API。

---

## 6. Day 5：把它变成可面试的项目

### 6.1 做最终质量检查

在 `labs/day4` 执行：

```bash
terraform fmt -check
terraform validate
terraform test
terraform plan
```

任何一条失败都先修。只要 LocalStack 正在运行，再额外完成一次：

```bash
terraform apply
terraform destroy
```

确认 `terraform state list` 在 destroy 后没有输出，或直接删除本地 state 文件后重新 `init`（仅限这份纯本地练习）。

### 6.2 模拟一次需求变更

完成下面三项，每项都执行 `plan` 后解释变化：

1. 把 `environment` 从 `dev` 改为 `staging`。
2. 新增一个 `archive` S3 bucket。
3. 将 SQS `maxReceiveCount` 从 3 改为 5。

然后全部还原。面试中，修改已有 IaC 的能力比从零背资源定义更常用。

### 6.3 用自己的话回答高频题

不要背原文，录音或对着空白文档回答：

1. Terraform state 是什么？为什么多人协作要远端存储和锁？
2. 什么是 drift？发现手工修改的资源时怎么处理？
3. 为什么 secrets 不能放 `terraform.tfvars` 或 Git？
4. `for_each` 与 `count` 何时选择？
5. Terraform、Kubernetes manifest、Helm 各自应管理什么？

你已有 K8s 背景时，最后一题可以这样回答：Terraform 管云网络、IAM、EKS 和外围托管服务；Helm/manifest 管集群内应用。两者可以衔接，但不应让同一个状态文件承担全部应用发布生命周期。

---

## 7. 排错速查

| 症状 | 先做什么 |
|---|---|
| `terraform init` 下载 provider 失败 | 检查网络、代理和 Terraform Registry 是否可访问；不要先改 HCL。 |
| `terraform test` 显示 provider credentials 错误 | 确保测试文件有根级 `mock_provider "aws" {}`；不要创建真实 AWS credential。 |
| `terraform validate` 报 argument 不支持 | 先看 AWS Provider 对应资源的当前文档，检查 provider 版本。 |
| `apply` 连不上 `localhost:4566` | 运行 `docker compose -f docker-compose.localstack.yml up -d`，再检查：`curl http://localhost:4566/_localstack/health`。 |
| `apply` 后第二次 plan 仍有变化 | 先读 diff；可能是 LocalStack 模拟差异，也可能是配置缺失。不要先用 `ignore_changes` 掩盖问题。 |
| 不小心创建了本地 state | 正常；练习项目的 `terraform.tfstate` 不要提交 Git。每次实验后优先 `terraform destroy`。 |

## 8. 此阶段不做的事

- 不考证、不刷题库；先把 Day 4 项目讲明白。
- 不上 Terragrunt、Terraform Cloud、高级 policy-as-code。
- 不尝试在 LocalStack 跑完整 EKS/ALB Controller。
- 不把测试变成几十个断言；每个 module 只验证最重要的命名、标签、分支和输出。

完成这份指南后，再回到 5 天计划中的“之后只补三件事”：CI、一次真实 AWS sandbox 验证、以及 EKS/IRSA/Ingress 的衔接。

## 参考资料

- [Terraform provider mocking 官方文档](https://docs.hashicorp.com/terraform/language/tests/mocking)
- [Terraform tests 官方教程](https://docs.hashicorp.com/terraform/tutorials/configuration-language/test)
- [LocalStack + Terraform 官方文档](https://docs.localstack.cloud/aws/connecting/infrastructure-as-code/terraform/)
- [AWS Provider 官方资源文档](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
