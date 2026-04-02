# ansible-test_202604

# Windows のパスワード取得
aws ec2 wait password-data-available --instance-id <windows_instance_id>

aws ec2 get-password-data `
  --instance-id <windows_instance_id> `
  --priv-launch-key "C:\path\to\your-key.pem"


# Linux へ入って接続確認
ssh -i /path/to/your-key.pem ec2-user@<linux_public_ip>

cd ~/ansible
ansible-playbook ping-windows.yml -e 'ansible_password=取得したAdministratorパスワード'


# playbook 実行
cd ~/ansible
ansible-playbook site.yml -e 'ansible_password=取得したAdministratorパスワード'

タグごとに見せるなら
ansible-playbook site.yml --tags password -e 'ansible_password=取得したAdministratorパスワード'
ansible-playbook site.yml --tags lockout  -e 'ansible_password=取得したAdministratorパスワード'
ansible-playbook site.yml --tags firewall -e 'ansible_password=取得したAdministratorパスワード'
