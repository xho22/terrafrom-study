# AWS + Terraform 5 天速成实战计划

## 目标与边界

**投入：**每天 3～4 小时，连续 5 天；第 0 天另留 30 分钟安装环境。

**5 天后的达标标准：**你能看懂并修改一个常见 AWS Terraform 项目，能在本地完成 `plan`、`apply`、`destroy`，能解释 state、module、IAM、VPC、S3、ECS/EKS 的常见取舍，并能在面试中讲一个完整项目。

**刻意不学：**AWS 全部服务、多账号 Landing Zone、复杂 Terragrunt、跨区域容灾、Terraform Provider 开发。这些不是入门 DevOps 岗的最快收益点。

**练习环境：**不用真实 AWS。逻辑测试使用 Terraform 原生 `terraform test` + `mock_provider`；资源联调使用 Docker 中的 LocalStack。LocalStack 不是 AWS 的完全替代品，因此 EKS/ALB/NAT 的行为以“理解配置结构”为目的，不追求本地 1:1 验证。

## 第 0 天（30 分钟）：一次性准备

安装并确认：

```bash
terraform version
docker version
```

安装 LocalStack 并启动（按其官方当前安装文档；如版本要求认证，使用其免费账户或先只完成 mock 练习）。建立练习目录：

```bash
mkdir -p labs/day{1,2,3,4,5}
```

每天开始前先定一个规矩：本地实验结束必跑 `terraform destroy`。即使是 LocalStack，这也是生产习惯。

---

## Day 1：把 Terraform 跑通（3 小时）

### 学什么（45 分钟）

- HCL：block、attribute、变量、输出、`locals`
- `terraform init / fmt / validate / plan / apply / destroy`
- provider、resource、data source 的区别
- state 是 Terraform 对“已管理资源”的记录，不是配置文件

### 做什么（90 分钟）

在 `labs/day1` 写一个最小 S3 bucket 配置（使用 LocalStack），并完成：

```bash
terraform fmt
terraform validate
terraform plan
terraform apply
terraform destroy
```

然后依次做三次小改动：改 bucket 名、增加 `tags`、增加 output。每次先看 plan，再 apply。

### 面试表达（15 分钟）

> Terraform 通过 provider 调用云 API；配置描述期望状态，state 记录已管理资源，plan 比较两者后生成变更。生产上 state 必须共享并加锁，不能每个人各存一份本地 state。

### 验收

- [ ] 不看教程能写出 provider、一个 resource、变量和 output
- [ ] 能说明为什么不能跳过 `plan`
- [ ] 能安全执行并确认 `destroy`

---

## Day 2：写出可复用配置（3～4 小时）

### 学什么（45 分钟）

- `for_each`（优先）与 `count`
- type 明确的 variables、`*.tfvars`
- module 的输入、输出和边界
- provider version 与 `.terraform.lock.hcl`

### 做什么（2 小时）

做一个 `s3_bucket` module，支持传入：bucket 名称、环境、业务名、是否开启 versioning。根模块用 `for_each` 创建 `logs`、`uploads` 两个 bucket。

目录控制在这一级，别过度拆分：

```text
labs/day2/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars
└── modules/s3_bucket/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

### 加一项真实工程动作（30 分钟）

为 module 写一个 `*.tftest.hcl`，用 `mock_provider "aws" {}` 断言 bucket 名和必需标签；执行：

```bash
terraform test
```

### 验收

- [ ] 能说出 `for_each` 比 `count` 更适合稳定资源标识的原因
- [ ] 能区分“模块复用”与“为了目录好看而拆模块”
- [ ] `fmt`、`validate`、`test` 都通过

---

## Day 3：掌握 AWS 基础骨架（4 小时）

### 学什么（60 分钟）

按流量路径理解，不背 API：

```text
Internet → ALB（公有子网）→ 应用（私有子网）→ RDS（私有子网）
                         ↘ CloudWatch
```

- VPC、CIDR、公有/私有子网、Route Table、Internet Gateway、NAT Gateway
- Security Group 是有状态的防火墙；NACL 是无状态的（知道即可）
- IAM User、Role、Policy；应用优先用 Role，不在代码或环境变量里塞长期 AK/SK

### 做什么（2 小时）

不要求在 LocalStack 完整模拟网络。手写一个 VPC 配置的**骨架**：VPC、2 个 public subnet、2 个 private subnet、Internet Gateway、一个 Security Group。重点是写出正确资源关系与变量；用：

```bash
terraform fmt && terraform validate
```

再写两份 IAM policy JSON：

1. 应用对指定 S3 bucket 的只读权限。
2. CI 对当前项目所需资源的最小权限（先写服务范围，未确定 ARN 可在注释中标出待收紧项）。

### 面试表达（15 分钟）

> 负载均衡器需要接受公网流量，所以在公有子网；应用和数据库不直接暴露公网，放私有子网。安全组只允许上游必要端口访问下游。Terraform 执行身份和运行中应用身份分开，并遵守最小权限。

### 验收

- [ ] 能在纸上画出请求从 Internet 到数据库的路径
- [ ] 能解释公有子网不等于“资源自动有公网 IP”
- [ ] 配置能通过 `terraform validate`

---

## Day 4：做一个能放简历的最小项目（4 小时）

### 项目：本地文件处理流水线

```text
上传文件 → S3 → SQS → Lambda/消费者 → DynamoDB 记录处理状态
```

使用 Terraform + LocalStack 创建 S3、SQS、DynamoDB、IAM Role；Lambda 可以先不实际运行，只把事件和权限关系写正确。若时间足够，再用 Python/Node 写一个最小消费者或 Lambda handler。

### 必须提交的工程内容

- `README.md`：架构图（ASCII 即可）、启动命令、验证步骤、销毁命令
- `variables.tf`：环境、项目名、资源命名
- `outputs.tf`：bucket 名、queue URL、table 名
- `*.tftest.hcl`：至少两个断言
- 所有资源的统一 tags：`Project`、`Environment`、`ManagedBy = Terraform`

### 验收

- [ ] 从空目录能按 README 跑到 `apply`
- [ ] 资源名不硬编码环境（例如 `file-pipeline-dev-upload`）
- [ ] 能解释 S3、SQS、DynamoDB 各自解决什么问题

---

## Day 5：把代码变成面试能力（3 小时）

### 复盘与打磨（90 分钟）

给 Day 4 项目补齐以下内容：

- README 写清楚“为什么用队列解耦”和“失败怎么处理”（DLQ 为后续项即可）
- 给变量加 description 和合理 type
- 跑一遍：

```bash
terraform fmt -check
terraform validate
terraform test
terraform plan
terraform destroy
```

### 30 分钟高频面试题

1. **为什么远端 state 要锁？** 防止多人并发 apply 写坏 state。
2. **如何处理 drift？** 先 `plan` 识别差异；确认手工修改是否合理，再选择回写配置、import 或让 Terraform 恢复期望状态。
3. **密钥放哪里？** 不进 Git、不写 tfvars；CI 用短期身份/Role，应用用 IAM Role + Secrets Manager/Parameter Store。
4. **为什么 module 不要过度拆？** 模块用于有明确边界且可复用的资源组合；只用一次的简单资源直接写更容易读和改。
5. **`terraform apply` 失败怎么办？** 先读具体 API 错误和 plan/state，不盲目重复执行；修正配置或权限后重新 plan。部分资源已创建时以 state 为准继续收敛。
6. **Kubernetes 经验如何迁移？** 用 Terraform 建网络、IAM、EKS 及其外围依赖；应用层用 Helm/Kubernetes manifest，基础设施和应用发布保持职责分离。

### 简历项目描述（可直接改名使用）

> 使用 Terraform 模块化定义文件处理基础设施（S3、SQS、DynamoDB 与 IAM），在 LocalStack 完成本地 IaC 联调；通过 `terraform test` 覆盖资源命名、标签与模块输出，统一执行 fmt/validate/plan/apply/destroy 工作流。

### 最终验收

- [ ] 5 分钟内画出项目架构并讲清数据流
- [ ] 5 分钟内解释 state、module、IAM 最小权限、drift
- [ ] 能现场给资源加变量、标签或新增第二个环境
- [ ] 项目可复现，且销毁后不留下资源

## 之后只补这三件事

1. **真实 AWS sandbox 验证一次：**仅验证 VPC + IAM + 一个计算服务，完成后 destroy；这是 LocalStack 覆盖不了的现实差异。
2. **CI：**在 GitHub Actions/GitLab CI 中跑 `fmt -check`、`validate`、`test`、PR `plan`。
3. **EKS：**把你已有 K8s 经验接上去，学习 IRSA、ECR、ALB Controller、Cluster Autoscaler/Karpenter 中最常遇到的部分。

先不要学：Terraform Cloud 高级治理、复杂 Terragrunt、多云抽象、几十个社区 Module 的组合。这些在能独立交付一个小型 AWS Terraform 项目前，投入产出很低。
