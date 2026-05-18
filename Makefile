# -----------------------------------------
# Config
# -----------------------------------------
# Official Ubuntu image does NOT include /sbin/init or /lib/systemd/systemd.
# Official CentOS image does NOT include /sbin/init or /usr/lib/systemd/systemd.
# Custom build images are required for systemd support.
UBUNTU_IMAGE=ubuntu-systemd:latest
CENTOS_IMAGE=centos-systemd:latest

# Number of nodes per distro
UBUNTU_NODES=1
CENTOS_NODES=1

# Names will be ubuntu-1..N, centos-1..N
ANSIBLE_INVENTORY ?= inventory.yml
PLAYBOOK ?= playbook.yml

# -----------------------------------------
# Lint: ansible-lint for playbook and roles
# -----------------------------------------
.PHONY: lint
lint:
	@echo "==> Running ansible-lint on key role files and directories"
	ansible-lint tasks/
	ansible-lint handlers/
	ansible-lint defaults/
	ansible-lint vars/
	ansible-lint meta/

# -----------------------------------------
# Tools existence check (fail fast)
# -----------------------------------------
.PHONY: check
check:
	@command -v podman >/dev/null 2>&1 || { echo "podman not found"; exit 1; }
	@command -v ansible-playbook >/dev/null 2>&1 || { echo "ansible-playbook not found"; exit 1; }
	@command -v ansible-galaxy >/dev/null 2>&1 || { echo "ansible-galaxy not found"; exit 1; }

# -----------------------------------------
# Prepare: install required Ansible collection for Podman connection
# -----------------------------------------
.PHONY: deps
deps: check
	# Install the connection plugin for Podman containers
	ansible-galaxy collection install containers.podman --force

# -----------------------------------------
# Create systemd-enabled containers
# -----------------------------------------
.PHONY: build-ubuntu-image
build-ubuntu-image:
	@echo "==> Building Ubuntu systemd image"
	# Official Ubuntu image does NOT include /sbin/init or /lib/systemd/systemd.
	# Error example:
	# podman run -d --name ubuntu --privileged --systemd=always ubuntu:24.04 /sbin/init
	# Error: executable file `/sbin/init` not found in $PATH: No such file or directory
	# podman run -d --name ubuntu --privileged --systemd=always ubuntu:24.04 /lib/systemd/systemd
	# Error: executable file `/lib/systemd/systemd` not found in $PATH: No such file or directory
	# Therefore, custom Dockerfile.ubuntu-systemd is used.
	podman build -t ubuntu-systemd:latest -f Dockerfile.ubuntu-systemd .

.PHONY: build-centos-image
build-centos-image:
	@echo "==> Building CentOS systemd image"
	# Official CentOS image does NOT include /sbin/init or /usr/lib/systemd/systemd.
	# Therefore, custom Dockerfile.centos-systemd is used.
	podman build -t centos-systemd:latest -f Dockerfile.centos-systemd .

.PHONY: create-nodes
create-nodes: check build-ubuntu-image build-centos-image
	@echo "==> Creating Ubuntu nodes"
	@for i in $$(seq 1 $(UBUNTU_NODES)); do \
		name=ubuntu-$$i; \
		podman rm -f $$name >/dev/null 2>&1 || true; \
		echo "[create] $$name ($(UBUNTU_IMAGE))"; \
		podman run -d --name $$name --network podman --privileged --systemd=always $(UBUNTU_IMAGE); \
		# comm: Shows only the executable file name, truncated to 16 characters if longer. ; \
		podman exec $$name bash -lc 'ps -p 1 -o comm=' ; \
	done;
	@echo "==> Creating CentOS nodes"
	@for i in $$(seq 1 $(CENTOS_NODES)); do \
		name=centos-$$i; \
		podman rm -f $$name >/dev/null 2>&1 || true; \
		echo "[create] $$name ($(CENTOS_IMAGE))"; \
		podman run -d --name $$name --network podman --privileged --systemd=always $(CENTOS_IMAGE); \
		podman exec $$name bash -lc 'ps -p 1 -o comm=' ; \
	done

# -----------------------------------------
# Generate test playbook
# -----------------------------------------
.PHONY: generate-playbook
generate-playbook:
	@echo "==> Generating playbooks for each transfer case"

	@echo "---" > $(PLAYBOOK)
	@echo "- name: Test role" >> $(PLAYBOOK)
	@echo "  hosts: all" >> $(PLAYBOOK)
	@echo "  become: yes" >> $(PLAYBOOK)
	@echo "  vars:" >> $(PLAYBOOK)
	@echo "    users:" >> $(PLAYBOOK)
	@echo "      - name: root" >> $(PLAYBOOK)
	@echo "        groups: []" >> $(PLAYBOOK)
	@echo "        home_dir: /root" >> $(PLAYBOOK)
	@echo "      - name: user1" >> $(PLAYBOOK)
	@echo "        groups:" >> $(PLAYBOOK)
	@echo "          - adm" >> $(PLAYBOOK)
	@echo "        password: 'Th1sIsRand0mPassWord!'" >> $(PLAYBOOK)
	@echo "        home_dir: /home/user1" >> $(PLAYBOOK)
	@echo "  roles:" >> $(PLAYBOOK)
	@echo "    - role" >> $(PLAYBOOK)

# -----------------------------------------
# Generate dynamic Ansible inventory (Podman connection → SSH is not needed)
# -----------------------------------------
.PHONY: generate-inventory
generate-inventory:
	@echo "==> Generating $(ANSIBLE_INVENTORY) for test"
	@echo "# generated" > $(ANSIBLE_INVENTORY)
	@echo "all:" >> $(ANSIBLE_INVENTORY)
	@echo "  children:" >> $(ANSIBLE_INVENTORY)
	@echo "    ubuntu:" >> $(ANSIBLE_INVENTORY)
	@echo "      hosts:" >> $(ANSIBLE_INVENTORY)
	@for i in $$(seq 1 $(UBUNTU_NODES)); do \
		echo "        ubuntu-$$i:" >> $(ANSIBLE_INVENTORY); \
		echo "          ansible_connection: containers.podman.podman" >> $(ANSIBLE_INVENTORY); \
		echo "          ansible_python_interpreter: /usr/bin/python3" >> $(ANSIBLE_INVENTORY); \
	done;
	@echo "    centos:" >> $(ANSIBLE_INVENTORY)
	@echo "      hosts:" >> $(ANSIBLE_INVENTORY)
	@for i in $$(seq 1 $(CENTOS_NODES)); do \
		echo "        centos-$$i:" >> $(ANSIBLE_INVENTORY); \
		echo "          ansible_connection: containers.podman.podman" >> $(ANSIBLE_INVENTORY); \
		# CentOS Stream 9 has /usr/libexec/platform-python for system tools, but we install python3 in playbook anyway  ; \
		echo "          ansible_python_interpreter: /usr/bin/python3" >> $(ANSIBLE_INVENTORY); \
	done

# -----------------------------------------
# Run Ansible playbook
# -----------------------------------------
.PHONY: ansible
# Options: set via environment or command line
DRYRUN ?= 0
VERBOSE ?= 0
TAGS ?=

# Compose ansible-playbook options
ANSIBLE_OPTS =
ifneq ($(DRYRUN),0)
ANSIBLE_OPTS += --check --diff
endif
ifneq ($(VERBOSE),0)
ANSIBLE_OPTS += -vvv
endif
ifneq ($(TAGS),)
ANSIBLE_OPTS += --tags $(TAGS)
endif

ansible: generate-playbook generate-inventory
	ansible-playbook -i $(ANSIBLE_INVENTORY) $(PLAYBOOK) $(ANSIBLE_OPTS)

# -----------------------------------------
# Destroy all containers
# -----------------------------------------
.PHONY: destroy
destroy:
	@echo "==> Removing Ubuntu nodes"
	@for i in $$(seq 1 $(UBUNTU_NODES)); do \
		name=ubuntu-$$i; \
		echo "[rm] $$name"; \
		podman rm -f $$name >/dev/null 2>&1 || true; \
	 done;
	@echo "==> Removing CentOS nodes"
	@for i in $$(seq 1 $(CENTOS_NODES)); do \
		name=centos-$$i; \
		echo "[rm] $$name"; \
		podman rm -f $$name >/dev/null 2>&1 || true; \
	 done;
	@echo "==> Removing roles directory, tar.gz, inventory, playbook, and test files"
	rm -rf roles roles.tar.gz
	rm -rf *.retry
	rm -rf *.log
	rm -rf tmp test-output
	rm -f $(ANSIBLE_INVENTORY) $(PLAYBOOK) playbook.s3_only.yml playbook.s3_and_log.yml playbook.log_only.yml

.PHONY: clean
clean: destroy

# -----------------------------------------
# Test Ansible Galaxy role install & execution
# -----------------------------------------
.PHONY: test-role
test-role: deps create-nodes generate-playbook generate-inventory
	@echo "==> Packaging role for Galaxy install"
	rm -f roles.tar.gz
	tar czf roles.tar.gz --exclude=roles.tar.gz --exclude=.git --exclude=*.pyc --exclude=__pycache__ .
	@echo "==> Installing role via ansible-galaxy"
	rm -rf roles
	mkdir -p roles/role
	tar xzf roles.tar.gz -C roles/role
	@echo "==> Running test playbook"
	ansible-playbook -i $(ANSIBLE_INVENTORY) $(PLAYBOOK) $(ANSIBLE_OPTS) -e 'roles_path=./roles'
	@echo "==> Test completed"

# E2E test: environment setup, role test, cleanup
.PHONY: test-e2e
test-e2e: destroy test-role destroy
	@echo "Done."
