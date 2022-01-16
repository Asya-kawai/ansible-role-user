# Ansible Role For User Setting

[![CI](https://github.com/Asya-kawai/ansible-role-user/actions/workflows/ci.yml/badge.svg)](https://github.com/Asya-kawai/ansible-role-user/actions/workflows?query=workflow%3ACI)

Setup users and install Ruby,Python and OCaml.

And also changes login shell to zsh.

# Examples

Directory tree.

```
.
├── README.md
├── ansible.cfg
├── group_vars
│   ├── all.yml
│   ├── webserver_centos.yml
│   └── webserver_ubuntu.yml
├── inventory
└── webservers.yml
```

## Inventory file

```
[webservers:children]
webserver_ubuntu
webserver_centos

[webserver_ubuntu]
ubuntu ansible_host=10.10.10.10 ansible_port=22

[webserver_centos]
centos ansible_host=10.10.10.11 ansible_port=22
```

## Group Vars / Common settings(all.yml)

`all.yml` sets common variables.

```yaml
# Common settings
become: yes
ansible_user: root

# Private_key is saved in local host only!
ansible_ssh_private_key_file: ""
```

## Group Vars / Ubuntu(webserver_ubuntu.yml)

`webserver_ubuntu.yml` is `webservers` host's children.

This role refers `users(array)` variable including elements of `name`, `groups(array)`, `password` and `home_dir`.

```yaml
ansible_user: ubuntu
become: yes
ansible_become_password: 'ThisIsSecret!'

users:
  - name: aintek
    groups:
      - sudo
    password: 'ThisIsSecret!'
    home_dir: /home/aintek
```

## Group Vars / CentOS(webserver_centos.yml)

`webserver_ubuntu.yml` is `webservers` host's children.

```yaml
users:
  - name: aintek
    groups:
      - wheel
    password: 'ThisIsSecret!'
    home_dir: /home/aintek
```

## Playbook / Webservers(webservers.yml)

```yaml
- hosts: webservers
  become: yes
  module_defaults:
    apt:
      cache_valid_time: 86400
  roles:
    - user
```

# How to DryRun and Apply

DryRun

```
ansible-playbook -i inventory --private-key="~/.ssh/your_private_key" -CD webservers.yml --tags user
```

Apply

```
ansible-playbook -i inventory --private-key="~/.ssh/your_private_key" -D webservers.yml --tags user
```
