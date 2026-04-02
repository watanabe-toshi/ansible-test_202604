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
```

## 各ファイルの役割

### `ansible.cfg`

Ansible の基本設定ファイルです。

このデモでは主に次を設定しています。

- 使用する inventory の指定
- host key checking の無効化
- Python interpreter の設定

実行しやすさを優先した最小構成です。

---

### `inventory.ini`

Ansible の接続先定義です。  
この構成では Windows ノードを 1 台定義しています。

```ini
[windows]
winhost ansible_host=10.0.2.10

[windows:vars]
ansible_connection=winrm
ansible_port=5986
ansible_user=Administrator
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
```

この inventory で定義している内容は次の通りです。

- `ansible_host`  
  接続先 Windows の private IP

- `ansible_connection=winrm`  
  Windows 接続に WinRM を使う

- `ansible_port=5986`  
  HTTPS の WinRM ポート

- `ansible_user=Administrator`  
  接続ユーザ

- `ansible_winrm_transport=ntlm`  
  認証方式

- `ansible_winrm_server_cert_validation=ignore`  
  自己署名証明書を使うため、証明書検証を無効化

---

### `site.yml`

メインの Playbook です。  
このファイルでは、Windows ノードに対して複数の role を順に適用します。

```yaml
---
- name: Demo CIS-like baseline for Windows Server 2022
  hosts: windows
  gather_facts: false
  vars_files:
    - ./vars/vars.yml

  roles:
    - account_policies
    - windows_firewall
```

このファイル自体には詳細な設定を書かず、**何を適用するかだけを記述する薄い構成**にしています。  
実際の設定内容は `roles/` 以下に分離しています。

---

### `vars/vars.yml`

Playbook 内で利用する変数定義ファイルです。  
環境ごとに変わる値や、ポリシー値をここにまとめています。

```yaml
password_history_size: 24
maximum_password_age: 60
minimum_password_age: 1
minimum_password_length: 14

lockout_bad_count: 10
reset_lockout_count: 15
lockout_duration: 15

linux_control_node_ip: "10.0.1.10"
rdp_allowed_remote_ip: "203.0.113.10"
```

変数を分離している理由は次の通りです。

- Playbook の可読性を上げる
- 値の変更をしやすくする
- 環境差分を吸収しやすくする

---

## Roles の説明

### `roles/account_policies`

Windows のアカウントポリシー関連を設定する role です。

主に次を設定します。

- パスワード履歴
- パスワード最大有効期限
- パスワード最小有効期限
- パスワード最小長
- アカウントロックアウトしきい値
- ロックアウト時間
- ロックアウトカウンタのリセット時間

この role は、**Windows のローカルセキュリティポリシーをコードで制御する例**としています

---

### `roles/windows_firewall`

Windows Firewall の設定を行う role です。

主に次を設定します。

- Domain / Private / Public の各プロファイルで Firewall を有効化
- WinRM 5986 を Linux control node からのみ許可
- RDP 3389 を管理端末の IP からのみ許可

この role は、**必要な通信だけを許可する**という考え方を説明しています

---

## タグの使い方

各 task にはタグを付けています。  
そのため、設定カテゴリ単位で Playbook を実行できます。

使用している主なタグは次の通りです。

- `password`
- `lockout`
- `firewall`
- `demo`

### パスワード関連のみ実行

```bash
ansible-playbook site.yml --tags password -e 'ansible_password=<Administrator password>'
```

### ロックアウト関連のみ実行

```bash
ansible-playbook site.yml --tags lockout -e 'ansible_password=<Administrator password>'
```

### Firewall 関連のみ実行

```bash
ansible-playbook site.yml --tags firewall -e 'ansible_password=<Administrator password>'
```

タグを使うことで、社内デモ時に

- 今回はパスワードポリシーだけ適用する
- 次は Firewall のみ適用する

といった見せ方がしやすくなります。

---

## Playbook 実行前提

Ansible を実行する前に、次の条件を満たしている必要があります。

- Windows インスタンスが起動している
- Windows 側で WinRM over HTTPS が有効になっている
- Linux から Windows の 5986/TCP へ到達できる
- Windows の Administrator パスワードが分かっている
- Linux 側に Ansible および必要コレクションがインストール済みである

このデモ構成では、これらの多くは Terraform の `user_data` により初期セットアップされます。

---

## 動作確認用 Playbook

`ping-windows.yml` は、Windows へ Ansible 接続できるか確認するための簡易 Playbook です。

```yaml
---
- name: Test Windows connectivity
  hosts: windows
  gather_facts: false
  tasks:
    - name: Win ping
      ansible.windows.win_ping:
```

これは ICMP の ping ではなく、**Ansible 経由で Windows モジュールが実行できるか**を確認するものです。

実行例:

```bash
cd ~/ansible
ansible-playbook ping-windows.yml -e 'ansible_password=<Administrator password>'
```

これが成功すれば、Linux から Windows に対して Ansible 実行が可能な状態です。

---

## 実行手順

### 1. Linux に接続

```bash
ssh -i /path/to/key.pem ec2-user@<linux_public_ip>
```

### 2. Ansible ディレクトリへ移動

```bash
cd ~/ansible
```

### 3. 接続確認

```bash
ansible-playbook ping-windows.yml -e 'ansible_password=<Administrator password>'
```

### 4. Playbook 実行

```bash
ansible-playbook site.yml -e 'ansible_password=<Administrator password>'
```

---

## Windows 側の確認方法

このデモでは、Playbook 実行の前後で Windows 側の設定状態を確認することで、  
**Ansible によって設定が変更されたこと**と、**再実行しても同じ状態に収束すること**を確認できます。

確認方法は、次の 2 通りがあります。

- GUI で確認する方法
- PowerShell / コマンドで確認する方法

デモでは、まず GUI で状態を見せ、最後に PowerShell で証跡を出す流れがわかりやすいです。

---

### 1. ローカルセキュリティポリシーの確認

#### GUI で確認

`Win + R` を押して、以下を実行します。

```text
secpol.msc
```

`Local Security Policy` が開いたら、次を確認します。

- `Security Settings` → `Account Policies` → `Password Policy`
- `Security Settings` → `Account Policies` → `Account Lockout Policy`

ここでは主に、次の項目を確認します。

- Minimum password length
- Maximum password age
- Enforce password history
- Account lockout threshold
- Account lockout duration
- Reset account lockout counter after

#### コマンドで確認

現在のローカルセキュリティポリシーをファイルへ出力します。

```powershell
secedit /export /cfg C:\Temp\secpol.cfg
notepad C:\Temp\secpol.cfg
```

必要な項目だけ確認する場合は、以下を使います。

```powershell
Select-String -Path C:\Temp\secpol.cfg -Pattern `
  "MinimumPasswordLength",
  "MaximumPasswordAge",
  "PasswordHistorySize",
  "LockoutBadCount",
  "LockoutDuration",
  "ResetLockoutCount"
```

---

### 2. Windows Firewall 状態の確認

#### GUI で確認

`Win + R` を押して、以下を実行します。

```text
wf.msc
```

`Windows Defender Firewall with Advanced Security` が開きます。  
ここで、次を確認します。

- Domain Profile が有効か
- Private Profile が有効か
- Public Profile が有効か

#### PowerShell で確認

```powershell
Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
```

`Enabled` が `True` になっていることを確認します。

---

### 3. RDP の制御状態の確認

#### GUI で確認

`wf.msc` を開き、左ペインの `Inbound Rules` を確認します。

Playbook で作成した、たとえば以下のようなルールを探します。

- `Allow RDP 3389 from admin IP`

確認ポイントは次の通りです。

- ルールが有効
- Action が Allow
- Local Port が 3389
- Remote Address が管理端末の IP に限定されている

#### PowerShell で確認

```powershell
Get-NetFirewallRule -DisplayName "Allow RDP 3389 from admin IP"
```

ポート条件を確認する場合:

```powershell
Get-NetFirewallRule -DisplayName "Allow RDP 3389 from admin IP" |
  Get-NetFirewallPortFilter
```

送信元 IP 制限を確認する場合:

```powershell
Get-NetFirewallRule -DisplayName "Allow RDP 3389 from admin IP" |
  Get-NetFirewallAddressFilter
```

---

### 4. WinRM の制御状態の確認

#### GUI で確認

`wf.msc` の `Inbound Rules` で、以下のような WinRM 用ルールを確認します。

- `Allow WinRM 5986 from Linux control node`

確認ポイントは次の通りです。

- ルールが有効
- Local Port が 5986
- Remote Address が Linux control node の private IP に限定されている

#### PowerShell で確認

まず WinRM サービスの状態を確認します。

```powershell
Get-Service WinRM
```

`Status` が `Running` であることを確認します。

次に、HTTPS listener を確認します。

```powershell
winrm enumerate winrm/config/listener
```

ここで、次を確認します。

- `Transport = HTTPS`
- `Port = 5986`

Firewall ルールも確認できます。

```powershell
Get-NetFirewallRule -DisplayName "Allow WinRM 5986 from Linux control node"
```

ポート条件:

```powershell
Get-NetFirewallRule -DisplayName "Allow WinRM 5986 from Linux control node" |
  Get-NetFirewallPortFilter
```

送信元 IP 制限:

```powershell
Get-NetFirewallRule -DisplayName "Allow WinRM 5986 from Linux control node" |
  Get-NetFirewallAddressFilter
```

---

## デモ時の確認の流れ

おすすめの流れは次の通りです。

### 1. Before を確認

Windows 側で以下を確認します。

- ローカルセキュリティポリシー
- パスワードポリシー
- アカウントロックアウトポリシー
- Windows Firewall 状態
- RDP / WinRM の制御状態

### 2. Playbook を実行

Linux 側で Playbook を実行します。

```bash
ansible-playbook site.yml -e 'ansible_password=<Administrator password>'
```

### 3. After を確認

もう一度同じ画面とコマンドを使って確認し、設定が反映されていることを見せます。

### 4. 再実行して冪等性を確認

同じ Playbook をもう一度実行し、不要な変更が発生しないことを確認します。

---

## 確認コマンドまとめ

```powershell
# ローカルセキュリティポリシーを書き出す
secedit /export /cfg C:\Temp\secpol.cfg

# パスワード / ロックアウト関連だけ確認
Select-String -Path C:\Temp\secpol.cfg -Pattern `
  "MinimumPasswordLength",
  "MaximumPasswordAge",
  "PasswordHistorySize",
  "LockoutBadCount",
  "LockoutDuration",
  "ResetLockoutCount"

# Firewall プロファイル確認
Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction

# RDP ルール確認
Get-NetFirewallRule -DisplayName "Allow RDP 3389 from admin IP"
Get-NetFirewallRule -DisplayName "Allow RDP 3389 from admin IP" | Get-NetFirewallPortFilter
Get-NetFirewallRule -DisplayName "Allow RDP 3389 from admin IP" | Get-NetFirewallAddressFilter

# WinRM サービス確認
Get-Service WinRM

# WinRM HTTPS listener 確認
winrm enumerate winrm/config/listener

# WinRM ルール確認
Get-NetFirewallRule -DisplayName "Allow WinRM 5986 from Linux control node"
Get-NetFirewallRule -DisplayName "Allow WinRM 5986 from Linux control node" | Get-NetFirewallPortFilter
Get-NetFirewallRule -DisplayName "Allow WinRM 5986 from Linux control node" | Get-NetFirewallAddressFilter
```

## 社内デモでの見せ方

おすすめの流れは次の通りです。

### 1. Before を見せる

Windows 側で以下を確認します。

- ローカルセキュリティポリシー
- パスワードポリシー
- アカウントロックアウトポリシー
- Windows Firewall 状態
- RDP / WinRM の制御状態

### 2. Playbook を実行する

Linux 側で以下を実行します。

```bash
ansible-playbook site.yml -e 'ansible_password=<Administrator password>'
```

### 3. After を見せる

再度 Windows 側で設定値を確認し、Playbook によって状態が変更されたことを見せます。

### 4. 再実行する

もう一度同じ Playbook を実行し、大きな変更が発生しないことを見せます。

これにより、次の点を説明しやすくなります。

- 手作業ではなくコード化されている
- 同じ状態に再現できる
- 冪等性がある

---

## このデモで重要な Ansible の考え方

### 1. 設定をコード化する

GUI 操作を手順書として残すのではなく、Playbook と role で状態として定義します。

### 2. role に分割する

`site.yml` にすべてを書くのではなく、設定カテゴリごとに role に分けることで保守しやすくします。

例:

- `account_policies`
- `windows_firewall`

### 3. 値を変数化する

設定値を `vars.yml` に逃がすことで、環境差分やポリシー変更に対応しやすくします。

### 4. タグで実行範囲を絞る

デモや検証時は、すべてを一気に適用するよりも、カテゴリごとに実行できる方がわかりやすくなります。

---

## 注意事項

- この構成は **社内デモ向け** を想定しています
- 自己署名証明書を利用しているため、証明書検証は無効化しています
- 本番環境では証明書や秘密情報の扱いを見直す必要があります
- `user_data` は初回起動時の初期セットアップ用途です
- 実運用では playbook を Git 管理する方が保守しやすいです

---

## 今後の拡張案

- role の追加
  - user rights assignment
  - audit policy
  - administrative templates
- private subnet 化
- SSM Session Manager 利用
- Ansible Vault の導入
- CI/CD 連携
- Playbook を Git から取得する構成への変更

---

## まとめ

このデモの中心は、**Linux 上の Ansible から Windows Server の設定を自動適用すること**です。

Terraform は AWS 基盤の作成と初期配置を担当し、Ansible は Windows の設定管理を担当します。

この役割分担により、次を分離して考えられるようになります。

- インフラ構築
- 初期セットアップ
- OS 設定適用

