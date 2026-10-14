# terraform-aws-k3s-airgap

AWS에 **폐쇄망(air-gap) k3s 클러스터**를 구성하는 Terraform 모듈입니다. 단일 AZ VPC 안에
퍼블릭 bastion/아티팩트 서버 인스턴스를 두고, 프라이빗 서브넷의 EC2 인스턴스들을
[k3s](https://k3s.io) 공식 에어갭 설치 방식으로 하나의 클러스터로 묶습니다.

프라이빗 노드에는 **인터넷으로 나가는 경로가 없습니다.** 노드는 k3s 설치 파일을 제공하는
bastion 인스턴스, 그리고 노드끼리만 통신할 수 있습니다.

```
                 인터넷
                    │
              ┌─────┴─────┐
              │    IGW    │
              └─────┬─────┘
  퍼블릭 서브넷      │
  ┌─────────────────┴──────────────────┐
  │ NAT / bastion 인스턴스 (EIP)        │
  │  - SSH 점프 호스트                  │
  │  - 지정한 k3s 릴리스를 GitHub에서   │
  │    부팅 시 한 번 다운로드           │
  │  - 아티팩트 서버 :8080              │
  └─────────────────┬──────────────────┘
  프라이빗 서브넷    │ SSH / 아티팩트만
  ┌─────────────────┴──────────────────┐
  │ node-1      node-2      node-N     │
  │ (k3s server)(k3s agent) (k3s agent)│
  └────────────────────────────────────┘
   기본 라우트 없음: bastion 및 노드 간 통신만 가능
```

## 주요 기능

- VPC, 퍼블릭/프라이빗 서브넷, 인터넷 게이트웨이, Elastic IP를 가진 bastion(Amazon Linux 2023)
- `private_instance_count`개의 프라이빗 EC2 인스턴스(기본 Ubuntu 24.04)가 k3s 클러스터를 구성
- 에어갭 설치: bastion이 지정한 버전의 k3s 바이너리, 이미지 tarball, 설치 스크립트를 내려받아
  SHA-256 체크섬을 검증하고 프라이빗 서브넷에만 제공합니다. 노드는 체크섬을 다시 검증한 뒤
  `INSTALL_K3S_SKIP_DOWNLOAD=true`로 설치합니다.
- `k3s_server_count`로 단일 서버(SQLite) 또는 홀수 개의 HA 서버(embedded etcd) 구성
- 모듈이 관리하는 SSH 키 페어(또는 기존 키 사용), 필요 시 bastion에 키를 설치해 단계별 SSH 가능
- 노드 기본 보안·운영 설정: 디스크 증가 제한, 호스트 방화벽, SSH 하드닝 ([노드 기본 설정](#노드-기본-설정) 참고)

## 사용법

```hcl
module "k3s_airgap" {
  source  = "mumberrymountain/k3s-airgap/aws"
  version = "~> 0.1"

  name_prefix            = "airgap"
  private_instance_count = 3

  k3s_version      = "v1.36.5+k3s1"
  k3s_server_count = 1
}
```

`apply` 후 부트스트랩이 끝나려면 몇 분 걸립니다.

```bash
terraform output -raw private_key_pem > airgap-key.pem && chmod 400 airgap-key.pem   # 파일 이름 = key_pair_name + ".pem"
eval "$(terraform output -raw k3s_kubeconfig_command)"
terraform output -raw k3s_api_tunnel_command   # 별도 셸에서 실행
KUBECONFIG=./kubeconfig.yaml kubectl get nodes
```

프라이빗 노드에는 `ssh_example`, `scp_example` 출력값으로 bastion을 거쳐 접속합니다.
`ssh -i 키 -J 호스트` 형식은 `-i` 키를 점프 호스트에 전달하지 않기 때문에, `-J` 대신
`ProxyCommand`를 사용합니다.

부트스트랩 로그: bastion은 `/var/log/cloud-init-output.log`, 각 노드는
`/var/log/k3s-airgap-bootstrap.log`입니다. kubeconfig 파일에는 클러스터 관리자 인증 정보가 들어 있으니 커밋하지 마세요.

전체 구성 예시는 [`examples/basic`](./examples/basic)을 참고하세요.

## 노드 기본 설정

모든 프라이빗 노드에는 부팅 시 아래 설정이 항상 적용됩니다. (입력 변수 없음)

- **디스크 증가 제한**
  - journald: 전체 500M / 파일당 50M / 보관 2주, 여유 공간 2G 유지
  - `/var/log/syslog` 등 rsyslog 파일도 100M를 넘으면 로테이션
  - `containerd.log`와 부트스트랩 로그에 logrotate 적용 (매일, 7개 보관, 최대 50M)
  - 크기 제한이 일 단위 실행 사이에도 적용되도록 logrotate를 매시간 실행
  - kubelet 컨테이너 로그 로테이션: 컨테이너당 10Mi × 3개 파일
  - 설치가 끝나면 내려받은 설치 파일 삭제
- **호스트 방화벽(ufw)**: 기본값은 들어오는 트래픽 차단 / 포워딩 차단 / 나가는 트래픽 허용.
  그 위에 SSH(22/tcp), 프라이빗 서브넷(클러스터 노드) 전체, bastion에서 오는 k3s API(6443/tcp),
  k3s 파드·서비스 대역(`10.42.0.0/16`, `10.43.0.0/16`)을 허용합니다.
- **SSH 하드닝** (`/etc/ssh/sshd_config.d/01-airgap-hardening.conf`): 공개키 인증만 허용, root 로그인 금지,
  `AllowUsers`를 `private_instance_ssh_user`로 제한, `MaxAuthTries 3`, `LoginGraceTime 30`,
  응답 없는 클라이언트는 약 10분 뒤 연결 해제, 에이전트/TCP/X11 포워딩과 터널 금지.
  이 파일은 `sshd -t`로 검증하며, 오류가 있으면 삭제합니다.
- **유휴 셸**은 15분 뒤 자동 로그아웃됩니다 (`TMOUT=900`).

## 폐쇄망 관련 참고

- 프라이빗 라우트 테이블에는 기본 라우트가 없고, 프라이빗 보안그룹은 bastion과 다른 클러스터 노드와의
  통신만 허용합니다. DNS, 인스턴스 메타데이터, Amazon Time Sync Service는 링크로컬 AWS 서비스라서
  계속 동작합니다.
- 인터넷에서 내려받는 것은 bastion이 부팅 시 GitHub에서 한 번 받는 파일뿐입니다. 노드는 bastion의
  `READY` 표시가 생길 때까지 기다린 뒤 설치합니다. 따라서 폐쇄망은 노드 기준이며, bastion은 해당되지 않습니다.
- bastion은 프라이빗 서브넷의 트래픽을 포워딩하거나 마스커레이드하지 않습니다.
- 워크로드 이미지는 공개 레지스트리에서 받을 수 없습니다. `k3s ctr images import`로 직접 넣으세요.
- k3s 토큰은 Terraform이 생성하며, 인스턴스 user data와 Terraform state에 포함됩니다. state를 민감 정보로 다루세요.
- bastion과 노드는 고정 프라이빗 IP(각 서브넷의 호스트 오프셋 10부터)를 사용하므로, 부팅 시점에 아티팩트 서버와
  첫 번째 서버의 주소를 알 수 있습니다. 노드 user data가 바뀌면 인스턴스가 교체됩니다.
- `amd64` 인스턴스 타입만 지원합니다.

## 요구 사항

| 이름 | 버전 |
|------|------|
| terraform | >= 1.5.0 |
| aws | >= 5.0 |
| random | >= 3.0 |
| tls | >= 4.0 |

## 입력 변수

| 이름 | 설명 | 기본값 |
|------|------|--------|
| `name_prefix` | 리소스 이름 접두사 | `"airgap"` |
| `vpc_cidr` / `public_subnet_cidr` / `private_subnet_cidr` | 네트워크 CIDR | `10.0.0.0/16` / `10.0.1.0/24` / `10.0.2.0/24` |
| `availability_zone` | 모든 서브넷이 사용할 AZ | 사용 가능한 첫 번째 AZ |
| `key_name` / `key_pair_name` | 기존 키 페어 이름 / 모듈이 생성할 키 페어 이름 | `null` |
| `deploy_ssh_private_key_to_nat` / `ssh_private_key_pem` | bastion에 개인키 설치 여부 / 사용할 PEM | 자동 |
| `ssh_allowed_cidr_blocks` | bastion SSH를 허용할 CIDR | `["0.0.0.0/0"]` |
| `private_instance_count` | k3s 노드 수 (서버 + 에이전트) | `3` |
| `private_instance_ami` / `_type` / `_ssh_user` | 프라이빗 인스턴스 | Ubuntu 24.04 / `t3.medium` / `ubuntu` |
| `nat_instance_ami` / `_type` / `_ssh_user` | bastion 인스턴스 | AL2023 / `t3.micro` / `ec2-user` |
| `nat_root_volume_size` / `private_root_volume_size` | 루트 볼륨 크기 (GiB) | `10` / `20` |
| `root_volume_type` / `root_volume_encrypted` | 루트 볼륨 설정 | `gp3` / `false` |
| `k3s_version` | k3s 릴리스 | `v1.36.5+k3s1` |
| `k3s_server_count` | 서버 노드 수 (홀수, `private_instance_count` 이하) | `1` |
| `tags` | 모든 리소스에 붙일 태그 | `{}` |

## 출력값

네트워크: `vpc_id`, `public_subnet_id`, `private_subnet_id`, `availability_zone`,
`nat_instance_id`, `nat_public_ip`, `nat_private_ip`, `private_instance_ids`, `private_instance_private_ips`

접속: `key_pair_name`, `private_key_pem` (sensitive), `private_key_save_command`, `ssh_proxy_command`,
`ssh_example`, `scp_example`, `ssh_via_nat_example`, `scp_via_nat_example`

k3s: `k3s_version`, `k3s_server_private_ips`, `k3s_agent_private_ips`, `k3s_api_endpoint`,
`k3s_token` (sensitive), `k3s_artifact_url`, `k3s_kubeconfig_command`, `k3s_api_tunnel_command`

## 라이선스

[LICENSE](./LICENSE)를 참고하세요.
