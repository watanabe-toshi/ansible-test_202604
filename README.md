# Terraform + Ansible Demo for Windows Server Hardening

## 概要

このリポジトリは、AWS 上に Terraform で以下の構成を作成し、  
Amazon Linux を **Ansible の control node**、Windows Server を **Ansible の管理対象ノード** として利用するデモ構成です。

- Amazon Linux 2023
- Windows Server 2022
- VPC / Public Subnet / Internet Gateway / Route Table
- Security Group
- WinRM over HTTPS
- Ansible による Windows セキュリティ設定の自動適用

このデモの主目的は、**Windows サーバの設定を GUI の手作業ではなく、Ansible Playbook によってコード化・再現可能にすること**です。

---

## このデモで見せたいこと

この構成では、主に次のポイントをデモできます。

- Windows サーバのセキュリティ設定をコードで管理できる
- 同じ設定を何度でも再現できる
- 手作業ではなく Playbook 実行で状態を揃えられる
- 再実行時に不要な変更が発生しないことを確認できる
- Linux から Windows へ Ansible で設定を適用できる

---

## 全体構成

- **Terraform**
  - AWS リソースの作成
  - Linux / Windows インスタンスの作成
  - user_data による初期セットアップ

- **Amazon Linux**
  - Ansible 実行サーバ
  - `ansible.windows` / `community.windows` コレクションを配置
  - Playbook / inventory / vars / roles を自動生成

- **Windows Server**
  - WinRM over HTTPS を有効化
  - Ansible から管理される対象ノード

---

## Ansible 構成の考え方

この構成では、Amazon Linux 側に Ansible 一式を配置し、Windows Server に対して WinRM で接続します。

### なぜ Linux 側で Ansible を実行するのか

Ansible の control node は基本的に Linux / Unix 系で運用する前提です。  
そのため、この構成では Amazon Linux を control node とし、Windows は管理対象ノードとしています。

### なぜ WinRM を使うのか

Windows サーバに対して Ansible を実行する場合、SSH ではなく **WinRM** を利用するのが標準的です。  
この構成では、Windows 側で WinRM over HTTPS を有効にし、Linux 側から安全に接続できるようにしています。

---

## Linux 側で自動配置される Ansible ファイル

Terraform の `user_data` によって、Linux インスタンス起動時に以下のような構成が自動作成されます。

```text
/home/ec2-user/ansible/
├─ ansible.cfg
├─ inventory.ini
├─ site.yml
├─ ping-windows.yml
├─ vars/
│  └─ vars.yml
└─ roles/
   ├─ account_policies/
   │  └─ tasks/
   │     └─ main.yml
   └─ windows_firewall/
      └─ tasks/
         └─ main.yml
