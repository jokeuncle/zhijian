#!/usr/bin/env python3
"""Verify the release in a relocated directory, with original source/build reads denied."""
import json
import os
import pathlib
import shutil
import subprocess
import tempfile

ROOT=pathlib.Path(__file__).resolve().parents[1]
APP=ROOT/"build/知间.app"
for source in (ROOT/"Sources").rglob("*.swift"):
    assert "/Users/" not in source.read_text() and "/home/" not in source.read_text(),source
assert "/Users/" not in (ROOT/".codex/config.toml").read_text()
for product in ("ZhijianApp","zhijian"):
    executable=APP/"Contents/MacOS"/product
    arches=subprocess.check_output(["lipo","-archs",str(executable)],text=True)
    assert "arm64" in arches and "x86_64" in arches,arches
    linked=subprocess.check_output(["otool","-L",str(executable)],text=True)
    dependencies="\n".join(line.strip() for line in linked.splitlines() if line.startswith("\t"))
    assert "/opt/homebrew/" not in dependencies and "/Users/" not in dependencies,dependencies

with tempfile.TemporaryDirectory(prefix="zhijian-portable-") as folder:
    target=pathlib.Path(folder)/"另一个下载目录 with spaces"/"知间.app"
    target.parent.mkdir()
    subprocess.run(["ditto",str(APP),str(target)],check=True)
    executable=target/"Contents/MacOS/zhijian"
    database=pathlib.Path(folder)/"another-user-data"/"library.sqlite"
    env=dict(os.environ); env.pop("ZHIJIAN_DATABASE",None)
    # No calls into the developer's checkout or .build directories may be needed by a downloaded app.
    profile=f'(version 1) (allow default) (deny file-read* (subpath "{ROOT}"))'
    def run(*args):
        command=["sandbox-exec","-p",profile,str(executable),"--database",str(database),*args]
        result=subprocess.run(command,cwd=folder,env=env,text=True,capture_output=True,check=True,timeout=30)
        return json.loads(result.stdout)
    assert run("stats")["entries"]==20
    assert run("get","residual-stream")["content"]["english"]=="Residual Stream"
    assert run("collections")[0]["entryIDs"][2]=="residual-stream"
    print("PASS relocated app with Unicode/spaces, unrelated cwd, source/build reads denied, seed and real library operations")
    subprocess.run(["python3",str(ROOT/"scripts/verify.py"),str(executable)],cwd=folder,env=env,check=True,timeout=60)

print("PASS both executables contain arm64+x86_64 and depend only on system frameworks/libraries")
