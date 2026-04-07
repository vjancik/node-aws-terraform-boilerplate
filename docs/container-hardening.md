# Container Security Hardening

Defence-in-depth settings for production containers. None of these affect normal application behaviour — they restrict what a compromised or misbehaving container can do.

## The settings

### `allowPrivilegeEscalation: false`

Prevents the process from gaining more privileges than it started with. Blocks setuid binaries, sudo, and anything that would let a process escalate to root after startup. Node.js never needs this.

### `capabilities: drop: ["ALL"]`

Linux capabilities are fine-grained root powers — binding to ports below 1024, opening raw sockets, loading kernel modules, etc. Node.js running on port 3000 needs none of them. Dropping all is safe and standard practice for web services.

If you ever need a specific capability back (e.g. `NET_BIND_SERVICE` to bind to port 80 directly), add it explicitly under `capabilities.add`.

### `seccompProfile: type: RuntimeDefault`

Applies the container runtime's default syscall filter. This blocks ~300 obscure Linux syscalls that no normal application uses. The `RuntimeDefault` profile is specifically designed not to break normal workloads — it's what Docker applies by default unless you disable it.

### `readOnlyRootFilesystem: true`

Makes the entire container filesystem read-only at the kernel level — including `/tmp`. The strongest of the four settings. If the container is compromised, an attacker cannot write malware, modify binaries, or persist anything to disk.

**Caveat:** Many runtimes write to `/tmp` (Node.js, Python's uvicorn, nginx). You need to explicitly mount writable paths back as `emptyDir` tmpfs volumes:

```yaml
# In the container spec:
securityContext:
  readOnlyRootFilesystem: true

volumeMounts:
  - name: tmp
    mountPath: /tmp

# In the pod spec:
volumes:
  - name: tmp
    emptyDir:
      medium: Memory  # tmpfs — lives in RAM, not on disk
```

Add additional mounts for any other paths the app writes to (e.g. nginx needs `/var/cache/nginx` and `/var/run`). Check at runtime — if the pod crashes on startup with a permission error, that's a missing mount.

---

## Kubernetes implementation

Add to the container spec in your Deployment (not the pod spec):

```yaml
containers:
  - name: backend
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      seccompProfile:
        type: RuntimeDefault
      # readOnlyRootFilesystem: true   # enable if you add /tmp emptyDir mount
```

---

## Docker / Docker Compose equivalent

Docker applies `RuntimeDefault` seccomp automatically. The other two need explicit config:

```yaml
services:
  backend:
    security_opt:
      - no-new-privileges:true   # equivalent to allowPrivilegeEscalation: false
    cap_drop:
      - ALL                      # equivalent to capabilities.drop: ["ALL"]
    # read_only: true            # equivalent to readOnlyRootFilesystem: true
    # tmpfs:
    #   - /tmp                   # writable /tmp if read_only is enabled
```

Or with `docker run`:

```bash
docker run \
  --security-opt no-new-privileges \
  --cap-drop ALL \
  # --read-only \
  # --tmpfs /tmp \
  your-image
```
