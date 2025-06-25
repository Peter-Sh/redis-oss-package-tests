# Redis Package Tests Action

A GitHub Action that runs Redis package tests using shunit2 in a QEMU virtual machine. This action uploads test files to the VM, installs dependencies, and executes comprehensive Redis package tests.

## Features

- **📦 Self-Contained**: Includes embedded shunit2 framework and test scripts - no external dependencies
- **🧪 Comprehensive Testing**: Uses shunit2 framework for robust test execution
- **📦 Package Installation**: Automatically installs Redis RPM packages if specified
- **🔧 Dependency Management**: Installs required test dependencies (redis-cli)
- **⚙️ Systemd Integration**: Tests Redis service management via systemd
- **🛡️ Requirement Checking**: Validates OS compatibility and system requirements
- **🧹 Automatic Cleanup**: Cleans up test files after execution
- **🔄 Portable**: Works across different repositories without additional setup

## Usage

### Basic Usage

```yaml
- name: Run Redis package tests
  uses: ./.github/actions/redis_package_tests
  with:
    qemu_ssh: ${{ env.QEMU_SSH }}
    qemu_shell: "qemu_shell"
```

### Advanced Usage with RPM Installation

```yaml
- name: Run Redis package tests with RPM installation
  uses: ./.github/actions/redis_package_tests
  with:
    qemu_ssh: ${{ env.QEMU_SSH }}
    qemu_shell: "qemu_shell"
    redis_rpm_files: "/tmp/redis-7.0.0-1.el8.x86_64.rpm /tmp/redis-tools-7.0.0-1.el8.x86_64.rpm"
    test_timeout: 600
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `qemu_ssh` | SSH command to connect to QEMU VM | Yes | - |
| `qemu_shell` | Shell command to execute scripts in QEMU VM | Yes | - |
| `redis_rpm_files` | Space-separated list of Redis RPM files to install | No | `""` |
| `test_timeout` | Timeout for test execution in seconds | No | `300` |

## Test Requirements

The test script includes several requirement checkers that will skip tests if conditions are not met:

### `require_id_like <id>`
- Checks if the OS ID matches the required distribution
- Example: `require_id_like rhel` checks for RHEL-like systems
- Uses `/etc/os-release` to determine OS compatibility

### `require_has_systemd`
- Verifies that systemd is available on the system
- Checks for the presence of `systemctl` command
- Required for systemd-based Redis service tests

## Test Cases

### `test_systemd_start_redis`
This test validates Redis server functionality through systemd:

1. **Requirement Validation**: Checks for systemd availability
2. **Service Management**: Stops any running Redis instance
3. **Service Start**: Starts Redis via `systemctl start redis`
4. **Status Verification**: Confirms Redis service is active
5. **Connectivity Test**: Validates Redis responds to ping commands
6. **Cleanup**: Stops Redis service after testing

## Environment Variables

The action sets the following environment variable for the test script:

- `REDIS_RPM_INSTALL_FILES`: Space-separated list of RPM files to install

## Dependencies

The action automatically installs the following dependencies in the VM:

- **redis-cli**: Redis command-line interface for testing connectivity
- **Package managers supported**: yum, dnf, apt

## Integration with QEMU Setup

This action is designed to work with the `qemu_setup_rootless` action:

```yaml
- name: Setup QEMU VM
  uses: ./.github/actions/qemu_setup_rootless
  with:
    image: rocky8.qcow2
    arch: x86_64

- name: Run Redis tests
  uses: ./.github/actions/redis_package_tests
  with:
    qemu_ssh: ${{ env.QEMU_SSH }}
    qemu_shell: "qemu_shell"
    redis_rpm_files: "redis-server.rpm redis-cli.rpm"
```

## Error Handling

- **Timeout Protection**: Tests will timeout after the specified duration
- **Requirement Skipping**: Tests are skipped (not failed) when requirements aren't met
- **Cleanup Guarantee**: Test files are cleaned up even if tests fail
- **Detailed Logging**: Comprehensive output for debugging test failures

## File Structure

```
.github/actions/redis_package_tests/
├── action.yaml         # GitHub Action definition
├── README.md          # This documentation
├── package_tests.sh   # Main test script with shunit2 tests
└── shunit2           # Testing framework (embedded)
```

The action is **self-contained** and includes all necessary test files and dependencies, making it usable across different repositories without requiring additional setup.

## Best Practices

1. **Set appropriate timeouts** for your test complexity
2. **Use specific RPM file paths** when testing package installation
3. **Check VM logs** if tests fail unexpectedly
4. **Ensure VM has sufficient resources** for Redis operation

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| SSH connection fails | QEMU VM not ready | Ensure QEMU setup completed successfully |
| redis-cli not found | Package installation failed | Check VM package manager and repositories |
| systemctl not found | Non-systemd system | Use different init system or skip systemd tests |
| Test timeout | Slow VM or complex tests | Increase `test_timeout` value |

### Debug Commands

```yaml
- name: Debug test environment
  if: failure()
  run: |
    ${{ env.QEMU_SSH }} "
      echo 'OS Information:'
      cat /etc/os-release

      echo 'Available commands:'
      command -v systemctl && echo 'systemctl: available' || echo 'systemctl: not found'
      command -v redis-cli && echo 'redis-cli: available' || echo 'redis-cli: not found'

      echo 'Redis service status:'
      systemctl status redis || echo 'Redis service not found'
    "
```
