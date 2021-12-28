# Ansible Role For User Setting

Setup users and install Ruby,Python and OCaml.

# Examples

Directory tree.

```
.
├── README.md
├── ansible.cfg
├── authorized_keys
│   └── aintek
│        └── centos
│        └── ubuntu
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

```
# Common settings
become: yes
ansible_user: root

# Private_key is saved local host only!
ansible_ssh_private_key_file: ""
```

## Group Vars / Ubuntu(webserver_ubuntu.yml)

`webserver_ubuntu.yml` is `webservers` host's children.

This role refers `users(array)` variable including elements of `name`, `groups(array)` and `password`.

```
ansible_user: ubuntu
become: yes
ansible_become_password: 'ThisIsSecret!'

users:
  - name: aintek
    groups:
      - sudo
    password: 'ThisIsSecret!'
```

## Group Vars / CentOS(webserver_centos.yml)

`webserver_ubuntu.yml` is `webservers` host's children.

```
users:
  - name: aintek
    groups:
      - wheel
    password: 'ThisIsSecret!'
```

## Authorized_keys

This role copy `authorized_keys` in `./authorized_keys/{{ user.name }}/{{ inventory_hostname }}`.

So when you want to apply this role to `ubuntu` and `centos` for `aintek` user(you want to create aintek's authorized_keys),
you should make `./authorized_kyes/aintek/ubuntu` and `./authorized_kyes/aintek/centos`.

## Playbook / Webservers(webservers.yml)

```
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
