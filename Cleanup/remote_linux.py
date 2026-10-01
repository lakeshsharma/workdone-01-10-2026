"""Runs on a Linux agent through SSH. Input and output are one JSON object each.

The coordinator supplies an allowlisted workspace root. This program never follows
directory symlinks while measuring or removing data.
"""

import json
import hashlib
import base64
import os
import shutil
import stat
import sys
import time


def contained(root, path, allow_root=False):
    root = os.path.abspath(root)
    path = os.path.abspath(path)
    if not os.path.isdir(root) or os.path.islink(root):
        raise ValueError("Workspace root is missing or is a symlink")
    if os.path.commonpath((root, path)) != root or (path == root and not allow_root):
        raise ValueError("Path is outside the workspace root or is the root itself")
    current = root
    for component in os.path.relpath(path, root).split(os.sep):
        if component == ".":
            continue
        current = os.path.join(current, component)
        if os.path.islink(current):
            raise ValueError("A symlink occurs in the selected path")
    return path


def tree_size(path):
    total = 0
    errors = []
    digest = hashlib.sha256()
    stack = [path]
    base_device = os.stat(path).st_dev
    while stack:
        folder = stack.pop()
        try:
            with os.scandir(folder) as entries:
                for entry in sorted(entries, key=lambda value: value.name):
                    try:
                        info = os.stat(entry.path, follow_symlinks=False)
                        digest.update(repr((entry.path, info.st_dev, info.st_ino, info.st_size,
                                            info.st_mtime_ns, info.st_mode)).encode("utf-8", "replace"))
                        if stat.S_ISDIR(info.st_mode):
                            if info.st_dev != base_device or os.path.ismount(entry.path):
                                errors.append(f"{entry.path}: mount boundary; size excluded")
                            else:
                                stack.append(entry.path)
                        elif stat.S_ISREG(info.st_mode):
                            total += info.st_size
                    except OSError as exc:
                        errors.append(f"{entry.path}: {exc.strerror}")
        except OSError as exc:
            errors.append(f"{folder}: {exc.strerror}")
    return total, errors[:30], digest.hexdigest()


def item(path):
    info = os.lstat(path)
    kind = "symlink" if stat.S_ISLNK(info.st_mode) else "directory" if stat.S_ISDIR(info.st_mode) else "file"
    size, errors, fingerprint = tree_size(path) if kind == "directory" else (info.st_size if kind == "file" else 0, [], None)
    return {
        "name": os.path.basename(path), "path": path, "type": kind,
        "size": size, "mtime": info.st_mtime, "owner_uid": info.st_uid,
        "mode": stat.filemode(info.st_mode), "device": info.st_dev,
        "inode": info.st_ino, "errors": errors, "fingerprint": fingerprint,
    }


def process_sample():
    result = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            base = f"/proc/{name}"
            with open(f"{base}/stat", encoding="utf-8") as handle:
                fields = handle.read().rsplit(") ", 1)[1].split()
            try:
                with open(f"{base}/io", encoding="utf-8") as handle:
                    io = dict(line.split(": ", 1) for line in handle.read().splitlines())
                written = int(io.get("write_bytes", 0))
            except (OSError, ValueError):
                written = None
            try:
                with open(f"{base}/cmdline", "rb") as handle:
                    command = handle.read(180).replace(b"\0", b" ").decode("utf-8", "replace").strip()
            except OSError:
                command = "[unavailable]"
            result[name] = (int(fields[11]) + int(fields[12]), written, command)
        except (OSError, ValueError, IndexError):
            continue
    return result


def busy_processes():
    first = process_sample()
    time.sleep(0.4)
    second = process_sample()
    ticks = os.sysconf("SC_CLK_TCK")
    rows = []
    for pid, (cpu, written, command) in second.items():
        if pid not in first:
            continue
        prior_cpu, prior_written, _ = first[pid]
        rows.append({"pid": int(pid), "command": command,
                     "cpu_percent": round(max(0, cpu - prior_cpu) / ticks / 0.4 * 100, 1),
                     "write_bytes_per_second": max(0, written - prior_written) / 0.4
                     if written is not None and prior_written is not None else None})
    return sorted(rows, key=lambda row: (row["write_bytes_per_second"] or 0, row["cpu_percent"]), reverse=True)[:15]


def check_protected(path, protected):
    for candidate in protected:
        candidate = os.path.abspath(candidate)
        if os.path.commonpath((path, candidate)) in (path, candidate):
            raise ValueError("Selected folder contains or is within a protected path")


def main(request):
    root = os.path.abspath(request["root"])
    op = request["op"]
    if op == "scan":
        contained(root, root, allow_root=True)
        usage = shutil.disk_usage(root)
        filesystem = os.statvfs(root)
        return {"root": root, "disk": {"total": usage.total, "used": usage.used, "free": usage.free},
                "inodes": {"total": filesystem.f_files, "free": filesystem.f_favail},
                "probe_uid": os.geteuid(), "processes": busy_processes(), "listing": list_folder(root, root)}
    if op == "browse":
        path = contained(root, request["path"], allow_root=True)
        return {"root": root, "listing": list_folder(root, path)}
    if op == "inspect":
        path = contained(root, request["path"])
        check_protected(path, request.get("protected", []))
        return {"item": item(path)}
    if op == "delete":
        path = contained(root, request["path"])
        check_protected(path, request.get("protected", []))
        before = item(path)
        if before["type"] != "directory" or before["errors"]:
            raise ValueError("Only fully readable directories can be deleted")
        expected = request["expected"]
        if any(before[key] != expected[key] for key in ("device", "inode", "mtime", "size", "fingerprint")):
            raise ValueError("Folder changed since approval; scan and approve again")
        shutil.rmtree(path)
        return {"deleted": path, "bytes_before": before["size"], "completed_at": time.time()}
    raise ValueError("Unsupported operation")


def list_folder(root, path):
    if not os.path.isdir(path):
        raise ValueError("Selected path is not a directory")
    children = []
    with os.scandir(path) as entries:
        for entry in entries:
            children.append(item(entry.path))
    children.sort(key=lambda value: value["size"], reverse=True)
    return {"path": path, "is_root": path == root, "children": children,
            "size": sum(child["size"] for child in children)}


if __name__ == "__main__":
    try:
        request = json.loads(base64.b64decode(sys.argv[1])) if len(sys.argv) > 1 else json.load(sys.stdin)
        print(json.dumps({"ok": True, "data": main(request)}))
    except Exception as exc:
        print(json.dumps({"ok": False, "error": f"{type(exc).__name__}: {exc}"}))
