# Alchemyst DevOps Assignment
## Distributed Inference Platform on Azure

A production-oriented deployment of the `iii` distributed worker mesh, running a Gemma 3 270m language model behind a private subnet with a public JSON HTTP API gateway.

---

## Architecture

```
                         INTERNET
                             │
                    HTTP :80 │
                             ▼
                 ┌─────────────────────┐
                 │    Gateway VM        │
                 │  Public IP           │
                 │  NGINX reverse proxy │
                 │  iii engine (broker) │
                 │  francecentral       │
                 └──────────┬──────────┘
                            │
              Private VNet (10.0.0.0/16)
              Private Subnet (10.0.2.0/24)
                            │
              ┌─────────────┴──────────────┐
              │                            │
              ▼                            ▼
  ┌────────────────────┐      ┌────────────────────┐
  │   Inference VM     │      │    Caller VM        │
  │   Standard_B2s     │      │    Standard_B1s     │
  │   Python worker    │      │    TypeScript worker│
  │   Gemma 3 270m     │      │    HTTP trigger     │
  │   No public IP     │      │    No public IP     │
  └────────────────────┘      └────────────────────┘

RPC flow:
  Client → NGINX (Gateway) → iii-http (Gateway)
         → caller-worker (Caller VM) via iii engine
         → inference-worker (Inference VM) via iii engine
         → Gemma model → response traverses back
```

---

## Stack

| Layer | Tool |
|---|---|
| Cloud | Microsoft Azure (francecentral) |
| IaC | Terraform |
| Configuration | Ansible |
| CI/CD | GitHub Actions |
| Reverse proxy | NGINX |
| Worker runtime | iii (v0.11.0) |
| Inference | Python + transformers (Gemma 3 270m GGUF Q8) |
| API bridge | TypeScript (iii-sdk 0.11.0) |
| OS | Ubuntu 22.04 LTS |

---

## Repository Structure

```
alchemyst-devops-assignment/
│
├── .github/
│   └── workflows/
│       ├── deploy.yml          # Full CI/CD pipeline
│       └── destroy.yml         # Manual teardown
│
├── terraform/
│   ├── provider.tf             # Azure provider + remote state backend
│   ├── network.tf              # VNet, subnets, NAT gateway, public IPs
│   ├── security.tf             # NSGs — gateway (public) + worker (private)
│   ├── compute.tf              # 3 VMs using for_each
│   ├── variables.tf            # All input variables
│   └── outputs.tf              # IPs exported to deploy jobs
│
├── ansible/
│   ├── deploy-gateway.yml      # Installs iii engine + NGINX on gateway VM
│   ├── deploy-inference-worker.yml
│   ├── deploy-caller-worker.yml
│   └── inventory.ini           # Generated at pipeline runtime from TF outputs
│
├── workers/
│   ├── inference-worker/
│   │   ├── inference_worker.py
│   │   ├── requirements.txt
│   │   └── iii_worker.yaml
│   └── caller-worker/
│       ├── src/worker.ts
│       ├── package.json
│       ├── tsconfig.json
│       └── iii_worker.yaml
│
├── gateway/
│   └── nginx.conf              # Reverse proxy config
│
├── config/
│   └── config.yaml             # iii engine config
│
├── systemd/
│   ├── iii-engine.service
│   ├── inference-worker.service
│   └── caller-worker.service
│
└── README.md
```

---

## VM Layout

| VM | Role | Size | Subnet | Public IP |
|---|---|---|---|---|
| `gateway-vm` | NGINX + iii engine | Standard_B1s | public (10.0.1.0/24) | ✅ Yes |
| `inference-vm` | Python inference worker | Standard_B2s | private (10.0.2.0/24) | ❌ No |
| `caller-vm` | TypeScript HTTP worker | Standard_B1s | private (10.0.2.0/24) | ❌ No |

**Total vCPUs: 4** — within Azure student account `standardBSFamily` quota for `francecentral`.

---

## Security Model

| Rule | NSG | Effect |
|---|---|---|
| HTTP port 80 | gateway-nsg | Public internet → gateway |
| SSH port 22 | gateway-nsg | Pipeline/admin → gateway |
| iii engine port 49134 | worker-nsg | VNet-internal only |
| iii HTTP port 3111 | worker-nsg | VNet-internal only |
| SSH port 22 | worker-nsg | Gateway subnet only (10.0.1.0/24) |
| All inbound internet | worker-nsg | **DENY** |

Workers have zero public internet exposure. All RPC communication is internal to `10.0.0.0/16`.

---

## RPC Flow (Step by Step)

```
1. Client sends POST /v1/chat/completions to gateway public IP
2. NGINX receives on port 80, proxies to iii-http on 127.0.0.1:3111
3. iii-http routes to http::run_inference_over_http (caller-worker)
4. caller-worker triggers inference::get_response via iii engine
5. iii engine routes to inference::run_inference (inference-worker)
6. inference-worker loads messages, runs Gemma 3 270m, returns text
7. Response traverses: inference-worker → iii engine → caller-worker → HTTP response
```

**Key principle:** Workers never talk directly. All communication routes through the iii engine WebSocket broker on port 49134.

---

## API Reference

### Endpoint

```
POST http://<GATEWAY_PUBLIC_IP>/v1/chat/completions
Content-Type: application/json
```

### Request

```json
{
  "messages": [
    {
      "role": "user",
      "content": "Explain what Azure DevOps is in two sentences."
    }
  ]
}
```

### curl command

```bash
curl -X POST http://<GATEWAY_PUBLIC_IP>/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {
        "role": "user",
        "content": "Explain what Azure DevOps is in two sentences."
      }
    ]
  }'
```

### Sample response

```json
{
  "result": {
    "response": "Azure DevOps is Microsoft's end-to-end platform for software development, providing tools for planning, source control, CI/CD pipelines, and artifact management. It enables teams to deliver software continuously and reliably across any cloud or on-premises environment."
  }
}
```

### Health check

```bash
curl http://<GATEWAY_PUBLIC_IP>/health
```

```json
{"status": "ok", "service": "alchemyst-inference-gateway"}
```

---

## Prerequisites

- Azure subscription (student account works — francecentral region)
- GitHub account with Actions enabled
- Azure Cloud Shell or local Azure CLI
- Terraform 1.7.x
- Ansible

---

## Redeployment from Scratch

### Step 1 — Fork and clone the repository

```bash
git clone https://github.com/<your-username>/alchemyst-devops-assignment
cd alchemyst-devops-assignment
```

### Step 2 — Create Terraform state storage (once only)

Run in Azure Cloud Shell:

```bash
az group create --name rg-tfstate --location francecentral

az storage account create \
  --name tfstatealchemyst \
  --resource-group rg-tfstate \
  --location francecentral \
  --sku Standard_LRS

az storage container create \
  --name tfstate \
  --account-name tfstatealchemyst

# Copy this value — it becomes ARM_ACCESS_KEY
az storage account keys list \
  --account-name tfstatealchemyst \
  --resource-group rg-tfstate \
  --query "[0].value" -o tsv
```

### Step 3 — Generate SSH key pair

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/alchemyst_deploy -N ""

# SSH_PUBLIC_KEY secret
cat ~/.ssh/alchemyst_deploy.pub

# SSH_PRIVATE_KEY secret
cat ~/.ssh/alchemyst_deploy
```

### Step 4 — Add GitHub Secrets

Go to your repo → **Settings → Secrets and variables → Actions → New repository secret**

| Secret | Value |
|---|---|
| `AZURE_USERNAME` | Your Azure account email |
| `AZURE_PASSWORD` | Your Azure account password |
| `ARM_ACCESS_KEY` | Storage account key from Step 2 |
| `SSH_PUBLIC_KEY` | Output of `cat ~/.ssh/alchemyst_deploy.pub` |
| `SSH_PRIVATE_KEY` | Output of `cat ~/.ssh/alchemyst_deploy` |
| `ADMIN_IP` | Your public IP (`curl -s https://api.ipify.org`) |

### Step 5 — Push to main

```bash
git push origin main
```

The GitHub Actions pipeline will:
1. Lint Python and TypeScript worker code
2. Run `terraform apply` — provisions 3 VMs, VNet, subnets, NSGs, NAT gateway
3. Run Ansible playbooks — installs iii engine, workers, NGINX
4. Poll `/health` until the gateway responds
5. Run an inference smoke test

### Step 6 — Teardown

Go to **Actions → Destroy Infrastructure → Run workflow** to tear everything down.

Or manually:

```bash
cd terraform/
terraform destroy -auto-approve -lock=false
```

---

## CI/CD Pipeline

```
Push to main
    │
    ▼
lint-test        Flake8 (Python) + tsc --noEmit (TypeScript)
    │
    ▼
provision        terraform apply → 3 VMs in francecentral
    │
    ▼
deploy           Ansible → iii engine, workers, NGINX
    │
    ▼
health-check     Poll /health — 20 retries × 30s
    │
    ▼
smoke-test       POST /v1/chat/completions with test message
    │
    ▼ (on any failure)
destroy-on-failure   terraform destroy — no orphaned billing
```

---

## Production Hardening

### Security

**SSH access** should be removed from the gateway NSG entirely and replaced with Azure Bastion — a managed jump host that provides browser-based SSH without exposing port 22 publicly. Currently port 22 is open to all IPs to allow the GitHub Actions runner to connect via Ansible.

**Secrets management** should use Azure Key Vault with managed identity injection rather than environment variables set in systemd unit files. The iii engine URL and any API keys would be fetched at worker startup rather than baked into service files.

**TLS termination** should be added at the NGINX layer using a certificate from Let's Encrypt via Certbot, with HTTP permanently redirected to HTTPS. Currently the API runs on plain HTTP port 80.

**Network Security Groups** should be tightened further — the gateway NSG SSH rule should be restricted to a known CI/CD IP range or removed post-deployment, and the worker NSG should restrict outbound traffic in addition to inbound.

**ISO 27001 alignment** — the current design already maps to several Annex A controls: A.9 (access control via NSG rules and SSH key authentication), A.12 (audit trail via GitHub Actions logs and systemd journal), A.10 (no data in transit without network-layer controls). A production deployment would add formal evidence collection for these controls.

### Reliability

**VM Scale Sets** should replace individual VMs for the caller-worker tier, enabling horizontal scaling under load with an Azure Load Balancer distributing requests.

**Health probes** at the load balancer layer would automatically remove unhealthy worker instances from rotation without manual intervention.

**Availability Zones** — all three VMs currently deploy to a single zone in francecentral. A production deployment would distribute across zones 1, 2, and 3 to survive a zone failure.

**Deployment slots** would enable zero-downtime worker updates — a new worker version connects to the engine and registers its functions before the old version is removed.

### Observability

**Azure Monitor** with alerts on CPU utilisation, memory pressure, and failed inference requests would provide operational visibility. The iii-observability worker is already configured in `config.yaml` — connecting it to Azure Monitor is a matter of changing the exporter from `memory` to `otlp`.

**Centralised logging** via Azure Log Analytics would aggregate systemd journal output from all three VMs into a single queryable workspace.

---

## Scaling to a 100x Larger Model

The current deployment runs Gemma 3 270m (Q8 quantised, ~270MB) on a CPU-only `Standard_B2s` VM. A model 100x larger — roughly 27 billion parameters — would require a fundamentally different infrastructure tier.

**GPU compute** would replace the `Standard_B2s` with an `Standard_NC` series VM (NVIDIA T4 or A100) or an AKS node pool with GPU scheduling. The inference worker code itself requires minimal changes — swapping the GGUF model path and removing the CPU-only constraint from the transformers pipeline.

**Distributed inference** using tensor parallelism across multiple GPUs would be necessary for models above ~70B parameters. Frameworks like vLLM or Ray Serve support this natively and expose the same HTTP interface, meaning the caller-worker and NGINX layers would not change.

**Async request queuing** via Azure Service Bus or Redis would decouple the HTTP response from the inference computation — returning a job ID immediately and delivering results via webhook or polling. This prevents HTTP timeouts on long inference runs and allows the system to absorb traffic spikes without dropping requests.

**Kubernetes (AKS)** would replace VM-based deployment entirely, giving the inference tier autoscaling via Horizontal Pod Autoscaler triggered on GPU utilisation metrics, rolling updates with zero downtime, and automatic rescheduling on node failure.

The iii worker architecture is well-suited to this migration — workers connect to the engine over WebSocket regardless of whether they run on bare VMs, containers, or Kubernetes pods.

---

## Notes on Azure Student Account Constraints

This deployment was built within Azure for Students constraints:

- **Region**: `francecentral` only (student policy restriction)
- **vCPU quota**: 4 cores maximum for `standardBSFamily` — the iii engine is co-located on the gateway VM to stay within quota
- **Service principal creation**: blocked by university Azure AD tenant — pipeline uses Azure CLI username/password authentication with storage access key for Terraform backend
- **Key Vault**: not used due to student account permission restrictions — secrets injected via GitHub Secrets and systemd environment variables

In a production Azure subscription all of these constraints would be removed.
